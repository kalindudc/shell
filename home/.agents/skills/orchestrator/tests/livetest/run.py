#!/usr/bin/env python3
"""Prepare, drive, score and clean up the isolated orchestrator live test."""

import argparse
import json
import os
import shlex
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.dont_write_bytecode = True
from check import (ALERT, BARE_QUIET, BB_QUIET, BB_TITLE, FLEET_SCRIPT, KIT,
                   add_shutdown_evidence, bare_roster, bare_wakes, bb_ancestors,
                   bb_children, bb_json, bb_roster, capture, fleet_file, fleet_processes,
                   processes_before_down, read_json, read_text, skill_roots, thread_id)
from evidence import alert_units, bb_deliveries, permission_denials, sentinel_path


INJECT_SECONDS = 180
STABLE_SECONDS = 60
ERRORS = (OSError, ValueError, KeyError, RuntimeError, sqlite3.Error, subprocess.SubprocessError)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def bare_env(run):
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("BB_", "GIT_"))
           and key not in {"FLEET", "FLEET_MEMBER", "LIVETEST_PROTECT"}}
    paths = [entry for entry in env.get("PATH", os.defpath).split(os.pathsep)
             if os.path.isabs(entry) and "bb.app" not in entry.lower()
             and "bb.app" not in os.path.realpath(entry).lower()
             and shutil.which("bb", path=entry) is None]
    env["PATH"] = os.pathsep.join(paths)
    env["FLEET"] = str(run)
    return env


def adapter_args(harness, run):
    if harness == "pi":
        return []
    if harness == "claude":
        fleet_commands = sorted({shlex.join([python, str(FLEET_SCRIPT)])
                                 for python in ("python3", sys.executable)})
        # Scratch-only writes the skill expects: worktrees for parallel builders, and applying their patches.
        allowed_commands = ["python3 -c", "python3 -m unittest", "git status", "git diff", "git show", "git log", "ls", "cat",
                         "git worktree", "git apply"]
        tools = [f"Bash({command}{suffix})" for command in [*fleet_commands, *allowed_commands]
                 for suffix in ("", " *")]
        return ["--permission-prompts", "none", "--permission-mode", "acceptEdits",
                "--add-dir", str(KIT.parents[1]), str(run), "--allowedTools", *tools]

    return ["-s", "workspace-write", "-a", "never"]


def make_run(root, out):
    if root is None:
        storage = os.environ.get("FLEET") or os.environ.get("BB_THREAD_STORAGE")
        if storage:
            root = Path(storage) / "livetest"
        elif out is None:
            return Path(tempfile.mkdtemp(prefix="orchestrator-livetest-")).resolve()
        else:
            raise ValueError("--out requires --root, FLEET, or BB_THREAD_STORAGE")
    root = root.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    if out is None:
        return Path(tempfile.mkdtemp(prefix="run-", dir=root))
    run = (root / out.expanduser()).resolve()
    if run.parent != root:
        raise ValueError(f"--out must be a new directory directly under {root}")
    run.mkdir(mode=0o700)
    return run


def sentinel_command(run):
    source = ("import sys; from pathlib import Path; "
              "cursor = Path(sys.argv[2]); "
              "start = int(cursor.read_text().strip()) if cursor.exists() else 0; "
              "lines = Path(sys.argv[1]).read_text().splitlines(); "
              "sys.exit(not any(line.startswith('ALERT:') for line in lines[start:]))")
    return shlex.join([sys.executable, "-I", "-B", "-c", source,
                       str(run / "signals" / "alerts.txt"), str(run / "signals" / "reported-through.txt")])


