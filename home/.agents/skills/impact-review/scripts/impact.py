#!/usr/bin/env python3
"""impact-review helper: normalize evidence, shard it for the classifier, aggregate results.

Item schema (one JSON object per line):
  id, source, url, date (YYYY-MM-DD), title, workstream, text, firsthand (bool, peer mode)

Subcommands:
  resolve      Merge references/engine.json with the org rubric into <run>/questions.json
  gh-reviews   Collect the subject's PR reviews (review bodies + inline comments) via gh
  gh-prs       Collect PRs authored by the subject, optionally only those another user engaged on
  slack-plan   List the Slack threads still to fetch for a set of subjects (used by slack_collect.js)
  slack-build  Build per-subject Slack items from the shared per-cycle Slack cache (used by slack_collect.js)
  shard        Dedupe, cap text, and split items into classifier shards
  aggregate    Join items + classifier results into evidence.md and summary.json

Org-specific collectors live in private/adapters/ and write the item schema above.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
import time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.join(HERE, "..", "references", "engine.json")
RUBRIC = os.path.join(HERE, "..", "private", "rubric.json")  # gitignored org pack
RUBRIC_KEYS = ("org", "verified", "model", "cycle", "dimensions", "extra_questions", "sources", "github")


def load_rubric(path):
    """The org pack (gitignored). No fallback: a missing or incomplete pack is a setup error."""
    if not os.path.exists(path):
        raise SystemExit(f"org rubric not found: {path}\n"
                         "Copy references/rubric.example.json to private/rubric.json and fill it in for your org.")
    with open(path) as f:
        r = json.load(f)
    missing = [k for k in RUBRIC_KEYS if k not in r] + ([] if "label" in r.get("cycle", {}) else ["cycle.label"])
    if missing:
        raise SystemExit(f"org rubric {path} is missing: {', '.join(missing)} (see references/rubric.example.json)")
    return r


def load_config(path):
    """Merge the generic engine questions with the org rubric into the classifier question set.
    Order: gate, rubric dimensions, the other engine questions, concern, then the rubric's extra questions."""
    with open(ENGINE) as f:
        e = json.load(f)
    r = load_rubric(path)
    dims = r["dimensions"]
    qs = {e["gate"]: e["questions"][e["gate"]]}
    qs.update({d: {"type": "bool", "instructions": v["question"], "criteria": "@strength"} for d, v in dims.items()})
    qs.update({k: v for k, v in e["questions"].items() if k != e["gate"]})
    qs["concern"] = {"type": "choice", "instructions": e["concern"]["instructions"],
                     "criteria": {"none": e["concern"]["none"], **{d: v["shortfall"] for d, v in dims.items()}}}
    qs.update(r["extra_questions"])
    return {"version": r["cycle"]["label"], "verified": r["verified"], "model": r["model"],
            "context": e["context"].replace("{ORG}", r["org"]), "gate": e["gate"], "dimensions": list(dims),
            "statements": {d: {"self": v["self"], "peer": v["peer"]} for d, v in dims.items()},
            "strength": e["strength"], "questions": qs, "sources": {**e["sources"], **r["sources"]}}


def cmd_resolve(a):
    cfg = load_config(a.rubric)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"wrote {a.out}: {len(cfg['questions'])} questions, {len(cfg['dimensions'])} dimensions, "
          f"{len(cfg['sources'])} sources", file=sys.stderr)


def write_jsonl(path, rows):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"wrote {len(rows)} rows -> {path}", file=sys.stderr)


def read_jsonl(paths):
    rows = []
    for p in paths:
        with open(p) as f:
            rows.extend(json.loads(l) for l in f if l.strip())
    return rows


def expand(paths):
    out = []
    for p in paths:
        out.extend(sorted(glob.glob(os.path.join(p, "*.jsonl"))) if os.path.isdir(p) else [p])
    return out


# ---------------------------------------------------------------- gh helpers

def gh(args, sleep):
    for attempt in range(6):
        p = subprocess.run(["gh"] + args, capture_output=True, text=True)
        if p.returncode == 0:
            time.sleep(sleep)
            return json.loads(p.stdout) if p.stdout.strip() else None
        err = p.stderr.lower()
        if "rate limit" in err or "403" in err or "429" in err:
            wait = 60 * (attempt + 1)
            print(f"gh rate limited ({' '.join(p.stderr.split())[:160]}), sleeping {wait}s", file=sys.stderr)
            time.sleep(wait)
            continue
        print(f"gh failed: {' '.join(args)}\n{p.stderr}", file=sys.stderr)
        return None
    raise SystemExit("gh: giving up after repeated rate limits")


