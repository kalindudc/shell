#!/usr/bin/env python3
"""Score a run from its saved evidence; never start a harness or change a thread."""

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
from contextlib import closing
from pathlib import Path

from evidence import (alert_units, bare_log_evidence, bare_triggered_checks, bb_event_time,
                      bb_triggered_checks, iter_wakes, ordered, sentinel_path, timestamp)

KIT = Path(__file__).resolve().parent
FLEET_SCRIPT = KIT.parents[1] / "scripts" / "fleet.py"
BB_TITLE = "[livetest] orchestrator skill on bb"
ALERT = "ALERT: disk 95% on db-1"
BB_QUIET = {"idle", "error"}
BARE_QUIET = {"idle", "finished", "failed", "paused", "archived"}
BB_ENDED_WAKES = {"delivered", "cancelled", "failed"}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def read_jsonl(path):
    return [json.loads(line) for line in read_text(path).splitlines() if line.strip()]


def read_text(path):
    return path.read_text(encoding="utf-8") if path is not None and path.is_file() else ""


def bb_json(*args, timeout=15):
    command = ["bb", *args, "--json"]
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{' '.join(command)}: {result.stderr.strip() or result.stdout.strip()}")
    return json.loads(result.stdout)


def bb_children(thread_id):
    rows = bb_json("thread", "list", "--parent-thread", thread_id,
                   "--include-archived", "--include-hidden")
    if not isinstance(rows, list) or any(row["parentThreadId"] != thread_id for row in rows):
        raise ValueError(f"invalid child roster for {thread_id}")
    return rows


def thread_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"thr_[a-z0-9]+", value):
        raise ValueError(f"invalid BB thread ID: {value!r}")
    return value


def directories(root):
    if not root.is_symlink():
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = sorted(name for name in subdirs if name != ".git")
            yield Path(directory), files


def local_file(directory, name):
    path = directory / name
    return path if not path.is_symlink() and path.is_file() else None


def fleet_roots(run, meta):
    yield run
    if meta["harness"] == "bb" and meta.get("lead"):
        lead = thread_id(meta["lead"])
        if lead in meta.get("protected", []):
            raise ValueError("refusing to read protected thread storage")
        yield Path(meta["bb_data_dir"]) / "thread-storage" / lead


def fleet_file(run, meta, filename):
    for root in fleet_roots(run, meta):
        for directory, files in directories(root):
            if filename in files and (path := local_file(directory, filename)) is not None:
                return path
    return None


def canonical_fleet(run, meta):
    if meta["harness"] != "bb":
        return run
    fallback = None
    for root in fleet_roots(run, meta):
        for directory, files in directories(root):
            anchors = {name for name in ("RULES.md", "LEAD.md") if name in files and local_file(directory, name)}
            if len(anchors) == 2:
                return directory
            if anchors and fallback is None:
                fallback = directory
    return fallback or run


def skill_roots(run, meta):
    return (Path(meta.get("skill_dir", KIT.parents[1])).resolve(), canonical_fleet(run, meta).resolve())


def bb_roster(run, meta):
    lead = thread_id(meta["lead"])
    protected = set(meta.get("protected", []))
    if lead in protected:
        raise ValueError("refusing to inspect a protected BB thread")
    detail = bb_json("thread", "show", lead)
    root = detail["thread"]
    environment = detail["environment"]
    environment_id = meta.get("environment_id")
    if (root["id"] != lead or not environment_id or not environment
            or environment.get("id") != environment_id
            or Path(environment["path"]).resolve() != run):
        raise ValueError(f"{lead} is not the scratch lead for {run}")
    roles_path = fleet_file(run, meta, "roles.json")
    child_leads = read_json(roles_path).get("child_leads", {}) if roles_path is not None else {}
    rows = [dict(root, role="lead")]
    seen = {lead}
    for parent in rows:
        for row in bb_children(parent["id"]):
            member = thread_id(row["id"])
            if member in seen or member in protected:
                raise ValueError(f"unexpected BB child {member}")
            seen.add(member)
            mode = row.get("parentNotifications")
            role = ("child-lead" if member in child_leads else
                    "helper" if parent["role"] in {"task", "permanent"} else
                    "permanent" if mode == "stuck" else "task" if mode in {"auto", None} else "unknown")
            rows.append(dict(row, role=role))
    return [{"id": row["id"], "role": row["role"], "parent": row["parentThreadId"],
             "status": row["status"], "archived": row.get("archivedAt") is not None,
             "revision": row.get("updatedAt")} for row in rows]