def prepare(run, dry, sentinel):
    shutil.copytree(KIT / "scenario", run, dirs_exist_ok=True)
    goal = (KIT / "GOAL.md").read_text(encoding="utf-8")
    (run / "GOAL.md").write_text(goal.replace("@SKILL@", str(KIT.parents[1] / "SKILL.md"))
                                 .replace("@RUN@", str(run)).replace("@SENTINEL@", sentinel), encoding="utf-8")
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT="0")

    def git(*args):
        result = subprocess.run(["git", "-c", "core.hooksPath=/dev/null", *args], cwd=run, env=env,
                                text=True, capture_output=True, timeout=15)
        if result.returncode:
            raise RuntimeError(f"git {args[0]}: {result.stderr.strip()}")

    git("init", "--template=")
    info = run / ".git" / "info"
    info.mkdir(exist_ok=True)
    (info / "exclude").write_text("/GOAL.md\n/run.json\n/fleet.json\n/launch-env.json\n/protected-children.json\n"
                                  "/observations.jsonl\n/before-cleanup.json\n/after-cleanup.json\n/after-down.json\n"
                                  "/completion.json\n"
                                  "/result.json\n/result.md\n", encoding="utf-8")
    if not dry:
        git("add", "--", "calc.py", "test_calc.py", "deploy.sh", "signals/alerts.txt")
        git("-c", "user.name=Orchestrator live test", "-c", "user.email=livetest@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-m", "Seed isolated scenario")


def launch_command(args, run):
    goal = str(run / "GOAL.md")
    if args.harness == "bb":
        command = ["bb", "thread", "spawn", "--project", args.project, "--environment", str(run),
                   "--title", BB_TITLE, "--prompt-file", goal, "--json"]
    else:
        command = [sys.executable, str(FLEET_SCRIPT), "--fleet", str(run), "init", "--lead", "lead",
                   "--harness", args.harness, "--prompt-file", goal, "--cwd", str(run)]
    if args.model:
        command += ["--model", args.model]
    return command


def spawned_workspace(lead, run):
    reason = "environment not ready"
    for attempt in range(6):
        try:
            detail = bb_json("thread", "show", lead, timeout=1)
        except (RuntimeError, subprocess.TimeoutExpired) as exc:
            reason = str(exc)
        else:
            if detail["thread"]["id"] != lead:
                raise ValueError(f"BB returned a different thread for {lead}")
            environment = detail.get("environment") or {}
            path = environment.get("path")
            if path and Path(path).resolve() != run:
                raise ValueError(f"BB assigned {lead} to {path}, not scratch workspace {run}")
            if path and environment.get("id"):
                return environment["id"]
            reason = "environment has no ID or path yet"
        if attempt < 5:
            time.sleep(1)
    raise RuntimeError(f"cannot verify the scratch workspace for {lead}: {reason}")


def snapshot(protected):
    return {parent: {thread_id(row["id"]): row.get("title") for row in bb_children(parent)}
            for parent in protected}


def observe(run, meta, started, timeout):
    is_bb = meta["harness"] == "bb"
    quiet = BB_QUIET if is_bb else BARE_QUIET
    deadline = started + timeout
    last = None
    idle_since = None
    injected = False
    with (run / "observations.jsonl").open("w", encoding="utf-8", buffering=1) as log:
        while True:
            now = time.monotonic()
            if now >= deadline:
                return "timeout"
            if not injected and now >= started + INJECT_SECONDS:
                with (run / "signals" / "alerts.txt").open("a", encoding="utf-8") as signals:
                    signals.write("\n" + ALERT + "\n")
                record = sentinel_path(run)
                write_json(record, {**read_json(record), "injected_at": time.time()})
                injected = True
            roster = bb_roster(run, meta) if is_bb else bare_roster(run)
            if is_bb:
                active = sorted(row["id"] for row in roster if row["status"] == "active" and not row["archived"])
            else:
                turns = {row["id"]: row for row in roster if row["status"] == "running" and row["turn_pid"]}
                # Confirm both turns stayed live across the non-atomic registry scan.
                active = sorted(row["id"] for row in bare_roster(run) if turns.get(row["id"]) == row) if turns else []
            wakes = {} if is_bb else bare_wakes(run, roster)
            report = fleet_file(run, meta, "REPORT.md")
            try:
                report_revision = report.stat().st_mtime_ns if report is not None else None
            except FileNotFoundError:
                report_revision = None
            report_alerts = sorted(line for line in alert_units(read_text(report)) if line.startswith("ALERT:"))
            state = {"roster": roster, "active": active, "wakes": wakes, "report_alerts": report_alerts,
                     "injected": injected, "report_revision": report_revision}
            if state != last:
                sample = dict(state, at=time.time())
                if is_bb:
                    sample["ancestors"] = bb_ancestors(roster, meta["protected"])
                log.write(json.dumps(sample, sort_keys=True) + "\n")
                idle_since = None
                last = state
            if is_bb and roster[0]["parent"] is not None:
                return "not_top_level"
            lead_idle = any(row["id"] == meta["lead"] and row["status"] in {"idle", "archived"} for row in roster)
            if injected and report_revision is not None and lead_idle and all(row["status"] in quiet for row in roster):
                if idle_since is None:
                    idle_since = now
                if now - idle_since >= STABLE_SECONDS:
                    return "stable"
            else:
                idle_since = None
            interval = 2 if is_bb else 1
            targets = [deadline, now + interval] if injected else [deadline, now + interval, started + INJECT_SECONDS]
            time.sleep(max(0, min(targets) - time.monotonic()))


