#!/usr/bin/env python3
"""Stage 1 fetch for pr-reviewer, and the cleanup after a Shuttle review is posted.

    python3 prfetch.py fetch   --key github:owner/repo#123 [--head <sha or prefix>] [--out DIR]
    python3 prfetch.py cleanup --key github:owner/repo#123 [--task <cortex id>] [--out DIR]

Every section runs on its own and reports ok, FAILED or skipped with the command to run by hand,
so one failure never hides what the other sections found. Sections that need an earlier result
(the diff needs the pinned head) say which one they waited for. Output files go to --out, by
default $BB_THREAD_STORAGE/pr<number>. Exit status: 0 when every section is ok, 3 when any
failed or was skipped, 2 for bad arguments.

GitHub works out of the box. Other forges with a gh-compatible CLI, and a host bridge for running
cortex from a sandbox, come from the optional, gitignored private/forges.json next to this script:

    {"forges": {"<server>": {"cli": "<cli>", "identity_cmd": ["<cli>", "auth", "status"],
                             "identity_regex": "Signed in as (\\S+)", "stderr_noise": "<regex>"}},
     "host_bridge": "<command that runs a host command>"}
"""

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def load_private():
    path = os.path.join(HERE, "private", "forges.json")
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


PRIVATE = load_private()
FORGES = PRIVATE.get("forges", {})
_noise = [f["stderr_noise"] for f in FORGES.values() if f.get("stderr_noise")]
CLI_NOISE = re.compile("|".join(f"(?:{n})" for n in _noise)) if _noise else None


def noisy(line):
    return bool(CLI_NOISE and CLI_NOISE.match(line))
INLINE_DIFF_LINES = 400
INLINE_BODY_CHARS = 6000
INLINE_AGENTS_CHARS = 40000
COMMENT_CHARS = 240


class Skip(Exception):
    """The section could not run; its fallback is needed."""


class NotApplicable(Exception):
    """The section has nothing to do for this PR."""


class Report:
    def __init__(self):
        self.rows = []

    def section(self, name, fn, fallback, needs=()):
        missing = [n for n in needs if n not in self.ok]
        print(f"\n## {name}", flush=True)
        if missing:
            self.rows.append((name, "skipped", f"needs {', '.join(missing)}", fallback))
            print(f"[skipped] needs {', '.join(missing)}. By hand: {fallback}")
            return None
        started = time.time()
        try:
            out = fn()
        except NotApplicable as why:
            self.rows.append((name, "n/a", str(why), ""))
            print(f"[n/a] {why}")
            return None
        except Skip as why:
            self.rows.append((name, "skipped", str(why), fallback))
            print(f"[skipped] {why}. By hand: {fallback}")
            return None
        except Exception as error:  # each section fails on its own
            self.rows.append((name, "FAILED", str(error)[-600:], fallback))
            print(f"[FAILED] {str(error)[-600:]}\nBy hand: {fallback}")
            return None
        self.rows.append((name, "ok", f"{time.time() - started:.1f}s", ""))
        return out if out is not None else True

    @property
    def ok(self):
        return {name for name, state, _, _ in self.rows if state in ("ok", "n/a")}

    def summary(self):
        print("\n## Status")
        for name, state, note, fallback in self.rows:
            line = f"- {name}: {state}"
            if state not in ("ok", "n/a"):
                line += f" ({note}); by hand: {fallback}"
            print(line)
        bad = [r for r in self.rows if r[1] not in ("ok", "n/a")]
        print(f"{len(self.rows) - len(bad)} ok, {len(bad)} not ok")
        return 3 if bad else 0


def run(cmd, timeout=120, stdin=None, check=True, cwd=None):
    proc = subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=timeout, cwd=cwd)
    err = "\n".join(l for l in proc.stderr.splitlines() if not noisy(l)).strip()
    if check and proc.returncode != 0:
        raise RuntimeError(f"`{shlex.join(cmd)}` exited {proc.returncode}: {err[-500:] or proc.stdout[-500:]}")
    return proc.stdout


def parse_key(key):
    m = re.fullmatch(r"(?P<server>[\w.-]+):(?P<repo>[^#!\s]+/[^#!\s]+)[#!](?P<number>\d+)", key.strip())
    if not m:
        raise SystemExit(f"--key must look like github:owner/repo#123, got {key!r}")
    return m.group("server"), m.group("repo"), int(m.group("number"))