def owner_repo_num(url):
    m = re.search(r"github\.com/([^/]+)/([^/]+)/pull/(\d+)", url)
    return m.groups() if m else None


def load_done(path):
    return {r["id"] for r in read_jsonl([path])} if os.path.exists(path) else set()


def append(path, row):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "a") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def search_prs(flags, a):
    q = ["search", "prs", *flags, f"--created={a.start}..{a.end}", "--limit", str(a.max),
         "--json", "title,url,repository,author,createdAt"]
    owner = load_rubric(a.rubric)["github"]["owner"] if a.owner is None else a.owner
    if owner:
        q += ["--owner", owner]
    return gh(q, a.sleep) or []


# ---------------------------------------------------------------- gh-reviews

def cmd_gh_reviews(a):
    """Subject = reviewer. Items show the subject's review bodies and inline comments on others' PRs."""
    done = load_done(a.out)
    # Filter by author in the search itself: searching everything a prolific reviewer touched (1,000 results, 10 pages)
    # and filtering locally tripped GitHub's secondary rate limit for two peers.
    flags = [f"--reviewed-by={a.user}"] + ([f"--author={a.author}"] if a.author else [])
    prs = [p for p in search_prs(flags, a) if p["author"]["login"] != a.user]
    if a.author:
        prs = [p for p in prs if p["author"]["login"] == a.author]
    print(f"{len(prs)} PRs reviewed by {a.user} ({len(done)} already collected)", file=sys.stderr)
    for p in prs:
        if p["url"] in done:
            continue
        orn = owner_repo_num(p["url"])
        if not orn:
            continue
        o, r, n = orn
        reviews = gh(["api", f"repos/{o}/{r}/pulls/{n}/reviews", "--paginate"], a.sleep) or []
        comments = gh(["api", f"repos/{o}/{r}/pulls/{n}/comments", "--paginate"], a.sleep) or []
        mine = []
        for rv in reviews:
            if rv.get("user", {}).get("login") != a.user:
                continue
            body = (rv.get("body") or "").strip()
            if body:
                mine.append(f"{a.label} ({rv['state'].lower()} review): {body}")
            elif rv["state"] in ("APPROVED", "CHANGES_REQUESTED"):
                mine.append(f"{a.label}: {rv['state'].lower()}")
        mine += [f"{a.label} (inline on {c.get('path')}): {c['body'].strip()}" for c in comments
                 if c.get("user", {}).get("login") == a.user]
        others = [f"{c['user']['login']} (inline reply): {c['body'].strip()[:300]}" for c in comments
                  if c.get("user", {}).get("login") not in (a.user,) and c.get("in_reply_to_id")]
        text = f"{a.label}: reviewed PR '{p['title']}' by {p['author']['login']} in {p['repository']['nameWithOwner']}.\n" + \
               "\n".join(x for x in mine if x) + ("\n" + "\n".join(others[:10]) if others else "")
        # date = when the subject's review landed (latest review or inline comment), for the cycle buffer rule
        stamps = [rv.get("submitted_at") for rv in reviews if rv.get("user", {}).get("login") == a.user]
        stamps += [c.get("created_at") for c in comments if c.get("user", {}).get("login") == a.user]
        date = max([s for s in stamps if s] or [p["createdAt"]])[:10]
        append(a.out, {"id": p["url"], "source": "github-review", "url": p["url"], "date": date,
                       "title": f"Review: {p['title']}", "workstream": p["repository"]["nameWithOwner"],
                       "text": text, "firsthand": bool(a.author)})


# ---------------------------------------------------------------- gh-prs

