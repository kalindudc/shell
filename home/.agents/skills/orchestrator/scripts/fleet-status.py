#!/usr/bin/env python3
"""Print a lead thread's child threads: status, time since last activity, parent notifications.

Usage: fleet-status.py [lead-thread-id] [--recursive] [--stale-minutes N] [--all]
The lead defaults to $BB_THREAD_ID. Hidden children are included but never flagged STALE: they
usually belong to plugins (for example a thread's flare log), so leave them alone. Archived children are left out
unless --all is given. --recursive also lists the live children of each live child (a sub-lead's
helpers), indented under their parent, which is what a cleanup sweep needs.

A child is flagged STALE when it is idle and has not changed for longer than --stale-minutes
(default 90). For a permanent member, compare that with its cadence. For a task member, idle
usually means its result is ready to read, then archive.

This reads thread metadata only. It cannot see a member's wake-ups, so it is advisory: check each
permanent member's state file for its last successful check and next wake.
"""
import argparse
import json
import os
import subprocess
import sys
import time


def children(parent, include_archived):
    cmd = ["bb", "thread", "list", "--parent-thread", parent, "--include-hidden", "--json"]
    if include_archived:
        cmd.append("--include-archived")
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    return data if isinstance(data, list) else data["threads"]


def row(t, depth, now, stale_minutes):
    age_min = int((now - t["updatedAt"]) / 60000)
    flags = []
    if t.get("archivedAt"):
        flags.append("archived")
    if t.get("hasPendingInteraction"):
        flags.append("NEEDS-ANSWER")
    if t["status"] == "error":
        flags.append("FAILED")
    hidden = t.get("visibility") == "hidden"
    if t["status"] == "idle" and not t.get("archivedAt") and not hidden and age_min > stale_minutes:
        flags.append("STALE")
    if hidden:
        flags.append("hidden, leave")
    title = ("  " * depth + (t.get("title") or t.get("titleFallback") or "-"))[:60]
    return age_min, t["id"], t["status"], t.get("parentNotifications") or "-", title, " ".join(flags)


def walk(parent, depth, args, now, out):
    level = [(row(t, depth, now, args.stale_minutes), t) for t in children(parent, args.all)]
    level.sort(key=lambda pair: pair[0][0])
    for r, t in level:
        out.append(r)
        if args.recursive and not t.get("archivedAt"):
            walk(t["id"], depth + 1, args, now, out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("lead", nargs="?", default=os.environ.get("BB_THREAD_ID"))
    parser.add_argument("--recursive", action="store_true", help="include live members' own children")
    parser.add_argument("--stale-minutes", type=int, default=90)
    parser.add_argument("--all", action="store_true", help="include archived children")
    args = parser.parse_args()
    if not args.lead:
        sys.exit("No lead thread: pass its id or run inside a bb thread")

    rows = []
    walk(args.lead, 0, args, time.time() * 1000, rows)

    print(f"{'id':<15} {'status':<8} {'idle':>6} {'notify':<6} {'flags':<20} title")
    for age_min, tid, status, notify, title, flags in rows:
        idle = f"{age_min // 60}h{age_min % 60:02d}" if age_min >= 60 else f"{age_min}m"
        print(f"{tid:<15} {status:<8} {idle:>6} {notify:<6} {flags:<20} {title}")
    hidden = sum(1 for r in rows if "hidden" in r[5])
    live = sum(1 for r in rows if "archived" not in r[5] and "hidden" not in r[5])
    stale = sum(1 for r in rows if "STALE" in r[5])
    archived = sum(1 for r in rows if "archived" in r[5])
    print(f"\n{live} live ({stale} stale), {hidden} hidden, {archived} archived shown. "
          "Advisory: wake-ups are not visible here.")


if __name__ == "__main__":
    main()