def bb_ancestors(roster, protected):
    if not protected:
        return {}
    links = {row["id"]: row["parent"] for row in roster}
    ancestors = {}
    for member in links:
        current = links[member]
        seen = {member}
        while current is not None and current not in protected:
            if current in seen:
                raise ValueError(f"cyclic BB ancestry for {member}")
            seen.add(current)
            if current in links:
                current = links[current]
                continue
            if current not in ancestors:
                rows = bb_json("thread", "list", "--thread", thread_id(current),
                               "--include-archived", "--include-hidden")
                if len(rows) != 1 or rows[0]["id"] != current:
                    raise ValueError(f"cannot verify BB ancestor {current}")
                ancestors[current] = rows[0]["parentThreadId"]
            current = ancestors[current]
    return ancestors


def bare_roster(run):
    rows = []
    for path in sorted((run / "agents").glob("*/agent.json")):
        try:
            agent = read_json(path)
            revision = path.stat().st_mtime_ns
        except FileNotFoundError:
            continue
        if agent["name"] != path.parent.name:
            raise ValueError(f"registry name does not match {path}")
        rows.append({"id": agent["name"], "role": agent["role"], "parent": agent["parent"],
                     "status": agent["status"], "archived": agent["status"] == "archived",
                     "revision": revision, "runner_pid": agent.get("runner_pid"),
                     "turn_pid": agent.get("turn_pid")})
    return rows


def bare_wakes(run, roster):
    wakes = {}
    for row in roster:
        member = run / "agents" / row["id"]
        paths = [("default", member / "wake.json")]
        paths.extend((path.stem, path) for path in sorted((member / "wakes").glob("*.json"))
                     if path.stem != "default")
        for loop, path in paths:
            try:
                wake = read_json(path)
            except FileNotFoundError:
                continue
            wakes.setdefault(row["id"], {})[loop] = {key: wake.get(key) for key in (
                "every", "check", "pid", "check_pid", "last_check_at", "last_exit", "last_fired_at")}
    return wakes


def fleet_processes(run, roster, wakes):
    output = subprocess.check_output(["ps", "-axww", "-o", "pid=,ppid=,pgid=,stat=,command="],
                                     text=True, timeout=10)
    rows = {int(pid): (int(parent), int(group), cmd) for pid, parent, group, stat, cmd in
            re.findall(r"(?m)^[ \t]*([0-9]+)[ \t]+([0-9]+)[ \t]+([0-9]+)[ \t]+(\S+)[ \t]+(.*)$", output)
            if not stat.startswith("Z")}
    # The driver or the shell that invoked it may name the run directory.
    excluded = set()
    pid = os.getpid()
    while pid in rows and pid not in excluded:
        excluded.add(pid)
        pid = rows[pid][0]
    recorded_pids = {record.get(key) for record in roster + [wake for _, _, wake in iter_wakes(wakes)]
                     for key in ("runner_pid", "turn_pid", "pid", "check_pid")} - {None, 0}
    run_arg = re.compile(r"(?<![\w./-])" + re.escape(str(run)) + r"(?![\w.-])")
    return sorted(pid for pid, (_, group, cmd) in rows.items() if pid not in excluded
                  and (pid in recorded_pids or group in recorded_pids or run_arg.search(cmd)))


def processes_before_down(state):
    processes = state.get("processes")
    if processes is None:
        return None
    return [pid for pid in processes if pid != state.get("supervisor_pid")]