def cmd_gh_prs(a):
    """Subject = author. With --involves, keep only PRs that user reviewed or commented on (firsthand)."""
    done = load_done(a.out)
    flags = [f"--author={a.user}"] + ([f"--involves={a.involves}"] if a.involves else [])
    prs = search_prs(flags, a)
    print(f"{len(prs)} PRs by {a.user} ({len(done)} already collected)", file=sys.stderr)
    for p in prs:
        if p["url"] in done:
            continue
        orn = owner_repo_num(p["url"])
        if not orn:
            continue
        o, r, n = orn
        pr = gh(["api", f"repos/{o}/{r}/pulls/{n}"], a.sleep) or {}
        reviews = gh(["api", f"repos/{o}/{r}/pulls/{n}/reviews", "--paginate"], a.sleep) or []
        issue_comments = gh(["api", f"repos/{o}/{r}/issues/{n}/comments", "--paginate"], a.sleep) or []
        def who(u):
            return a.label if u == a.user else (f"{a.reviewer_label}" if a.involves and u == a.involves else u)
        convo = [f"{who(rv['user']['login'])} ({rv['state'].lower()} review): {rv['body'].strip()[:600]}"
                 for rv in reviews if (rv.get("body") or "").strip()]
        # `--involves` also matches bare mentions (475 PRs for one peer, 21 with real engagement), so firsthand means the
        # reviewer actually reviewed (including body-less approvals) or commented. Record body-less reviews too.
        engaged = bool(a.involves) and (any(rv["user"]["login"] == a.involves for rv in reviews)
                                        or any(c["user"]["login"] == a.involves for c in issue_comments))
        convo += [f"{who(rv['user']['login'])} ({rv['state'].lower()} review, no comment)"
                  for rv in reviews if not (rv.get("body") or "").strip() and rv["user"]["login"] == a.involves]
        convo += [f"{who(c['user']['login'])}: {c['body'].strip()[:600]}" for c in issue_comments
                  if not c["user"]["login"].endswith("[bot]")]
        state = "merged" if pr.get("merged_at") else pr.get("state", "?")
        text = f"{a.label}: authored PR '{p['title']}' ({state}) in {p['repository']['nameWithOwner']}.\n" + \
               (pr.get("body") or "")[:4000] + "\n" + "\n".join(convo[:20])
        # date = merge date when merged (when the work landed), else creation, for the cycle buffer rule
        date = (pr.get("merged_at") or p["createdAt"])[:10]
        append(a.out, {"id": p["url"], "source": "github-pr", "url": p["url"], "date": date,
                       "title": p["title"], "workstream": p["repository"]["nameWithOwner"], "text": text,
                       "firsthand": bool(engaged)})


# ---------------------------------------------------------------- slack cache (plan + build)
#
# slack_collect.js pages channel history and fetches threads into a per-cycle cache shared by every run in the
# cycle (self and all peers), so each thread is fetched at most once. Cache layout (sensitive: raw text + user ids):
#   <cache>/<cid>.parents.json        {"oldest", "latest", "parents": [slim top-level messages, unfiltered]}
#   <cache>/<cid>.threads.NNN.jsonl   {"ts": <parent ts>, "messages": [slim thread messages]}
# Planning and building live here because the bash tool truncates large outputs; JS only sees small JSON lines.


def _slack_parents(cache, cid):
    p = os.path.join(cache, f"{cid}.parents.json")
    if not os.path.exists(p):
        return None
    with open(p) as f:
        return json.load(f)


def _slack_threads(cache, cid):
    out = {}
    for p in sorted(glob.glob(os.path.join(cache, f"{cid}.threads.*.jsonl"))):
        for r in read_jsonl([p]):
            out[r["ts"]] = r["messages"]
    return out


def _slack_human(m):
    return not m.get("bot_id") and (m.get("subtype") or "") in ("", "thread_broadcast", "file_share")


def _slack_clean(text, label):
    t = re.sub(r"<@([UW][A-Z0-9]+)>", lambda m: "@" + label(m.group(1)), text or "")
    t = re.sub(r"<(https?:[^|>]+)\|([^>]+)>", r"\2 (\1)", t)
    t = re.sub(r"<(https?:[^>]+)>", r"\1", t)
    t = t.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    return re.sub(r"\s+", " ", t).strip()[:700]


def _slack_dm_sessions(parents, threads, gap_hours):
    """Group a DM's top-level messages into conversations (new one after a gap), with cached thread replies inline.
    One DM message per item loses the other side of the conversation and floods the classifier with one-liners."""
    out, cur, last = [], None, None
    for m in sorted((p for p in parents if _slack_human(p)), key=lambda p: float(p["ts"])):
        t = float(m["ts"])
        if cur is None or t - last > gap_hours * 3600:
            cur = {**m, "_msgs": []}
            out.append(cur)
        cur["_msgs"].append(m)
        for r in (threads.get(m["ts"]) or [])[1:]:
            cur["_msgs"].append(r)
        last = t
    for s in out:
        s["text"] = s["_msgs"][0].get("text")
        s["_msgs"] = s["_msgs"][:60]
    return out