class Server:
    def __init__(self, server, repo, number):
        self.server, self.repo, self.number = server, repo, number
        self.forge = FORGES.get(server, {})
        if server == "github" or server.startswith("github"):
            self.cli = "gh"
        elif self.forge.get("cli") and shutil.which(self.forge["cli"]):
            self.cli = self.forge["cli"]
        else:
            self.cli = None

    def need(self):
        if not self.cli or not shutil.which(self.cli):
            raise Skip(f"no API CLI for server {self.server!r}; read the PR with the request's view command")

    def api(self, path, timeout=60):
        self.need()
        return json.loads(run([self.cli, "api", "-X", "GET", path], timeout=timeout) or "null")

    def api_list(self, path, pages=10):
        items = []
        for page in range(1, pages + 1):
            sep = "&" if "?" in path else "?"
            batch = self.api(f"{path}{sep}per_page=100&page={page}")
            if not isinstance(batch, list):
                raise RuntimeError(f"{path} did not return a list")
            items += batch
            if len(batch) < 100:
                break
        return items

    def identity(self):
        self.need()
        if self.cli == "gh":
            return run(["gh", "api", "user", "--jq", ".login"], timeout=30).strip()
        cmd = self.forge.get("identity_cmd")
        if not cmd or not self.forge.get("identity_regex"):
            raise Skip(f"no identity_cmd and identity_regex for server {self.server!r} in private/forges.json")
        out = run(cmd, timeout=30)
        m = re.search(self.forge["identity_regex"], out)
        if not m:
            raise RuntimeError(f"`{shlex.join(cmd)}` did not say who is signed in")
        return m.group(1)

    def identity_hint(self):
        if self.cli == "gh" or not self.forge.get("identity_cmd"):
            return "gh api user --jq .login"
        return shlex.join(self.forge["identity_cmd"])

    def view_hint(self):
        return f"{self.cli or 'gh'} pr view {self.number} -R {self.repo} --comments"


def git(*args, timeout=120, check=True, stdin=None):
    return run(["git", *args], timeout=timeout, check=check, stdin=stdin)


def tree_mode(ref, path):
    """The path's mode at ref, or None when it is not there; a git without ls-tree falls back to cat-file."""
    try:
        entry = git("ls-tree", ref, "--", path, timeout=30).split()
        return entry[0] if len(entry) >= 3 else None
    except RuntimeError:
        found = subprocess.run(["git", "cat-file", "-e", f"{ref}:{path}"], capture_output=True, timeout=30).returncode == 0
        return "100644" if found else None


def remote_for(repo):
    remotes = {}
    for line in git("remote", "-v", timeout=30).splitlines():
        parts = line.split()
        if len(parts) >= 2:
            remotes.setdefault(parts[0], parts[1])
    want = repo.lower().removesuffix(".git")
    matches = [name for name, url in remotes.items() if want in url.lower()]
    if "origin" in matches or (not matches and "origin" in remotes):
        return "origin"
    if matches:
        return matches[0]
    raise RuntimeError(f"no git remote points at {repo}: {remotes}")


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def short(text, n, flat=False):
    text = (text or "").replace("\r", "").strip()
    if flat:
        text = " ".join(text.split())
    return text if len(text) <= n else text[:n] + f"... [{len(text) - n} more chars]"


def login_of(user):
    return ((user or {}).get("login") or (user or {}).get("email") or "").lower()


def cortex_cmd(args):
    if shutil.which("cortex"):
        return ["cortex", *args]
    bridge = PRIVATE.get("host_bridge")
    if bridge and shutil.which(bridge):
        return [bridge, "cortex", *args]
    raise Skip("no cortex CLI here and no host_bridge in private/forges.json")


def lane():
    top = git("rev-parse", "--show-toplevel", timeout=30, check=False).strip()
    return os.path.basename(top or os.getcwd())


def find_review_tasks(number):
    out = run(cortex_cmd(["ls", "--json", "-l", lane(), "-t", "pr-review", "-q", f"@PR Review #{number}:"]), timeout=60)
    tasks = json.loads(out or "[]")
    return [t for t in tasks if str(t.get("title", "")).startswith(f"PR Review #{number}:")]