def capture_bb_logs(run, meta, state):
    roots = skill_roots(run, meta)
    findings = {"logs_scanned": 0, "denials": []}
    errors = []
    for thread in (row["id"] for row in state["roster"]):
        try:
            events = bb_json("thread", "log", thread, "--all", timeout=20)
            if not isinstance(events, list):
                raise ValueError("unexpected BB event log format")
        except ERRORS as exc:
            errors.append(f"{thread}: {exc}")
            continue
        findings["logs_scanned"] += 1
        if thread == meta["lead"]:
            state["bb_deliveries"] = list(bb_deliveries(events, thread))
        for event in events:
            if event.get("threadId") == thread:
                findings["denials"].extend({"thread": thread, "seq": event.get("seq"), **finding}
                                           for finding in permission_denials(event.get("data") or {}, run, roots))
    if errors:
        findings["error"] = "; ".join(errors)
        if "bb_deliveries" not in state:
            state["bb_log_error"] = findings["error"]
    state["log_evidence"] = findings


def cleanup(run, meta, start_env, state):
    errors = []

    def attempt(label, action):
        try:
            return action()
        except ERRORS as exc:
            errors.append(f"{label}: {exc}")
            return None

    if meta["harness"] == "bb":
        # Refresh once after stopping, in case a member registered work during teardown.
        roster = attempt("list BB scratch fleet", lambda: bb_roster(run, meta)) or state.get("roster", [])
        if not roster:
            lead = thread_id(meta["lead"])
            if lead in meta["protected"]:
                return errors + ["refusing to clean up a protected thread"]
            # Without a verified roster, only the ID returned by spawn belongs to this run.
            attempt(f"stop {lead}", lambda: bb_json("thread", "stop", lead))
            attempt(f"archive {lead}", lambda: bb_json("thread", "archive", lead))
            rows = attempt(f"verify archive {lead}", lambda: bb_json(
                "thread", "list", "--thread", lead, "--include-archived", "--include-hidden"))
            if not rows or not any(row["id"] == lead and row.get("archivedAt") is not None for row in rows):
                errors.append(f"could not verify archive of spawned lead {lead}")
            return errors
        for row in roster:
            if not row["archived"] and row["status"] not in BB_QUIET:
                attempt(f"stop {row['id']}", lambda: bb_json("thread", "stop", row["id"]))
        roster = attempt("refresh BB scratch fleet", lambda: bb_roster(run, meta)) or roster
        for row in reversed(roster):
            if not row["archived"]:
                if row["status"] not in BB_QUIET:
                    attempt(f"stop {row['id']}", lambda: bb_json("thread", "stop", row["id"]))
                attempt(f"archive {row['id']}", lambda: bb_json("thread", "archive", row["id"]))
    else:
        def call(verb, member, *flags):
            command = [sys.executable, str(FLEET_SCRIPT), "--fleet", str(run), "--as", "lead", verb, member, *flags]
            result = subprocess.run(command, cwd=run, env=start_env, text=True, capture_output=True, timeout=15)
            if result.returncode:
                raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f"exit {result.returncode}")

        roster = attempt("list bare scratch fleet", lambda: bare_roster(run)) or state.get("roster", [])
        roster = sorted(roster, key=lambda row: row["role"] != "lead")
        for row in roster:
            if not row["archived"] and row["status"] != "paused":
                attempt(f"pause {row['id']}", lambda: call("pause", row["id"]))
        roster = attempt("refresh bare scratch fleet", lambda: bare_roster(run)) or roster
        for row in sorted(roster, key=lambda row: row["role"] == "lead"):
            if not row["archived"]:
                if row["status"] != "paused":
                    attempt(f"pause {row['id']}", lambda: call("pause", row["id"]))
                attempt(f"archive {row['id']}", lambda: call("archive", row["id"], "--force"))

    final = attempt("verify scratch teardown", lambda: capture(run, meta))
    if final is not None:
        write_json(run / "after-cleanup.json", final)
        unarchived = [row["id"] for row in final["roster"] if not row["archived"]]
        processes = final["processes"] if meta["harness"] == "bb" else processes_before_down(final)
        if unarchived or processes or final.get("pending_wakes"):
            errors.append(f"still live: unarchived={unarchived}, processes={processes}, "
                          f"pending_wakes={final.get('pending_wakes')}")
    return errors


