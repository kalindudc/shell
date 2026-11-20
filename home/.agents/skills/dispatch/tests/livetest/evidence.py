"""Evidence normalization for the live-test driver and offline checker."""

import json
import math
import re
import shlex
from datetime import datetime
from pathlib import Path


def sentinel_path(run):
    return run.parent / f".{run.name}-driver.json"


def timestamp(value):
    return value if type(value) in (int, float) and math.isfinite(value) else None


def ordered(*times):
    return all(timestamp(value) is not None for value in times) and all(
        earlier <= later for earlier, later in zip(times, times[1:]))


def alert_units(text):
    units = set()
    for line in text.splitlines():
        line = re.sub(r"^(?:>\s*)+", "", line.strip())
        line = re.sub(r"^(?:[-+*]|\d+[.)])\s+", "", line)
        fields = line.strip("|").split("|") if line.startswith("|") and line.endswith("|") else [line]
        for field in fields:
            field = field.strip()
            for marker in ("**", "`"):
                if field.startswith(marker) and field.endswith(marker):
                    field = field[len(marker):-len(marker)].strip()
            units.add(field)
    return units


def iter_wakes(wakes):
    for owner, records in wakes.items():
        if any(not isinstance(value, dict) for value in records.values()):
            yield owner, "default", records  # Old snapshots only included the default loop.
        else:
            for loop, record in records.items():
                yield owner, loop, record


def bare_triggered_checks(samples, watcher_inboxes, command, injected_at):
    matches = {}
    for sample in samples:
        for watcher, loop, wake in iter_wakes(sample.get("wakes", {})):
            checked, fired = wake.get("last_check_at"), wake.get("last_fired_at")
            if (watcher not in watcher_inboxes or wake.get("every") != 30 or wake.get("check") != command
                    or type(wake.get("last_exit")) is not int or wake["last_exit"] != 0
                    or not ordered(injected_at, checked, fired)):
                continue
            delivered = next((msg["ts"] for msg in watcher_inboxes[watcher]
                              if msg.get("kind") == "wake" and msg.get("from") == watcher
                              and msg.get("wake_id") == loop and ordered(fired, msg.get("ts"))), None)
            if delivered is not None:
                matches[watcher, loop, delivered] = {"watcher": watcher, "id": loop,
                                                     "checked_at": checked, "delivered_at": delivered}
    return list(matches.values())


def bb_triggered_checks(jobs, watchers, command, injected_at):
    return [{"watcher": job["thread"], "id": job["id"], "checked_at": job["checked_at"],
             "delivered_at": job["delivered_at"]} for job in jobs
            if job["thread"] in watchers and job.get("kind") == "check" and job.get("every") == 30
            and job.get("command") == command and job.get("check_kind") == "exited"
            and type(job.get("exit_code")) is int and job["exit_code"] == 0
            and job.get("state") == "delivered" and job.get("outcome") == "met"
            and ordered(injected_at, job.get("checked_at"), job.get("delivered_at"))]


def bb_event_time(value):
    if timestamp(value) is not None:
        return value / 1000
    if isinstance(value, str):
        try:
            when = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if when.tzinfo is not None:
                return when.timestamp()
        except ValueError:
            pass
    return None


def bb_deliveries(events, lead):
    accepted = {}
    for event in events:
        if event.get("threadId") == lead and event.get("type") == "turn/input/accepted":
            data = event.get("data") or {}
            when = bb_event_time(event.get("createdAt"))
            request = data.get("clientRequestId")
            if request and when is not None:
                accepted.setdefault(request, when)
    for event in events:
        if event.get("threadId") != lead or event.get("type") != "client/turn/requested":
            continue
        data = event.get("data") or {}
        when = accepted.get(data.get("requestId"))
        if data.get("initiator") == "agent" and data.get("senderThreadId") and when is not None:
            inputs = data.get("inputGroups") or [data.get("input") or []]
            for group in inputs:
                if not isinstance(group, list):
                    continue
                text = "\n".join(part["text"] for part in group if part.get("type") == "text")
                yield {"kind": "message", "from": data["senderThreadId"], "ts": when,
                       "text": text, "seq": event.get("seq")}