def fetch(args):
    srv = Server(*parse_key(args.key))
    out = args.out
    os.makedirs(out, exist_ok=True)
    rep = Report()
    facts = {"key": args.key, "repo": srv.repo, "number": srv.number, "out": out, "refs": []}
    print(f"# prfetch {args.key} -> {out}")

    def meta():
        pr = srv.api(f"repos/{srv.repo}/pulls/{srv.number}")
        write(f"{out}/pr.json", json.dumps(pr, indent=1))
        write(f"{out}/body.md", pr.get("body") or "")
        facts.update(
            title=pr.get("title"), author=login_of(pr.get("user")), state=pr.get("state"), draft=pr.get("draft"),
            head=pr["head"]["sha"], head_ref=pr["head"].get("ref"), base=pr["base"]["sha"], base_ref=pr["base"].get("ref"),
            merge_base=pr.get("merge_base_sha"), additions=pr.get("additions"), deletions=pr.get("deletions"),
            changed_files=pr.get("changed_files"), url=(pr.get("html_url") or pr.get("_links", {}).get("html", {}).get("href")),
        )
        if args.head and not facts["head"].startswith(args.head):
            print(f"NOTE: the request names head {args.head}, the server now says {facts['head'][:12]}; this review covers {facts['head'][:12]}.")
        write(f"{out}/meta.txt", f"{facts['title']}\n\n{pr.get('body') or ''}")
        print(f"{facts['title']}\nauthor {facts['author']} | {facts['state']}{' (draft)' if facts['draft'] else ''} | "
              f"{facts['base_ref']} {facts['base'][:12]} <- {facts['head_ref']} {facts['head'][:12]} | "
              f"+{facts['additions']} -{facts['deletions']} in {facts['changed_files']} files | {facts['url']}")
        print(f"\nDescription ({out}/body.md):\n{short(pr.get('body'), INLINE_BODY_CHARS)}")

    rep.section("meta", meta, f"{srv.view_hint()} (or {srv.cli or 'gh'} api repos/{srv.repo}/pulls/{srv.number})")

    def identity():
        facts["identity"] = srv.identity()
        print(f"posting identity: {facts['identity']}")

    rep.section("identity", identity, srv.identity_hint())

    def reviews():
        items = srv.api_list(f"repos/{srv.repo}/pulls/{srv.number}/reviews")
        write(f"{out}/reviews.json", json.dumps(items, indent=1))
        for r in items:
            print(f"- {login_of(r.get('user'))} {r.get('state')} @{(r.get('commit_id') or '')[:12]} {r.get('submitted_at')}")
        me = (facts.get("identity") or "").lower()
        if not me:
            print("GATE: unknown, the identity section failed; check the reviews above by hand.")
            return
        mine = [r for r in items if login_of(r.get("user")) == me and r.get("state") != "COMMENTED"]
        mine.sort(key=lambda r: r.get("submitted_at") or "")
        latest = mine[-1] if mine else None
        facts["my_review"] = latest and {k: latest.get(k) for k in ("state", "commit_id", "submitted_at", "html_url")}
        if not latest or latest.get("state") != "APPROVED":
            print(f"GATE: no standing approval from {me} ({latest.get('state') if latest else 'no approval or change request'}); continue (Stage 1 step 4).")
        elif latest.get("commit_id") == facts.get("head"):
            print(f"GATE: {me} APPROVED the current head ({latest.get('html_url')}); STOP per Stage 1 step 2.")
        else:
            print(f"GATE: {me} APPROVED older commit {latest.get('commit_id', '')[:12]}; compare patch ids per Stage 1 step 3 (patch-id section).")

    rep.section("reviews", reviews, f"{srv.cli or 'gh'} api -X GET repos/{srv.repo}/pulls/{srv.number}/reviews")

    def comments():
        inline = srv.api_list(f"repos/{srv.repo}/pulls/{srv.number}/comments")
        convo = srv.api_list(f"repos/{srv.repo}/issues/{srv.number}/comments")
        write(f"{out}/review_comments.json", json.dumps(inline, indent=1))
        write(f"{out}/issue_comments.json", json.dumps(convo, indent=1))
        print(f"{len(inline)} inline review comments ({out}/review_comments.json), {len(convo)} conversation comments ({out}/issue_comments.json)")
        for c in inline[:80]:
            print(f"- [{c.get('id')}] {login_of(c.get('user'))} {c.get('path')}:{c.get('line') or c.get('original_line')}: {short(c.get('body'), COMMENT_CHARS, flat=True)}")
        for c in convo[:40]:
            print(f"- [{c.get('id')}] {login_of(c.get('user'))} (conversation): {short(c.get('body'), COMMENT_CHARS, flat=True)}")

    rep.section("comments", comments, f"{srv.cli or 'gh'} api -X GET repos/{srv.repo}/pulls/{srv.number}/comments and .../issues/{srv.number}/comments")

    def issues():
        if srv.cli != "gh":
            raise NotApplicable("linked issues come from GitHub only; read issue links in the description")
        refs = json.loads(run(["gh", "pr", "view", str(srv.number), "-R", srv.repo, "--json", "closingIssuesReferences"], timeout=60))
        found = refs.get("closingIssuesReferences") or []
        for i in found:
            repo = (i.get("repository") or {}).get("nameWithOwner", srv.repo)
            print(f"- closes {repo}#{i.get('number')}: {i.get('title') or ''} {i.get('url') or ''}")
        if not found:
            print("closes no issue; look for issue links in the description")

    rep.section("issues", issues, f"gh pr view {srv.number} -R {srv.repo} --json closingIssuesReferences")

    def checks():
        srv.need()
        proc = subprocess.run([srv.cli, "pr", "checks", str(srv.number), "-R", srv.repo], capture_output=True, text=True, timeout=60)
        text = "\n".join(l for l in proc.stdout.splitlines() if l.strip() and not noisy(l))
        if not text:
            raise RuntimeError(proc.stderr.strip()[-300:] or f"exit {proc.returncode}")
        print(short(text, 3000))

    rep.section("checks", checks, f"{srv.cli or 'gh'} pr checks {srv.number} -R {srv.repo}")

    def pin():
        head = facts.get("head") or (args.head if args.head and len(args.head) == 40 else None)
        if not head:
            raise Skip("no full head SHA: the meta section failed and --head is not a full SHA")
        remote = remote_for(srv.repo)
        ref = f"refs/pr-review/{srv.number}-{head[:12]}"
        if srv.cli == "gh":
            git("fetch", "--no-tags", remote, f"+refs/pull/{srv.number}/head:{ref}", timeout=300)
        else:
            git("fetch", "--no-tags", remote, head, timeout=300)
            git("update-ref", ref, head, timeout=30)
        got = git("rev-parse", ref, timeout=30).strip()
        facts["refs"].append(ref)
        if got != head:
            facts["ref"] = ref
            raise RuntimeError(f"{ref} is {got[:12]} but the server's head is {head[:12]}: the PR moved; rerun this script")
        for sha in filter(None, {facts.get("base"), facts.get("merge_base")}):
            if subprocess.run(["git", "cat-file", "-e", f"{sha}^{{commit}}"], capture_output=True).returncode != 0:
                git("fetch", "--no-tags", remote, sha, timeout=300)
        mb = facts.get("merge_base")
        if not mb and facts.get("base"):
            mb = git("merge-base", facts["base"], ref, timeout=60, check=False).strip() or facts["base"]
        facts.update(ref=ref, remote=remote, diff_base=mb)
        print(f"pinned {ref} = {got}\ndiff base {mb} (read with: git show {ref}:<path>, git diff {mb[:12]} {ref}, git grep <pattern> {ref} -- <paths>)")

    rep.section("pin", pin, "git fetch the head into refs/pr-review/<n>-<head12> and check git rev-parse (Stage 1)", needs=())

    def diff():
        mb, ref = facts["diff_base"], facts["ref"]
        names = git("diff", "--name-only", mb, ref).split("\n")
        files = [n for n in names if n]
        facts["files"] = files
        write(f"{out}/files.txt", "\n".join(files) + "\n")
        patch = git("diff", mb, ref, timeout=300)
        write(f"{out}/pr.diff", patch)
        print(git("diff", "--stat=160", mb, ref).rstrip())
        commits = git("log", "--format=%h %an: %s%n%b", f"{mb}..{ref}")
        write(f"{out}/commits.txt", commits)
        print(f"\nCommits ({out}/commits.txt):\n{short(commits, 4000)}")
        lines = patch.count("\n")
        if lines <= INLINE_DIFF_LINES:
            print(f"\nDiff ({lines} lines, also {out}/pr.diff):\n{patch}")
        else:
            print(f"\nDiff: {lines} lines in {out}/pr.diff; read the hunks you need.")

    rep.section("diff", diff, "git diff --name-only/--stat <base> <ref>, git diff <base> <ref> > pr.diff", needs=("pin",))

    def patch_id():
        mine = facts.get("my_review") or {}
        if mine.get("state") != "APPROVED" or mine.get("commit_id") == facts.get("head"):
            raise NotApplicable("no approval at an older commit, so nothing to compare")
        approved, remote = mine["commit_id"], facts["remote"]
        if subprocess.run(["git", "cat-file", "-e", f"{approved}^{{commit}}"], capture_output=True).returncode != 0:
            git("fetch", "--no-tags", remote, approved, timeout=300)

        def pid(commit):
            base = git("merge-base", facts["base"], commit, timeout=60).strip()
            return git("patch-id", "--stable", stdin=git("diff", base, commit, timeout=300)).split(" ")[0]

        then, now = pid(approved), pid(facts["ref"])
        same = then == now and then != ""
        print(f"patch-id at approval {then[:12]}, at head {now[:12]}: {'EQUAL, the approval stands (Stage 1 step 3)' if same else 'different, review what changed since the approval'}")

    rep.section("patch-id", patch_id, "git diff <base>...<commit> | git patch-id --stable for the approved commit and the head", needs=("pin", "reviews"))

    def agents():
        ref, files = facts["ref"], facts["files"]
        dirs = {""}
        for f in files:
            parts = f.split("/")[:-1]
            for i in range(1, len(parts) + 1):
                dirs.add("/".join(parts[:i]))
        shown, total, failed = [], 0, []
        for d in sorted(dirs, key=lambda d: (d.count("/"), d)):
            path = f"{d}/AGENTS.md" if d else "AGENTS.md"
            try:
                mode = tree_mode(ref, path)
                if mode is None:
                    continue
                text = git("show", f"{ref}:{path}", timeout=30)
                pointer = mode == "120000" or (len(text) < 200 and "\n" not in text.strip() and text.strip().endswith(".md"))
                if pointer:
                    target = os.path.normpath(os.path.join(d, text.strip()))
                    if tree_mode(ref, target) is None:
                        print(f"\n### {path}: a symlink to {target}, which is not in the repository at this head; nothing to read")
                        continue
                    text = git("show", f"{ref}:{target}", timeout=30)
                    path = f"{path} -> {target}"
            except Exception as error:
                failed.append(f"{path}: {str(error)[-200:]}")
                continue
            saved = f"{out}/agents/{path.split(' ')[0].replace('/', '__')}"
            write(saved, text)
            shown.append((path, saved, text))
        if not shown and not failed:
            print("no AGENTS.md in any changed directory or its parents")
        for path, saved, text in shown:
            if total + len(text) <= INLINE_AGENTS_CHARS:
                total += len(text)
                print(f"\n### {path} ({len(text)} chars, {saved})\n{text.rstrip()}")
            else:
                print(f"\n### {path} ({len(text)} chars): read {saved}")
        if failed:
            raise RuntimeError("could not read " + "; ".join(failed))

    rep.section("agents", agents, "git show <ref>:<dir>/AGENTS.md for each changed directory and its parents", needs=("diff",))

    def specialists():
        files = facts.get("files")
        if not files:
            files = [f["filename"] for f in srv.api_list(f"repos/{srv.repo}/pulls/{srv.number}/files")]
        if not os.path.exists(f"{out}/meta.txt"):
            raise Skip("no PR title and body: the meta section failed")
        cmd = ["ruby", "--disable-gems", f"{HERE}/specialists.rb", "--repo", srv.repo, "--meta", f"{out}/meta.txt"]
        if facts.get("ref"):
            cmd += ["--ref", facts["ref"]]
        text = run(cmd, stdin="\n".join(files) + "\n", timeout=180)
        write(f"{out}/specialists.jsonl", text)
        print(text.rstrip() or "no specialist sources configured")

    rep.section("specialists", specialists, f"git diff --name-only <base> <ref> | ruby --disable-gems {HERE}/specialists.rb --repo {srv.repo} --meta <title and body file> --ref <ref>")

    def cortex():
        tasks = find_review_tasks(srv.number)
        facts["cortex"] = [{k: t.get(k) for k in ("id", "status", "title")} for t in tasks]
        for t in tasks:
            print(f"- task {t.get('id')} {t.get('status')}: {t.get('title')} (re-review fork applies)")
        if not tasks:
            print(f"no `PR Review #{srv.number}:` task in lane {lane()}: first review")

    rep.section("cortex", cortex, f'cortex ls --json -l {lane()} -t pr-review -q "@PR Review #{srv.number}:"')

    write(f"{out}/prfetch.json", json.dumps(facts, indent=1))
    return rep.summary()