def down(run, env, state):
    command = [sys.executable, str(FLEET_SCRIPT), "--fleet", str(run), "down"]
    evidence = {"command": command, "exit_code": None, "processes": None}
    try:
        result = subprocess.run(command, cwd=run, env=env, text=True, capture_output=True, timeout=15)
        evidence["exit_code"] = result.returncode
        if result.returncode:
            evidence["error"] = result.stderr.strip() or result.stdout.strip()
    except ERRORS as exc:
        evidence["error"] = str(exc)
    try:
        roster = [*state.get("roster", []), {"runner_pid": state.get("supervisor_pid")}]
        deadline = time.monotonic() + 2
        while True:
            processes = fleet_processes(run, roster, state.get("wakes", {}))
            evidence["processes"] = processes
            if not processes or evidence["exit_code"] != 0 or time.monotonic() >= deadline:
                break
            time.sleep(0.1)
    except ERRORS as exc:
        evidence["probe_error"] = str(exc)
    return evidence


def score_and_write(run, harness, shutdown=None):
    command = [sys.executable, "-B", str(KIT / "check.py"), str(run)]
    if shutdown:
        command.append("--before-down")
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=90)
        try:
            score = json.loads(result.stdout)
        except ValueError as exc:
            raise RuntimeError(result.stderr.strip() or str(exc)) from exc
    except (KeyboardInterrupt,) + ERRORS as exc:
        score = {"final": not bool(shutdown), "passed": False,
                 "checks": [{"name": "checker_error", "pass": False,
                                             "evidence": {"error": str(exc) or "interrupted"}}]}
    finally:
        if shutdown:
            down_evidence = shutdown()
            write_json(run / "after-down.json", down_evidence)
    if shutdown:
        add_shutdown_evidence(score, down_evidence)
    if score.get("final") is not True:
        raise RuntimeError("refusing to publish a provisional score as final")
    write_json(run / "result.json", score)
    lines = [f"# {harness}: {'PASS' if score['passed'] else 'FAIL'}", ""]
    lines.extend(f"- {'PASS' if row['pass'] else 'FAIL'}: `{row['name']}`" for row in score["checks"])
    lines.extend(["", "See [result.json](result.json) for evidence."])
    (run / "result.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{lines[0][2:]} — {run / 'result.md'}", flush=True)
    return 0 if score["passed"] else 1


def run_live(args, run, command, env, meta):
    protected = meta["protected"]
    snapshots = {}
    state = {"roster": [], "error": "launch did not complete"}
    completion = {"reason": "error", "cleanup_errors": []}
    launch_attempted = False
    try:
        snapshots["before"] = snapshot(protected)
        write_json(run / "protected-children.json", snapshots)
        started = time.monotonic()
        launch_attempted = True
        launch = subprocess.run(command, cwd=run, env=env, check=True, capture_output=True, text=True, timeout=30)
        if args.harness == "bb":
            response = json.loads(launch.stdout)
            lead = thread_id(response["id"])
            if lead in protected:
                raise ValueError("spawn returned a protected BB id; refusing to touch it")
            meta["lead"] = lead
            write_json(run / "run.json", meta)
            meta["environment_id"] = spawned_workspace(lead, run)
            write_json(run / "run.json", meta)
        completion["reason"] = observe(run, meta, started, args.timeout_min * 60)
    except subprocess.CalledProcessError as exc:
        completion["error"] = exc.stderr.strip() or str(exc)
    except (KeyboardInterrupt,) + ERRORS as exc:
        completion["error"] = str(exc) or "interrupted"
    finally:
        if launch_attempted and meta.get("lead"):
            try:
                state = capture(run, meta)
            except ERRORS as exc:
                state = {"roster": [], "error": str(exc)}
        if args.harness == "bb" and state.get("roster"):
            try:
                capture_bb_logs(run, meta, state)
            except ERRORS as exc:
                state["bb_log_error"] = str(exc)
        write_json(run / "before-cleanup.json", state)
        if launch_attempted:
            if meta.get("lead"):
                completion["cleanup_errors"] = cleanup(run, meta, env, state)
            else:
                completion["cleanup_errors"] = ["spawn did not return a thread ID; inspect only the new scratch workspace"]
        try:
            snapshots["after"] = snapshot(protected)
        except ERRORS as exc:
            completion["snapshot_error"] = str(exc)
        write_json(run / "protected-children.json", snapshots)
        write_json(run / "completion.json", completion)
    shutdown = (lambda: down(run, env, state)) if launch_attempted and args.harness != "bb" else None
    return score_and_write(run, args.harness, shutdown)