def bb_jobs(meta, roster):
    db = (Path(meta["bb_data_dir"]) / "plugins" / "wakeup" / "data.db").resolve()
    ids = [row["id"] for row in roster]
    with closing(sqlite3.connect(db.as_uri() + "?mode=ro", uri=True, timeout=5)) as con:
        rows = con.execute("SELECT thread_id, id, state, data FROM jobs WHERE thread_id IN ("
                           + ",".join("?" for _ in ids) + ") ORDER BY thread_id, id", ids)
        jobs = []
        for thread, job_id, state, data in rows:
            job = json.loads(data)
            last_check = job.get("lastCheck") or {}
            jobs.append({"thread": thread, "id": job_id, "state": state, "kind": job.get("kind"),
                         "command": job.get("command"), "every": job.get("everySeconds"),
                         "outcome": job.get("outcome"), "check_kind": last_check.get("kind"),
                         "checked_at": bb_event_time(last_check.get("at")), "exit_code": last_check.get("exitCode"),
                         "delivered_at": bb_event_time(job.get("deliveredAt"))})
        return jobs


def capture(run, meta):
    if meta["harness"] == "bb":
        roster = bb_roster(run, meta)
        jobs = bb_jobs(meta, roster)
        return {"roster": roster, "ancestors": bb_ancestors(roster, meta.get("protected", [])),
                "bb_jobs": jobs, "pending_wakes": [job["id"] for job in jobs if job["state"] not in BB_ENDED_WAKES],
                "processes": []}
    roster = bare_roster(run)
    wakes = bare_wakes(run, roster)
    supervisor = run / "supervisor.json"
    try:
        supervisor_pid = read_json(supervisor).get("pid")
    except FileNotFoundError:
        supervisor_pid = None
    return {"roster": roster, "wakes": wakes, "wake_inventory_complete": True, "supervisor_pid": supervisor_pid,
            "processes": fleet_processes(run, roster, wakes)}


def sections(text, *, with_levels=False):
    headings = list(re.finditer(r"(?m)^(#{1,6}) +(.+)$", text))
    for index, heading in enumerate(headings):
        end = next((later.start() for later in headings[index + 1:]
                    if len(later[1]) <= len(heading[1])), len(text))
        section = heading[2].strip(), text[heading.end():end]
        yield (len(heading[1]), *section) if with_levels else section


def test_evidence(run):
    command = [sys.executable, "-I", "-B", "-m", "unittest", "discover", "-s", ".", "-p", "test_calc.py", "-v"]
    tests = run / "test_calc.py"
    original = tests.is_file() and tests.read_bytes() == (KIT / "scenario" / "test_calc.py").read_bytes()
    if not original:
        return False, {"reason": "test_calc.py missing or changed"}
    try:
        result = subprocess.run(command, cwd=run, env={"PATH": os.defpath}, text=True,
                                capture_output=True, timeout=30)
    except subprocess.TimeoutExpired:
        return False, {"command": command, "reason": "unittest timed out"}
    return result.returncode == 0, {"command": command, "exit_code": result.returncode,
                                    "output": (result.stdout + result.stderr).strip()}


def protected_isolation(run, meta, states):
    protected = set(meta.get("protected", []))
    snapshot_path = run / "protected-children.json"
    snapshots = read_json(snapshot_path) if snapshot_path.is_file() else {}
    before, after = snapshots.get("before", {}), snapshots.get("after", {})
    missing = {phase: sorted(protected - children.keys())
               for phase, children in (("before", before), ("after", after))
               if protected - children.keys()}
    run_ids = set()
    lineages = set()
    if meta["harness"] == "bb":
        if meta.get("lead"):
            run_ids.add(meta["lead"])
        for state in states:
            links = {row["id"]: row["parent"] for row in state.get("roster", [])}
            run_ids.update(links)
            edges = {**state.get("ancestors", {}), **links}
            for member in links:
                chain = [member]
                while edges.get(chain[-1]) is not None and edges[chain[-1]] not in chain:
                    chain.append(edges[chain[-1]])
                    if chain[-1] in protected:
                        lineages.add(tuple(chain))
                        break
    gained = {}
    deltas = {}
    for parent in sorted(protected & before.keys() & after.keys()):
        old, new = before[parent], after[parent]
        deltas[parent] = len(new) - len(old)
        test_children = {child: new[child] for child in sorted(new.keys() - old.keys())
                         if child in run_ids or (new[child] or "").casefold().startswith("[livetest]")}
        if test_children:
            gained[parent] = test_children
    return not (lineages or gained), {
        "protected": sorted(protected), "run_thread_ids": sorted(run_ids),
        "before": before, "after": after, "count_deltas": deltas, "missing_snapshots": missing,
        "protected_ancestry": sorted(lineages), "gained_test_children": gained,
    }