def denial_scope(value, cwd, roots, explicit_path=False):
    if not isinstance(value, str) or not value:
        return None
    for root in roots:
        if re.search(r"(?<![\w./-])" + re.escape(str(root)) + r"(?![\w.-])", value):
            return str(root)
    try:
        tokens = shlex.split(value)
    except ValueError:
        tokens = []
    for token in [value] if explicit_path else tokens:
        token = token.rstrip(";)")
        if token == "$FLEET" or token.startswith(("$FLEET/", "${FLEET}/")):
            return str(roots[-1])
        if not explicit_path and "/" not in token and "." not in token:
            continue
        path = Path(token).expanduser()
        if not path.is_absolute():
            path = cwd / path
        for root in roots:
            try:
                path.resolve().relative_to(root)
            except (ValueError, OSError, RuntimeError):
                continue
            return str(root)
    return None


READ_TOOLS = {"read", "read_file"}
READ_COMMANDS = {"cat", "head", "tail", "less", "more", "ls", "wc", "grep", "rg"}
DENIED_READ = re.compile(
    r"^(?:cat|head|tail|less|more|ls|wc|grep|rg): (.+?): "
    r"(?:permission denied|operation not permitted|EACCES)\b", re.I,
)


def shell_read_scope(command, cwd, roots):
    if not isinstance(command, str) or "\n" in command:
        return None
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        words = list(lexer)
    except ValueError:
        return None
    if not words or any(word and all(char in "();<>|&" for char in word) for word in words):
        return None
    if Path(words[0]).name not in READ_COMMANDS:
        # Use the inner command from a logged shell invocation, never a script that merely mentions a path.
        if Path(words[0]).name in {"sh", "bash", "zsh"} and len(words) == 3 and words[1] in {"-c", "-lc"}:
            return shell_read_scope(words[2], cwd, roots)
        return None
    return next((scope for operand in words[1:] if not operand.startswith("-")
                 and (scope := denial_scope(operand, cwd, roots, explicit_path=True)) is not None), None)


def reported_read_scope(output, cwd, roots):
    return next((scope for line in output.splitlines() if (match := DENIED_READ.match(line))
                 and (scope := denial_scope(match[1].strip("'\""), cwd, roots, explicit_path=True)) is not None), None)


def permission_denials(event, cwd, roots):
    candidates = list(event.get("permission_denials") or [])
    item = event.get("item") or {}
    output = item.get("aggregated_output", item.get("aggregatedOutput", item.get("output", "")))
    exit_code = item.get("exit_code", item.get("exitCode"))
    failed = (type(exit_code) is int and exit_code != 0) or (exit_code is None and item.get("status") == "failed")
    # A successful cat may quote a permission error from the document it read.
    if failed and isinstance(output, str):
        scope = reported_read_scope(output, cwd, roots)
        if scope:
            yield {"tool": item.get("type"), "scope": scope}
    for candidate in candidates:
        tool = candidate.get("tool_name") or ""
        params = candidate.get("tool_input") or {}
        if tool.casefold() in READ_TOOLS:
            scope = denial_scope(params.get("file_path") or params.get("path"), cwd, roots, explicit_path=True)
        elif tool.casefold() in {"bash", "shell", "command_execution"}:
            scope = shell_read_scope(params.get("command"), cwd, roots)
        else:
            scope = None
        if scope:
            yield {"tool": tool, "scope": scope}


def bare_log_evidence(run, roots):
    paths = sorted(set((run / "agents").glob("*/runs/*.log")) | set((run / "agents").glob("*/runs/*.stderr")))
    denials = []
    for path in paths:
        agent_path = path.parents[1] / "agent.json"
        agent = json.loads(agent_path.read_text(encoding="utf-8")) if agent_path.is_file() else {}
        cwd = Path(agent.get("cwd") or run)
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            try:
                event = json.loads(line)
            except ValueError:
                if scope := reported_read_scope(line, cwd, roots):
                    denials.append({"log": str(path.relative_to(run)), "line": number, "scope": scope})
                continue
            if isinstance(event, dict):
                denials.extend({"log": str(path.relative_to(run)), "line": number, **match}
                               for match in permission_denials(event, cwd, roots))
    return {"logs_scanned": len(paths), "denials": denials}