def interrupt(signum, _frame):
    raise KeyboardInterrupt(f"received signal {signum}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--harness", required=True, choices=("bb", "pi", "claude", "codex"))
    parser.add_argument("--model")
    parser.add_argument("--root", type=Path, help="scratch root; defaults to FLEET/livetest, BB_THREAD_STORAGE/livetest, or a temporary directory")
    parser.add_argument("--out", type=Path, help="new directory directly under the scratch root")
    parser.add_argument("--protect", action="append", default=[], metavar="THREAD_ID",
                        help="protect this BB thread (repeatable; combines with comma-separated LIVETEST_PROTECT)")
    parser.add_argument("--project", default=os.environ.get("BB_PROJECT_ID"), help="local BB project ID")
    parser.add_argument("--timeout-min", default=30, type=int, help="timeout in positive whole minutes")
    parser.add_argument("--dry-run", action="store_true", help="prepare scratch files and print argv without launching")
    args = parser.parse_args()
    if args.timeout_min <= 0:
        parser.error("--timeout-min must be positive")
    try:
        if args.harness == "bb" and not args.project:
            if args.dry_run:
                parser.error("--project is required for BB dry runs outside a BB project")
            args.project = (bb_json("status").get("project") or {}).get("id")
            if not args.project:
                parser.error("--project is required outside a BB project")
        if not args.dry_run and args.harness != "bb" and not FLEET_SCRIPT.is_file():
            parser.error(f"missing bare runtime: {FLEET_SCRIPT}")
        protect_env = [value.strip() for value in os.environ.get("LIVETEST_PROTECT", "").split(",") if value.strip()]
        protected = sorted({thread_id(value) for value in [*protect_env, *args.protect]})
        run = make_run(args.root, args.out)
        sentinel = sentinel_command(run)
        with sentinel_path(run).open("x", encoding="utf-8") as record:
            json.dump({"sentinel": sentinel, "injected_at": None}, record)
            record.write("\n")
        prepare(run, args.dry_run, sentinel)
        meta = {"harness": args.harness, "protected": protected, "skill_dir": str(KIT.parents[1])}
        if args.harness == "bb":
            env = os.environ.copy()
            if not args.dry_run:
                meta["bb_data_dir"] = bb_json("status")["dataDir"]
        else:
            meta["lead"] = "lead"
            env = bare_env(run)
            bb_on_path = shutil.which("bb", path=env["PATH"]) is not None
            if bb_on_path:
                raise RuntimeError("refusing to start a bare harness with bb on PATH")
            write_json(run / "launch-env.json", {"keys": sorted(env), "bb_on_path": bb_on_path})
            write_json(run / "fleet.json", {
                "adapters": {harness: {"extra_args": adapter_args(harness, run)}
                             for harness in ("pi", "claude", "codex")},
                "broker": {"wake_checks": [sentinel]},
            })
        write_json(run / "run.json", meta)
        command = launch_command(args, run)
        print(f"Run directory: {run}\nLaunch: {shlex.join(command)}", flush=True)
        if args.dry_run:
            return 0
        signal.signal(signal.SIGTERM, interrupt)
        return run_live(args, run, command, env, meta)
    except ERRORS as exc:
        parser.exit(1, f"livetest: {exc}\n")


if __name__ == "__main__":
    sys.exit(main())