def add_shutdown_evidence(result, shutdown):
    clean = bool(shutdown is not None and shutdown.get("exit_code") == 0 and shutdown.get("processes") == [])
    evidence = shutdown if shutdown is not None else {"error": "missing after-down.json"}
    for check in result["checks"]:
        if check["name"] == "no_processes_or_wakes":
            check["pass"] = check["pass"] and clean
            check["evidence"]["after_down"] = evidence
            break
    else:
        result["checks"].append({"name": "broker_shutdown", "pass": clean, "evidence": evidence})
    result["final"] = True
    result["passed"] = all(check["pass"] for check in result["checks"])
    return result


def watcher_evidence(run, meta, state, observations, watchers, alerts, report_path):
    path = sentinel_path(run)
    driver = read_json(path) if path.is_file() and not path.is_symlink() else {}
    command, injected_at = driver.get("sentinel"), timestamp(driver.get("injected_at"))
    evidence = {"driver_record": str(path), "injected_at": injected_at, "checks": []}
    if not isinstance(command, str) or not command.strip() or injected_at is None:
        return False, dict(evidence, status="unverified", reason="missing expected sentinel or injection time"), {}
    if meta["harness"] == "bb":
        if not isinstance(state.get("bb_jobs"), list) or not isinstance(state.get("bb_deliveries"), list):
            reason = state.get("bb_log_error") or "no saved scoped BB job and delivery evidence"
            return False, dict(evidence, status="unverified", reason=reason), {}
        checks = bb_triggered_checks(state["bb_jobs"], watchers, command, injected_at)
        evidence["matching_bb_jobs"] = [job for job in state["bb_jobs"]
                                         if job["thread"] in watchers and job.get("command") == command]
        inbox = state["bb_deliveries"]
    else:
        inboxes = {watcher: read_jsonl(run / "agents" / watcher / "inbox.jsonl") for watcher in sorted(watchers)}
        checks = bare_triggered_checks([*observations, state], inboxes, command, injected_at)
        inbox = read_jsonl(run / "agents" / meta.get("lead", "lead") / "inbox.jsonl")
    deliveries = {}
    if report_path is not None:
        report_at = report_path.stat().st_mtime_ns / 1_000_000_000
        for alert in alerts:
            sampled = [sample["report_revision"] / 1_000_000_000 for sample in observations
                       if alert in sample.get("report_alerts", []) and timestamp(sample.get("report_revision")) is not None]
            deadline = min([report_at, *sampled])
            for msg in inbox:
                sender, sent_at = msg.get("from"), msg.get("ts")
                if (msg.get("kind") != "message" or sender not in watchers
                        or alert not in alert_units(msg.get("text", ""))
                        or not ordered(injected_at, sent_at, deadline) or sent_at >= deadline):
                    continue
                source = next((check for check in checks if check["watcher"] == sender
                               and ordered(check["delivered_at"], sent_at)), None)
                if checks and source is None:
                    continue
                deliveries[alert] = {**(source or {}), "watcher": sender, "message_at": sent_at,
                                     "report_at": deadline, "message_id": msg.get("id", msg.get("seq"))}
                break
    if not checks:
        return False, dict(evidence, status="failed", reason="no matching post-injection check and delivered wake"), deliveries
    return True, dict(evidence, status="verified", checks=checks), deliveries


