#!/usr/bin/env python3
"""Read-only PR sentinel for a keeper's `ScheduleWakeup until.check`.

  pr-sentinel.py check    <registry.json> <snapshot.json> [--api CMD]
  pr-sentinel.py snapshot <registry.json> <snapshot.json> [--api CMD] [--only owner/repo#1,owner/repo#2]

The registry is a JSON list of {"repo": "owner/name", "number": 123} objects (extra fields are
ignored). `check` compares live PRs with the snapshot and prints one line per change, exiting 0
on a change or 1 if unchanged. A PR missing from the snapshot counts as a change.
`--api` selects a read-only command that returns JSON from a GitHub-compatible REST API.
The default is `gh api {endpoint}`. The template can also use `{repo}`.
A fetch, parse or registry coverage failure exits 2, so a broken read is never mistaken for "unchanged".
Missing, empty or unrecognized check data is reported as unknown, not a pass.
`snapshot` writes the current state. With --only, it updates just the PRs you reviewed and keeps
the rest, so changes you haven't handled yet stay pending.
"""
import argparse
import json
import shlex
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

DEFAULT_API = "gh api {endpoint}"
READ_TIMEOUT = 25
FETCH_TIMEOUT = 37
PAGE_SIZE = 100
MAX_PAGES = 30
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


def read_api(api, repo, endpoint, deadline):
    timeout = min(READ_TIMEOUT, deadline - time.monotonic())
    if timeout <= 0:
        raise RuntimeError(f"{endpoint}: fetch deadline exceeded")
    command = [arg.format(repo=repo, endpoint=endpoint) for arg in api]
    try:
        out = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(f"{endpoint}: API command timed out") from e
    if out.returncode != 0:
        detail = out.stderr.strip() or f"API command exited {out.returncode}"
        raise RuntimeError(f"{endpoint}: {detail}")
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"{endpoint}: API response is not valid JSON: {e}") from e


def read_pages(api, repo, endpoint, deadline, field=None):
    rows = []
    page = 1
    separator = "&" if "?" in endpoint else "?"
    while True:
        if page > MAX_PAGES:
            raise RuntimeError(f"{endpoint}: more than {MAX_PAGES} pages")
        url = endpoint if page == 1 else f"{endpoint}{separator}page={page}"
        data = read_api(api, repo, url, deadline)
        if field is None:
            if not isinstance(data, list) or not all(isinstance(row, dict) for row in data):
                raise RuntimeError(f"{url}: expected a JSON array of objects")
            items = data
            # Some servers cap pages below the size asked for, so only an empty page ends the list.
            has_more = bool(items)
        else:
            items = data.get(field) if isinstance(data, dict) else None
            if not isinstance(items, list):
                return rows + [None]
            total = data.get("total_count")
            has_more = isinstance(total, int) and len(rows) + len(items) < total
            if has_more and not items:
                return rows + [None]
        rows.extend(items)
        if not has_more:
            return rows
        page += 1


def review_decision(reviews, head):
    latest = {}
    for review in reviews:
        state = review["state"]
        if state in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED") and review["user"] is not None:
            latest[review["user"]["login"]] = review
    current = {review["state"] for review in latest.values() if review.get("commit_id") == head}
    if "CHANGES_REQUESTED" in current:
        return "CHANGES_REQUESTED"
    return "APPROVED" if "APPROVED" in current else ""


def latest_activity(rows):
    stamps = [row.get(field) for row in rows for field in ("updated_at", "submitted_at", "created_at")]
    return max((stamp for stamp in stamps if isinstance(stamp, str)), default="")


def fetch(pr, api, requests, deadline):
    repo, number = pr["repo"], pr["number"]
    pull = f"repos/{repo}/pulls/{number}"
    page = f"?per_page={PAGE_SIZE}"
    details = requests.submit(read_api, api, repo, pull, deadline)
    reviews = requests.submit(read_pages, api, repo, f"{pull}/reviews{page}", deadline)
    issue_comments = requests.submit(
        read_pages, api, repo, f"repos/{repo}/issues/{number}/comments{page}", deadline,
    )
    review_comments = requests.submit(read_pages, api, repo, f"{pull}/comments{page}", deadline)

    data = details.result()
    state, draft, merged, head = data["state"], data["draft"], data["merged"], data["head"]["sha"]
    if state not in ("open", "closed") or not isinstance(draft, bool) or not isinstance(merged, bool):
        raise RuntimeError(f"{pull}: invalid PR state, draft or merged field")
    if not isinstance(head, str) or not head:
        raise RuntimeError(f"{pull}: missing head SHA")
    commit = f"repos/{repo}/commits/{head}"
    runs = requests.submit(read_pages, api, repo, f"{commit}/check-runs{page}", deadline, "check_runs")
    statuses = requests.submit(read_pages, api, repo, f"{commit}/status", deadline, "statuses")
    checks, failing = summarize_checks(runs.result() + statuses.result())
    reviews, comments = reviews.result(), issue_comments.result() + review_comments.result()
    return key(pr), {
        "state": state,
        "draft": draft,
        "merged": merged,
        "head": head,
        "review": review_decision(reviews, head),
        "checks": checks,
        "failing": failing,
        "reviews": len(reviews),
        "comments": len(comments),
        "activity": latest_activity(reviews + comments),
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


def fetch_all(reg, api):
    deadline = time.monotonic() + FETCH_TIMEOUT
    with ThreadPoolExecutor(max_workers=24) as requests, ThreadPoolExecutor(max_workers=10) as prs:
        return dict(prs.map(lambda pr: fetch(pr, api, requests, deadline), reg))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=["check", "snapshot"])
    p.add_argument("registry")
    p.add_argument("snapshot")
    p.add_argument("--only", default="")
    p.add_argument("--api", default=DEFAULT_API, help="read-only JSON API command template (default: %(default)s)")
    a = p.parse_args()
    try:
        api = shlex.split(a.api)
        if not any("{endpoint}" in arg for arg in api):
            raise RuntimeError("--api must contain {endpoint}")
        reg = load_registry(a.registry)
        live = fetch_all(reg, api)
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