def cmd_slack_plan(a):
    """Print one JSON line: parent ts values whose threads matter for these subjects and are not cached yet."""
    meta = _slack_parents(a.cache, a.cid)
    if meta is None or meta.get("oldest") != a.oldest or meta.get("latest") != a.latest:
        print(json.dumps({"parents": None}))
        return
    subjects = set(filter(None, a.subjects.split(",")))
    have = _slack_threads(a.cache, a.cid)
    dm = a.cid.startswith("D")
    need, relevant, trunc = [], 0, 0
    for m in meta["parents"]:
        if not _slack_human(m) or not m.get("reply_count"):
            continue
        listed = m.get("reply_users") or []
        users = set([m.get("user")] + listed)
        # reply_users listed every participant (up to 9) in 367 probed threads; if Slack ever truncates it, read the
        # thread rather than guess who took part.
        truncated = (m.get("reply_users_count") or 0) > len(listed)
        trunc += truncated
        if not (truncated or users & subjects):
            continue
        if a.firsthand_only and not dm and not truncated and a.reviewer not in users:
            continue
        relevant += 1
        if m["ts"] not in have:
            need.append(m["ts"])
    print(json.dumps({"parents": len(meta["parents"]), "relevant": relevant, "cached": relevant - len(need),
                      "truncated": trunc, "need": need[: a.max]}))


def cmd_slack_build(a):
    """Write <subject dir>/<cid>.jsonl for every subject from the cache. Idempotent: rebuilds the files each run."""
    with open(a.channels) as f:
        channels = json.load(f)
    with open(a.subjects) as f:
        subjects = json.load(f)
    counts = defaultdict(Counter)
    for ch in channels:
        cid, cname = ch["id"], ch.get("name") or ch["id"]
        meta = _slack_parents(a.cache, cid)
        if meta is None:
            continue
        threads = _slack_threads(a.cache, cid)
        dm = cid.startswith("D")
        rows = defaultdict(list)
        for m in (_slack_dm_sessions(meta["parents"], threads, a.dm_gap_hours) if dm else meta["parents"]):
            if not _slack_human(m):
                continue
            msgs = m["_msgs"] if "_msgs" in m else threads.get(m["ts"]) if m.get("reply_count") else [m]
            if msgs is None:  # thread not fetched: irrelevant to the planned subjects, or still pending
                continue
            msgs = [x for x in msgs if _slack_human(x)] or [m]
            users = {x.get("user") for x in msgs}
            firsthand = bool(a.reviewer) and (dm or a.reviewer in users)
            for s in subjects:
                if s["uid"] not in users or (a.firsthand_only and not firsthand):
                    continue
                names = {}

                def label(u, s=s, names=names):
                    if u == s["uid"]:
                        return s["s"]
                    if a.reviewer and u == a.reviewer:
                        return a.reviewer_label
                    return names.setdefault(u, f"colleague-{len(names) + 1}")

                # date = the subject's latest message in the thread (when their contribution landed)
                landed = max(float(x["ts"]) for x in msgs if x.get("user") == s["uid"])
                rows[s["dir"]].append({
                    "id": f"slack:{cid}:{m['ts']}",
                    "source": "slack-dm" if "_msgs" in m else "slack-thread" if m.get("reply_count") else "slack-message",
                    "url": f"https://{a.workspace}.slack.com/archives/{cid}/p{m['ts'].replace('.', '')}",
                    "date": time.strftime("%Y-%m-%d", time.gmtime(landed)),
                    "title": _slack_clean(m.get("text"), label)[:90] or "(no text)",
                    "workstream": cname,
                    "text": "\n".join(f"{label(x.get('user'))}: {_slack_clean(x.get('text'), label)}" for x in msgs),
                    "firsthand": firsthand,
                })
        for s in subjects:
            path = os.path.join(s["dir"], f"{cid}.jsonl")
            rs = rows.get(s["dir"], [])
            if rs:
                os.makedirs(s["dir"], exist_ok=True)
                with open(path, "w") as f:
                    f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rs)
                counts[s["s"]][cname] = len(rs)
            elif os.path.exists(path):
                os.remove(path)
    print(json.dumps({k: {"total": sum(v.values()), **dict(v)} for k, v in counts.items()}))


# ---------------------------------------------------------------- shard

def cmd_shard(a):
    items = read_jsonl(expand(a.inputs))
    seen, keep = set(), []
    for it in items:
        if it["id"] in seen or len(it.get("text", "")) < a.min_chars:
            continue
        seen.add(it["id"])
        it["text"] = it["text"][: a.max_chars]
        keep.append(it)
    os.makedirs(a.out, exist_ok=True)
    for old in glob.glob(os.path.join(a.out, "*.jsonl")):
        os.remove(old)
    for i in range(0, len(keep), a.size):
        write_jsonl(os.path.join(a.out, f"{i // a.size:04d}.jsonl"), keep[i : i + a.size])
    print(json.dumps({"items": len(keep), "dropped": len(items) - len(keep), "shards": (len(keep) + a.size - 1) // a.size,
                      "by_source": Counter(i["source"] for i in keep)}))


