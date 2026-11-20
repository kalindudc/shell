#!/usr/bin/env python3
"""Print a lead thread's child threads: role, status, time since last activity, parent notifications.

Usage: fleet-status.py [lead-thread-id] [--recursive] [--roles FILE] [--root-role top|child-lead]
                       [--stale-minutes N] [--all]

The lead defaults to $BB_THREAD_ID. Hidden children are included but get no depth or stale flags: they
usually belong to plugins (for example a thread's flare log), so leave them alone. Archived children are left
out unless --all is given. --recursive also lists the live children of each live child (a child lead's
workers), indented under their parent, which is what a cleanup sweep needs.

Roles come from the top fleet's roles.json ({"child_leads": {"<thread id>": "<stream>"}}), by default
roles.json in the lead's thread storage. Under the top lead a thread is a child lead if it is registered,
otherwise a worker. Under a child lead: workers. Under a worker: helpers. Under a helper: nothing.
With --recursive the script flags TOO-DEEP below a helper, and NESTED-LEAD for a registered child lead
anywhere but directly under the top lead. To audit a child lead's own subtree, pass --root-role child-lead
together with --roles <top fleet>/roles.json. The tree comes from parent links only: archiving also takes
hidden forks and lifecycle dependents, which this script can't see.

A thread is flagged STALE when it is idle and unchanged for longer than --stale-minutes (default 90).
For a permanent member or child lead, compare that with its cadence. For a task member, idle usually
means its result is ready to read, then archive.

This reads thread metadata only. It cannot see wake-ups or workspaces, so it is advisory: check each
permanent member's state file, and each worktree's git status before archiving.
"""
import argparse
import json
import os
import subprocess
import sys
import time

NEXT_ROLE = {"top": "worker", "child-lead": "worker", "worker": "helper", "helper": None}


def children(parent, include_archived):
    cmd = ["bb", "thread", "list", "--parent-thread", parent, "--include-hidden", "--json"]
    if include_archived:
        cmd.append("--include-archived")
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    return data if isinstance(data, list) else data["threads"]


def load_roles(path):
    if not path or not os.path.exists(path):
        return None
    with open(path) as f:
        return set(json.load(f).get("child_leads", {}))


def default_roles_path(lead):
    storage = os.environ.get("BB_THREAD_STORAGE")
    if not storage:
        return None
    return os.path.join(os.path.dirname(storage.rstrip("/")), lead, "roles.json")


def role_of(t, parent_role, child_leads):
    if t.get("visibility") == "hidden":
        return "plugin", []
    registered = t["id"] in (child_leads or set())
    if parent_role == "top":
        return ("child-lead" if registered else "worker"), []
    if registered:
        return "child-lead", ["NESTED-LEAD"]
    role = NEXT_ROLE[parent_role]
    if role is None:
        return "?", ["TOO-DEEP"]
    return role, []


def row(t, depth, role, flags, now, stale_minutes):
    age_min = int((now - t["updatedAt"]) / 60000)
    flags = list(flags)
    if t.get("archivedAt"):
        flags.append("archived")
    if t.get("hasPendingInteraction"):
        flags.append("NEEDS-ANSWER")
    if t["status"] == "error":
        flags.append("FAILED")
    hidden = role == "plugin"
    if t["status"] == "idle" and not t.get("archivedAt") and not hidden and age_min > stale_minutes:
        flags.append("STALE")
    if hidden:
        flags.append("hidden, leave")
    title = ("  " * depth + (t.get("title") or t.get("titleFallback") or "-"))[:60]
    return age_min, t["id"], role, t["status"], t.get("parentNotifications") or "-", title, " ".join(flags)


def walk(parent, parent_role, depth, args, now, child_leads, out):
    level = []
    for t in children(parent, args.all):
        role, flags = role_of(t, parent_role, child_leads)
        level.append((row(t, depth, role, flags, now, args.stale_minutes), t, role))
    level.sort(key=lambda item: item[0][0])
    for r, t, role in level:
        out.append(r)
        if args.recursive and not t.get("archivedAt") and role != "plugin":
            walk(t["id"], role if role != "?" else "helper", depth + 1, args, now, child_leads, out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("lead", nargs="?", default=os.environ.get("BB_THREAD_ID"))
    parser.add_argument("--recursive", action="store_true", help="include live members' own children")
    parser.add_argument("--roles", help="roles.json listing child leads (default: the lead's thread storage)")
    parser.add_argument("--root-role", choices=["top", "child-lead"], default="top")
    parser.add_argument("--stale-minutes", type=int, default=90)
    parser.add_argument("--all", action="store_true", help="include archived children")
    args = parser.parse_args()
    if not args.lead:
        sys.exit("No lead thread: pass its id or run inside a bb thread")

    if args.root_role == "child-lead" and not args.roles:
        sys.exit("--root-role child-lead needs --roles <top fleet>/roles.json, so nested leads are recognised")
    roles_path = args.roles or default_roles_path(args.lead)
    child_leads = load_roles(roles_path)
    rows = []
    walk(args.lead, args.root_role, 0, args, time.time() * 1000, child_leads, rows)

    print(f"{'id':<15} {'role':<10} {'status':<8} {'idle':>6} {'notify':<6} {'flags':<20} title")
    for age_min, tid, role, status, notify, title, flags in rows:
        idle = f"{age_min // 60}h{age_min % 60:02d}" if age_min >= 60 else f"{age_min}m"
        print(f"{tid:<15} {role:<10} {status:<8} {idle:>6} {notify:<6} {flags:<20} {title}")
    hidden = sum(1 for r in rows if r[2] == "plugin")
    archived = sum(1 for r in rows if "archived" in r[6])
    live = sum(1 for r in rows if r[2] != "plugin" and "archived" not in r[6])
    stale = sum(1 for r in rows if "STALE" in r[6])
    violations = sum(1 for r in rows if "TOO-DEEP" in r[6] or "NESTED-LEAD" in r[6])
    print(f"\n{live} live ({stale} stale), {hidden} hidden, {archived} archived shown. "
          f"Depth violations: {violations}." if args.recursive else
          f"\n{live} live ({stale} stale), {hidden} hidden, {archived} archived shown.")
    if child_leads is None:
        print(f"INCOMPLETE: no roles file at {roles_path}, so every direct member is treated as a worker "
              "and a child lead's helpers may show as TOO-DEEP.")
    print("Advisory: wake-ups and workspaces are not visible here.")


if __name__ == "__main__":
    main()
