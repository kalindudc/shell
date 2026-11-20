#!/usr/bin/env python3
"""Read-only PR sentinel for a keeper's `ScheduleWakeup until.check`.

  pr-sentinel.py check    <registry.json> <snapshot.json>   exit 0 changed, 1 unchanged, 2 error
  pr-sentinel.py snapshot <registry.json> <snapshot.json> [--only owner/repo#1,owner/repo#2]

The registry is a JSON list of {"repo": "owner/name", "number": 123} objects (extra fields are
ignored). `check` fetches every registered PR with gh, compares the material fields with the
snapshot and prints one line per change. A PR missing from the snapshot counts as a change.
A fetch, parse or registry coverage failure exits 2, so a broken read is never mistaken for "unchanged".
Missing, empty or unrecognized check data is reported as unknown, not a pass.
`snapshot` writes the current state. With --only, it updates just the PRs you reviewed and keeps
the rest, so changes you haven't handled yet stay pending.
"""
import argparse
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

FIELDS = "state,isDraft,reviewDecision,headRefOid,statusCheckRollup"
FAILED = {"FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"}
PENDING = {"PENDING", "QUEUED", "IN_PROGRESS", "EXPECTED", "WAITING", "REQUESTED"}
PASSING = {"SUCCESS", "NEUTRAL", "SKIPPED"}


def key(pr):
    return f"{pr['repo']}#{pr['number']}"


def summarize_checks(rollup):
    if not isinstance(rollup, list) or not rollup:
        return "unknown", []
    failing, pending, unknown = [], False, False
    for check in rollup:
        if not isinstance(check, dict):
            unknown = True
            continue
        outcome = check.get("conclusion") or check.get("state") or check.get("status")
        result = outcome.upper() if isinstance(outcome, str) else ""
        status = check.get("status")
        if result in FAILED:
            name = check.get("name") or check.get("context")
            failing.append(name if isinstance(name, str) else "?")
        elif result in PENDING or (isinstance(status, str) and status.upper() in PENDING):
            pending = True
        elif result not in PASSING:
            unknown = True
    overall = "fail" if failing else "unknown" if unknown else "pending" if pending else "pass"
    return overall, sorted(set(failing))


def fetch(pr):
    out = subprocess.run(
        ["gh", "pr", "view", str(pr["number"]), "--repo", pr["repo"], "--json", FIELDS],
        capture_output=True, text=True, timeout=25,
    )
    if out.returncode != 0:
        raise RuntimeError(f"{key(pr)}: {out.stderr.strip() or 'gh failed'}")
    data = json.loads(out.stdout)
    checks, failing = summarize_checks(data.get("statusCheckRollup"))
    return key(pr), {
        "state": data["state"],
        "draft": data["isDraft"],
        "review": data.get("reviewDecision") or "",
        "head": data["headRefOid"],
        "checks": checks,
        "failing": failing,
    }


def load_json(path, what):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        raise RuntimeError(f"{what} not found: {path}")
    except json.JSONDecodeError as e:
        raise RuntimeError(f"{what} is not valid JSON ({path}): {e}")


def load_registry(path):
    reg = load_json(path, "registry")
    if not isinstance(reg, list) or not all(isinstance(p, dict) and "repo" in p and "number" in p for p in reg):
        raise RuntimeError("registry must be a list of {repo, number} objects")
    return reg


def fetch_all(reg):
    with ThreadPoolExecutor(max_workers=8) as pool:
        return dict(pool.map(fetch, reg))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=["check", "snapshot"])
    p.add_argument("registry")
    p.add_argument("snapshot")
    p.add_argument("--only", default="")
    a = p.parse_args()
    try:
        reg = load_registry(a.registry)
        live = fetch_all(reg)
        if len(live) != len(reg):
            raise RuntimeError(f"fetched {len(live)} of {len(reg)} PRs")
        if a.mode == "snapshot":
            snap = {}
            if a.only:
                snap = load_json(a.snapshot, "snapshot")
                for k in a.only.split(","):
                    if k not in live:
                        raise RuntimeError(f"--only names an unregistered PR: {k}")
                    snap[k] = live[k]
            else:
                snap = live
            with open(a.snapshot, "w") as f:
                json.dump(dict(sorted(snap.items())), f, indent=2)
            print(f"snapshot written: {len(snap)} PRs")
            return 0
        snap = load_json(a.snapshot, "snapshot")
        if not isinstance(snap, dict):
            raise RuntimeError("snapshot must be an object keyed by owner/repo#number")
        changes = []
        for k in sorted(live):
            before, now = snap.get(k), live[k]
            if before is None:
                changes.append(f"{k}: new, {now['state'].lower()}, checks {now['checks']}")
                continue
            diffs = [f"{f} {before.get(f)!r} -> {now[f]!r}" for f in now if before.get(f) != now[f]]
            if diffs:
                changes.append(f"{k}: " + "; ".join(diffs))
        print("\n".join(changes) if changes else "no material change")
        return 0 if changes else 1
    except Exception as e:  # any failure must surface as exit 2, never as "unchanged"
        print(f"sentinel error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