def cleanup(args):
    srv = Server(*parse_key(args.key))
    out = args.out
    rep = Report()
    facts = {}
    try:
        with open(f"{out}/prfetch.json", encoding="utf-8") as f:
            facts = json.load(f)
    except (OSError, ValueError):
        pass
    print(f"# prfetch cleanup {args.key}")

    def posted():
        me = srv.identity().lower()
        items = srv.api_list(f"repos/{srv.repo}/pulls/{srv.number}/reviews")
        mine = sorted((r for r in items if login_of(r.get("user")) == me), key=lambda r: r.get("submitted_at") or "")
        if not mine:
            raise RuntimeError(f"no review from {me} on the PR")
        r = mine[-1]
        facts["posted"] = {"state": r.get("state"), "url": r.get("html_url"), "commit": r.get("commit_id")}
        print(f"posted: {r.get('state')} @{(r.get('commit_id') or '')[:12]} {r.get('submitted_at')} {r.get('html_url')}")

    rep.section("posted", posted, f"{srv.cli or 'gh'} api -X GET repos/{srv.repo}/pulls/{srv.number}/reviews")

    def roundlog():
        ids = [args.task] if args.task else [t["id"] for t in find_review_tasks(srv.number) if t.get("status") != "done"]
        if not ids:
            raise NotApplicable(f"no open `PR Review #{srv.number}:` task in lane {lane()}; pass --task if the review's task is elsewhere")
        p = facts["posted"]
        for task in ids:
            body = json.loads(run(cortex_cmd(["show", str(task), "--json"]), timeout=60))["task"].get("body") or ""
            lines = [l for l in body.splitlines() if "handed to Shuttle" in l]
            if not lines:
                print(f"task {task}: no round-log line says 'handed to Shuttle'; left as is")
                continue
            old = lines[-1]
            new = old.replace("handed to Shuttle", f"posted as {p['state']}, {p['url']}")
            run(cortex_cmd(["edit", str(task), "--bodySearch", old, "--bodyReplace", new]), timeout=60)
            print(f"task {task}: round log now ends '{new.strip()[-160:]}'")

    rep.section("round-log", roundlog, "cortex edit <id> --bodySearch '<handed to Shuttle line>' --bodyReplace '<posted line>'", needs=("posted",))

    def refs():
        names = set(facts.get("refs") or [])
        listed = git("for-each-ref", "--format=%(refname)", "refs/pr-review/", timeout=30, check=False)
        mine = re.compile(rf"^refs/pr-review/{srv.number}($|-)")
        names.update(l for l in listed.splitlines() if mine.match(l))
        failed = []
        for ref in sorted(names):
            try:
                git("update-ref", "-d", ref, timeout=30)
                print(f"deleted {ref}")
            except RuntimeError as error:
                failed.append(f"{ref}: {str(error)[-200:]}")
        if not names:
            print("no refs/pr-review refs to delete")
        if failed:
            raise RuntimeError("could not delete " + "; ".join(failed))

    rep.section("refs", refs, f"git update-ref -d refs/pr-review/{srv.number}-<head12>")

    def worktrees():
        try:
            listing = git("worktree", "list", "--porcelain", timeout=30)
        except RuntimeError:
            if not any(name.endswith("-head") for name in (os.listdir(out) if os.path.isdir(out) else [])):
                raise NotApplicable("this git has no worktrees, and there is no worktree folder to remove")
            raise
        gone = 0
        for line in listing.splitlines():
            if line.startswith("worktree ") and os.path.abspath(line[9:]).startswith(os.path.abspath(out)):
                git("worktree", "remove", "--force", line[9:], timeout=60)
                print(f"removed worktree {line[9:]}")
                gone += 1
        if not gone:
            print(f"no worktree under {out}")

    rep.section("worktrees", worktrees, "git worktree remove --force <storage>/pr<n>-head")
    return rep.summary()


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["fetch", "cleanup"])
    p.add_argument("--key", required=True, help="the PR key, such as github:owner/repo#123, or <server>:owner/repo#123 for a forge in private/forges.json")
    p.add_argument("--head", help="the head the request names (a prefix is fine)")
    p.add_argument("--task", help="cleanup: the review's Cortex task id")
    p.add_argument("--out", help="output directory, default $BB_THREAD_STORAGE/pr<number>")
    args = p.parse_args()
    _, _, number = parse_key(args.key)
    storage = os.environ.get("BB_THREAD_STORAGE") or os.path.join(os.getcwd(), "tmp")
    args.out = os.path.abspath(args.out or os.path.join(storage, f"pr{number}"))
    sys.exit(fetch(args) if args.command == "fetch" else cleanup(args))


if __name__ == "__main__":
    main()