# ---------------------------------------------------------------- aggregate

REACH_W = {"self": 1.0, "team": 1.5, "cross_team": 2.0, "company": 3.0}
# Routine PRs (releases, version bumps) pass the substantive gate but make poor highlights; rank them lower.
ROUTINE_RE = re.compile(r"^(chore|bump|release|revert)\b|\brelease\b.*\d+\.\d+|\bupdate \S+ to v?\d+\.\d+|\bbump\b", re.I)
SKIP_LINE = ("#", "for:", "|", "```", "<!--", "- [", "closes", "fixes", "resolves", "part of", "---")


def routine_w(it):
    return 0.4 if it["source"] == "github-pr" and ROUTINE_RE.search(it["title"]) else 1.0


def excerpt(text, label):
    """Most informative line: first real body line for PRs/reviews, else the subject's longest line."""
    lines = [l.strip() for l in text.split("\n")]
    if lines and re.match(rf"^{re.escape(label)}: (authored|reviewed) PR", lines[0]):
        for l in lines[1:]:
            body = re.sub(r"^\S+ \((approved|commented|changes_requested) review\): ", "", l)
            if len(body) >= 40 and not body.lower().startswith(SKIP_LINE):
                return re.sub(r"\s+", " ", body.replace("**", ""))[:220]
    mine = [l for l in lines if l.startswith(label + ":")]
    if mine:
        return re.sub(r"\s+", " ", max(mine, key=len))[:220]
    return re.sub(r"\s+", " ", text)[:220]