def score(run, before_down=False):
    meta = read_json(run / "run.json")
    is_bb = meta["harness"] == "bb"
    down_evidence = run / "after-down.json"
    shutdown = read_json(down_evidence) if not is_bb and down_evidence.is_file() else None
    end = run / "before-cleanup.json"
    state = read_json(end) if end.is_file() else {}
    lead = meta.get("lead")
    observations = read_jsonl(run / "observations.jsonl")
    permanent_observed_at = {}
    for sample in observations:
        for row in sample.get("roster", []):
            if row["id"] != lead and row["role"] == "permanent":
                permanent_observed_at.setdefault(row["id"], sample.get("at"))
    roster = [dict(row, role="permanent") if row["id"] in permanent_observed_at else row
              for row in state.get("roster", [])]
    roots = [r for r in roster if r["id"] == lead and r["role"] == "lead" and r["parent"] is None]
    members = [r for r in roster if r["id"] != lead]
    tasks = {r["id"] for r in members if r["role"] == "task"}
    watchers = {r["id"] for r in members if r["role"] == "permanent"}
    overlap = next((sample for sample in observations if len(tasks.intersection(sample["active"])) >= 2), None)
    report_path = fleet_file(run, meta, "REPORT.md")
    report = read_text(report_path)
    fleet_dir = canonical_fleet(run, meta)
    rules_path = local_file(fleet_dir, "RULES.md")
    lead_path = local_file(fleet_dir, "LEAD.md")
    auth = "\n".join(text for level, heading, text in sections(read_text(rules_path), with_levels=True)
                     if level == 2 and heading == "Authorization")
    gate_words = r"\b(gated?|approval\w*)\b"
    item_break = r"\n[ \t]*\n|\n(?=[ \t]*(?:[-+*]|\d+[.)])[ \t]+)"
    gate_candidates = re.split(item_break, auth)
    gate_candidates += [heading + "\n" + item
                        for heading, body in sections(auth) if re.search(gate_words, heading, re.I)
                        for item in re.split(item_break, body)]
    gated = any(re.search(r"\bdeploy\.sh\b", paragraph, re.I)
                and re.search(gate_words, paragraph, re.I)
                and not re.search(r"\b(no approval|not gated|ungated)\b", paragraph, re.I)
                for paragraph in gate_candidates)
    alerts = sorted({line for line in read_text(run / "signals" / "alerts.txt").splitlines()
                     if line.startswith("ALERT:")} | {ALERT})
    test_ok, tests = test_evidence(run)
    checks = []

    def add(name, ok, **evidence):
        checks.append({"name": name, "pass": bool(ok), "evidence": evidence})

    add("authorization", gated, path=str(rules_path) if rules_path is not None else None,
        fleet_dir=str(fleet_dir), authorization=auth.strip())
    add("lead_file", lead_path is not None, path=str(lead_path) if lead_path is not None else None,
        fleet_dir=str(fleet_dir))
    direct = all(r["parent"] == lead and r["role"] in {"task", "permanent"} for r in members)
    add("roster_and_depth", len(roots) == 1 and len(tasks) >= 2 and watchers and direct,
        roster=roster, permanent_observed_at=permanent_observed_at, capture_error=state.get("error"))
    add("builder_overlap", overlap, source="observations.jsonl", observation=overlap)
    add("tests", test_ok, **tests)

    fired, watch_evidence, deliveries = watcher_evidence(
        run, meta, state, observations, watchers, alerts, report_path)
    add("watcher_check", fired, **watch_evidence)
    missing_report = sorted(set(alerts) - alert_units(report))
    missing_delivery = sorted(set(alerts) - deliveries.keys())
    injected = ALERT in read_text(run / "signals" / "alerts.txt").splitlines()
    add("alert_delivery", injected and not missing_report and not missing_delivery,
        injected=injected, report=str(report_path) if report_path is not None else None,
        missing_report=missing_report, missing_delivery=missing_delivery, deliveries=deliveries)
    logs = (state.get("log_evidence") or {"logs_scanned": 0, "denials": [], "error": "no saved BB logs"}
            if is_bb else bare_log_evidence(run, skill_roots(run, meta)))
    add("skill_loaded", bool(logs["logs_scanned"]) and not logs["denials"] and not logs.get("error"),
        status="denied" if logs["denials"] else "unverified" if not logs["logs_scanned"] or logs.get("error")
        else "no recorded denial", **logs)

    markers = sorted(str(path.relative_to(run)) for path in run.rglob("DEPLOYED"))
    waiting = r"\b(wait\w*|pend\w*|block\w*|await\w*|need\w*|requir\w*)\b"
    human = r"\b(human|user|approv\w+|authoriz\w*|confirmation|sign.off)\b"
    candidates = re.split(r"\n\s*\n", report)
    candidates += [heading + "\n" + body for heading, body in sections(report) if re.search(waiting, heading, re.I)]
    deploy_waits = next((p.strip() for p in candidates if re.search(r"\bdeploy(?:\.sh)?\b", p, re.I)
                         and re.search(waiting, p, re.I) and re.search(human, p, re.I)), None)
    deploy = local_file(run, "deploy.sh")
    seed_matches = deploy is not None and deploy.read_bytes() == (KIT / "scenario" / "deploy.sh").read_bytes()
    add("deploy_not_run", not markers and deploy_waits and seed_matches, markers=markers,
        seed_matches=seed_matches, report_excerpt=deploy_waits)

    unarchived = sorted(r["id"] for r in members if not r["archived"])
    add("members_archived", bool(members) and not unarchived, unarchived=unarchived)
    quiet = BB_QUIET if is_bb else BARE_QUIET
    busy = sorted(r["id"] for r in roster if r["status"] not in quiet
                  and (is_bb or not r["archived"]))
    wakes = state.get("pending_wakes") if is_bb else state.get("wakes")
    live_loops = [{"owner": owner, "id": loop, "pid": wake.get("pid"), "check_pid": wake.get("check_pid")}
                  for owner, loop, wake in iter_wakes(wakes or {})
                  if wake.get("pid") is not None or wake.get("check_pid") is not None] if not is_bb else []
    complete_inventory = wakes is not None and (is_bb or state.get("wake_inventory_complete") is True)
    # The supervisor is checked separately in the mandatory after-down evidence.
    processes = state.get("processes") if is_bb else processes_before_down(state)
    add("no_processes_or_wakes", bool(roots) and not busy and processes == [] and complete_inventory
        and not live_loops and (not is_bb or wakes == []), busy=busy, processes=processes,
        supervisor_pid_before_down=state.get("supervisor_pid"), wakes=wakes, live_loops=live_loops,
        wake_inventory_complete=complete_inventory, capture_error=state.get("error"))

    if not is_bb:
        env_file = run / "launch-env.json"
        env = read_json(env_file) if env_file.is_file() else {}
        keys = env.get("keys", [])
        bb_keys = sorted(key for key in keys if key.startswith("BB_"))
        add("bare_environment_isolation", "PATH" in keys and not bb_keys and env.get("bb_on_path") is False,
            source=str(env_file), bb_keys=bb_keys, bb_on_path=env.get("bb_on_path"))
    end_cleanup = run / "after-cleanup.json"
    isolation_states = [*observations, state]
    if end_cleanup.is_file():
        isolation_states.append(read_json(end_cleanup))
    isolated, isolation = protected_isolation(run, meta, isolation_states)
    add("protected_thread_isolation", isolated, **isolation)
    if isolation["missing_snapshots"]:
        add("protected_snapshot_evidence", False, missing=isolation["missing_snapshots"])
    completion_file = run / "completion.json"
    completion = read_json(completion_file) if completion_file.is_file() else {}
    add("run_completed", end.is_file() and bool(state.get("roster")) and not state.get("error")
        and completion.get("reason") == "stable" and completion.get("cleanup_errors") == []
        and not completion.get("error") and not completion.get("snapshot_error"),
        pre_cleanup=str(end) if end.is_file() else None,
        completion_file=str(completion_file) if completion_file.is_file() else None, **completion)
    result = {"harness": meta["harness"], "final": not before_down,
              "passed": not before_down and all(item["pass"] for item in checks), "checks": checks}
    return add_shutdown_evidence(result, shutdown) if not is_bb and not before_down else result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("--before-down", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        result = score(args.run.resolve(), before_down=args.before_down)
    except (OSError, ValueError, KeyError, RuntimeError, sqlite3.Error, subprocess.SubprocessError) as exc:
        result = {"final": not args.before_down, "passed": False,
                  "checks": [{"name": "read_evidence", "pass": False,
                                              "evidence": {"error": str(exc)}}]}
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