def pace_stats(subs):
    """Velocity is a cross-item property the per-item classifier cannot see; compute it from dates."""
    import datetime as dt
    weeks = Counter()
    days = set()
    for it, _ in subs:
        d = dt.date.fromisoformat(it["date"])
        weeks[d - dt.timedelta(days=d.weekday())] += 1
        days.add(d)
    if not weeks:
        return None
    counts = sorted(weeks.values())
    return {"active_weeks": len(weeks), "active_days": len(days), "median_per_active_week": counts[len(counts) // 2],
            "busiest_weeks": [(str(w), n) for w, n in weeks.most_common(3)]}


def pi_session_stats(root, start, end):
    """Count local pi sessions created in the window (AI-usage evidence for self mode)."""
    import datetime as dt
    root = os.path.expanduser(root)
    per_day, per_proj, delegated = Counter(), Counter(), 0
    for f in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
        rel = os.path.relpath(f, root).split(os.sep)
        if "var-folders" in rel[0]:  # test fixtures under /var/folders
            continue
        st = os.stat(f)
        d = dt.date.fromtimestamp(getattr(st, "st_birthtime", st.st_mtime)).isoformat()
        if not start <= d <= end:
            continue
        if len(rel) > 2:  # nested: minion / sub-agent sessions
            delegated += 1
            continue
        per_day[d] += 1
        per_proj[rel[0].strip("-").split("-")[-1] or "home"] += 1
    if not per_day:
        return None
    return {"sessions": sum(per_day.values()), "delegated": delegated, "active_days": len(per_day),
            "max_day": per_day.most_common(1)[0], "top_projects": per_proj.most_common(6)}


def signal(hits, ws, beyond):
    if hits == 0:
        return "none", "no evidence collected; do not guess (check coverage)"
    if hits <= 2 or ws <= 1:
        return "thin", "3 (or lower if you know of counter-evidence)"
    if hits >= 8 and ws >= 3 and beyond >= 0.25:
        return "strong", "5 if the top evidence is exceptional, else 4"
    return "good", "4"


def cmd_aggregate(a):
    q = load_config(a.rubric)
    dims = q["dimensions"]
    statements = q["statements"]
    # First copy wins, matching `shard` (so the item text is the one the classifier saw), and firsthand from any copy:
    # a peer's PR appears in both gh-prs (firsthand) and an org collector (not), and last-wins silently dropped the flag.
    items = {}
    for i in read_jsonl(expand(a.items)):
        prev = items.setdefault(i["id"], i)
        if prev is not i and i.get("firsthand"):
            prev["firsthand"] = True
    results = {r["id"]: r for r in read_jsonl(expand(a.results))}
    label, thr, peer = a.label, a.threshold, a.mode == "peer"

    # Cycle buffer: collectors start 30 days before the window. Only in-window items count; buffer items are
    # context (they belong to the previous cycle) and post-window items belong to the next one.
    joined, buffer, missing = [], [], 0
    after = 0
    for iid, it in items.items():
        r = results.get(iid)
        if not r:
            missing += 1
            continue
        if it["date"] < a.start:
            buffer.append((it, r))
        elif it["date"] > a.end:
            after += 1
        else:
            joined.append((it, r))
    subs = [(it, r) for it, r in joined if r["p"].get("substantive", 0) >= 0.5]

    def score(it, r, d):
        w = REACH_W.get(r.get("reach"), 1.0) * (1 + 0.5 * r["p"].get("outcome", 0)) * routine_w(it)
        return r["p"].get(d, 0) * w * (1.5 if peer and it.get("firsthand") else 1.0)

    def top(rows, key, n):
        rows = sorted(rows, key=key, reverse=True)
        picked, used = [], set()
        for it, r in rows:  # one per workstream first, for breadth
            if it["workstream"] not in used:
                picked.append((it, r)); used.add(it["workstream"])
            if len(picked) == n:
                return picked
        for row in rows:
            if row not in picked:
                picked.append(row)
            if len(picked) == n:
                break
        return picked

    def line(it, r, extra=""):
        url = f"[{it['title'][:90]}]({it['url']})" if it.get("url") else it["title"][:90]
        fh = " firsthand" if it.get("firsthand") else ""
        return f"- {it['date']} {url} | {it['workstream']} | reach={r.get('reach')}{fh}{extra}\n  > {excerpt(it['text'], label)}"

    summary = {"mode": a.mode, "subject": label, "window": f"{a.start}..{a.end}", "threshold": thr, "items": len(items),
               "in_window": len(joined), "buffer": len(buffer), "after_window": after, "unclassified": missing,
               "substantive": len(subs), "dimensions": {}}
    out = [f"# Evidence: {label} ({a.mode} review, window {a.start}..{a.end})", "",
           "Generated by impact-review. Classifier scores are recall aids, not ratings. Read the evidence before rating.", "",
           "## Coverage", "", "| Source | In window | Substantive | Buffer (context only) |", "|---|---:|---:|---:|"]
    by_src, by_src_sub = Counter(it["source"] for it, _ in joined), Counter(it["source"] for it, _ in subs)
    by_src_buf = Counter(it["source"] for it, _ in buffer)
    for s_ in sorted(set(by_src) | set(by_src_buf), key=lambda x: -by_src[x]):
        out.append(f"| {s_} | {by_src[s_]} | {by_src_sub[s_]} | {by_src_buf[s_]} |")
    if after:
        out.append(f"\n{after} items are dated after {a.end} and were dropped (next cycle).")
    if missing:
        out.append(f"\nWARNING: {missing} items have no classifier result. Re-run classify before trusting counts.")

    out += ["", "## Statement signals", "",
            "| Key | Statement | Hits | Share | Rank | Workstreams | Months | Beyond team | With outcome | Signal | Suggested |",
            "|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|"]
    detail = []
    share = {d: sum(1 for _, r in subs if r["p"].get(d, 0) >= thr) / max(len(subs), 1) for d in dims}
    rank = {d: (i + 1 if share[d] else "-") for i, d in enumerate(sorted(dims, key=lambda x: -share[x]))}
    for d in dims:
        hits = [(it, r) for it, r in subs if r["p"].get(d, 0) >= thr]
        ws = len({it["workstream"] for it, _ in hits})
        months = len({it["date"][:7] for it, _ in hits})
        beyond = sum(1 for _, r in hits if r.get("reach") in ("cross_team", "company")) / len(hits) if hits else 0
        outc = sum(1 for _, r in hits if r["p"].get("outcome", 0) >= 0.5) / len(hits) if hits else 0
        fh = sum(1 for it, _ in hits if it.get("firsthand"))
        sig, sugg = signal(len(hits), ws, beyond)
        stmt = statements[d]["peer" if peer else "self"]
        summary["dimensions"][d] = {"hits": len(hits), "share": round(share[d], 3), "rank": rank[d], "workstreams": ws,
                                    "months": months, "beyond_team": round(beyond, 2), "with_outcome": round(outc, 2),
                                    "firsthand": fh, "signal": sig}
        out.append(f"| `{d}` | {stmt} | {len(hits)}{f' ({fh} firsthand)' if peer else ''} | {share[d]:.0%} | {rank[d]} | {ws} | {months} | {beyond:.0%} | {outc:.0%} | {sig} | {sugg} |")
        detail += ["", f"### `{d}`: {stmt}", ""]
        detail += [line(it, r, f" | p={r['p'][d]:.2f}") for it, r in top(hits, lambda x: score(*x, d), a.top)] or ["- none"]

    out += ["", "Share = hits / substantive items. Use Rank and the quality of the top evidence to differentiate ratings."]
    ps = pace_stats(subs)
    summary["pace_stats"] = ps
    if ps:
        out += ["", "## Pace (cross-item, computed from dates)", "",
                "The per-item classifier rarely sees velocity, so `pace` hits undercount. Use these numbers instead.", "",
                f"- Active weeks: {ps['active_weeks']}, active days: {ps['active_days']}, median substantive items per active week: {ps['median_per_active_week']}",
                "- Busiest weeks (week of): " + ", ".join(f"{w} ({n})" for w, n in ps["busiest_weeks"])]

    ws_score = defaultdict(float)
    ws_items = defaultdict(list)
    for it, r in subs:
        best = max(r["p"].get(d, 0) for d in dims)
        ws_score[it["workstream"]] += best * REACH_W.get(r.get("reach"), 1.0) * (1 + r["p"].get("outcome", 0)) * routine_w(it)
        ws_items[it["workstream"]].append((it, r))
    out += ["", "## Highlight candidates (workstreams by weighted evidence)", ""]
    for ws, sc in sorted(ws_score.items(), key=lambda x: -x[1])[: a.workstreams]:
        rows = ws_items[ws]
        dim_counts = Counter(d for _, r in rows for d in dims if r["p"].get(d, 0) >= thr)
        reach = Counter(r.get("reach") for _, r in rows).most_common(1)[0][0]
        span = f"{min(it['date'] for it, _ in rows)}..{max(it['date'] for it, _ in rows)}"
        out.append(f"### {ws}\n\nscore={sc:.1f} items={len(rows)} span={span} reach={reach} dims={dict(dim_counts.most_common())}\n")
        out += [line(it, r) for it, r in sorted(rows, key=lambda x: -max(score(*x, d) for d in dims))[:4]]
        out.append("")

    out += ["", "## Evidence per statement"] + detail

    out += ["", "## Possible shortfalls (feeds 'what would unlock')", ""]
    concerns = [(it, r) for it, r in subs if r.get("concern") not in (None, "none") and r.get("concern_p", 0) >= a.concern_threshold]
    summary["concerns"] = dict(Counter(r["concern"] for _, r in concerns))
    for d in dims:
        rows = [(it, r) for it, r in concerns if r["concern"] == d]
        if rows:
            out += [f"### `{d}` ({len(rows)})", ""] + [line(it, r, f" | p={r['concern_p']:.2f}") for it, r in sorted(rows, key=lambda x: -x[1]["concern_p"])[:5]] + [""]
    if not concerns:
        out.append("- none above threshold")

    ai = [(it, r) for it, r in subs if r["p"].get("ai", 0) >= thr]
    summary["ai"] = len(ai)
    out += ["", f"## AI leverage ({len(ai)} items)", ""]
    if a.pi_sessions:
        st = pi_session_stats(a.pi_sessions, a.start, a.end)
        summary["pi_sessions"] = st
        if st:
            out += [f"- pi sessions in window: {st['sessions']} interactive over {st['active_days']} days, plus {st['delegated']} delegated minion sessions; busiest day {st['max_day'][0]} ({st['max_day'][1]})",
                    "- Top session projects: " + ", ".join(f"{p} ({n})" for p, n in st["top_projects"]), ""]
    out += [line(it, r) for it, r in top(ai, lambda x: x[1]["p"]["ai"], a.top)] or ["- no per-item AI signal"]

    for k, v in q["questions"].items():  # the rubric's extra questions that carry a report heading
        if "report" not in v or (v.get("peer_only") and not peer):
            continue
        tr = [(it, r) for it, r in subs if r["p"].get(k, 0) >= thr]
        summary[k] = {"hits": len(tr), "firsthand": sum(1 for it, _ in tr if it.get("firsthand"))}
        out += ["", f"## {v['report']} ({len(tr)} items)", ""] + \
               ([line(it, r) for it, r in top(tr, lambda x, k=k: score(*x, k), a.top)] or ["- none"])

    buf_sub = [(it, r) for it, r in buffer if r["p"].get("substantive", 0) >= 0.5]
    out += ["", f"## Buffer items before {a.start} ({len(buf_sub)} substantive, context only)", "",
            "These landed in the 30-day buffer, so they are the previous cycle's impact. Use them only to explain",
            "in-window follow-through (e.g. the rollout that shipped inside the window). NEVER cite them as this cycle's impact.", ""]
    out += [line(it, r) for it, r in top(buf_sub, lambda x: max(score(*x, d) for d in dims), a.top)] or ["- none"]

    with open(a.out, "w") as f:
        f.write("\n".join(out) + "\n")
    with open(a.json, "w") as f:
        json.dump(summary, f, indent=2)
    print(json.dumps(summary, indent=2))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)

    p = sp.add_parser("resolve"); p.add_argument("--rubric", default=RUBRIC, help="org pack (default private/rubric.json)")
    p.add_argument("--out", required=True, help="resolved question set, e.g. <run>/questions.json")
    p.set_defaults(fn=cmd_resolve)

    for name, fn in (("gh-reviews", cmd_gh_reviews), ("gh-prs", cmd_gh_prs)):
        p = sp.add_parser(name); p.add_argument("--user", required=True, help="subject GitHub login")
        p.add_argument("--label", required=True); p.add_argument("--start", required=True); p.add_argument("--end", required=True)
        p.add_argument("--out", required=True)
        p.add_argument("--owner", default=None, help="GitHub org; default rubric github.owner, '' = all")
        p.add_argument("--rubric", default=RUBRIC)
        # 300 silently truncated a real run (421 reviewed PRs, 250 collected); keep the cap well above a cycle's volume
        p.add_argument("--max", type=int, default=1000); p.add_argument("--sleep", type=float, default=0.5)
        if name == "gh-reviews":
            p.add_argument("--author", help="only PRs authored by this login (firsthand)")
        else:
            p.add_argument("--involves", help="only PRs this login engaged on (firsthand)")
            p.add_argument("--reviewer-label", default="REVIEWER")
        p.set_defaults(fn=fn)

    p = sp.add_parser("slack-plan"); p.add_argument("--cache", required=True); p.add_argument("--cid", required=True)
    p.add_argument("--oldest", required=True); p.add_argument("--latest", required=True)
    p.add_argument("--subjects", required=True, help="comma-separated Slack user ids")
    p.add_argument("--reviewer"); p.add_argument("--firsthand-only", action="store_true")
    p.add_argument("--max", type=int, default=600)
    p.set_defaults(fn=cmd_slack_plan)

    p = sp.add_parser("slack-build"); p.add_argument("--cache", required=True)
    p.add_argument("--channels", required=True, help="JSON file: [{id, name}]")
    p.add_argument("--subjects", required=True, help="JSON file: [{uid, s, dir}]")
    p.add_argument("--reviewer"); p.add_argument("--reviewer-label", default="REVIEWER")
    p.add_argument("--firsthand-only", action="store_true")
    p.add_argument("--dm-gap-hours", type=float, default=3.0, help="new DM conversation item after this much silence")
    p.add_argument("--workspace", required=True, help="Slack workspace subdomain for permalinks (rubric slack.workspace)")
    p.set_defaults(fn=cmd_slack_build)

    p = sp.add_parser("shard"); p.add_argument("inputs", nargs="+"); p.add_argument("--out", required=True)
    p.add_argument("--size", type=int, default=100); p.add_argument("--max-chars", type=int, default=8000)
    p.add_argument("--min-chars", type=int, default=40)
    p.set_defaults(fn=cmd_shard)

    p = sp.add_parser("aggregate"); p.add_argument("--items", nargs="+", required=True)
    p.add_argument("--results", nargs="+", required=True); p.add_argument("--mode", choices=["self", "peer"], required=True)
    p.add_argument("--label", required=True); p.add_argument("--threshold", type=float, default=0.7)
    p.add_argument("--concern-threshold", type=float, default=0.6); p.add_argument("--top", type=int, default=6)
    p.add_argument("--workstreams", type=int, default=6)
    p.add_argument("--pi-sessions", help="pi sessions dir (self mode), e.g. ~/.pi/agent/sessions")
    p.add_argument("--start", required=True, help="official window start (YYYY-MM-DD); earlier items are buffer context")
    p.add_argument("--end", required=True, help="official window end (YYYY-MM-DD); later items are dropped")
    p.add_argument("--out", required=True); p.add_argument("--json", required=True)
    p.add_argument("--rubric", default=RUBRIC)
    p.set_defaults(fn=cmd_aggregate)

    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
