Weekly disk report for Kalindu's Mac, run by a bb automation every Friday at 2pm. This run is read-only until Kalindu picks items: do not delete, move, prune, trim or clean anything before then. Only measure and propose.

1. Run `~/bin/disk-audit` with a 1800 second timeout. It takes about 7 minutes and prints the new snapshot folder on its last line. Sizes in its files are KiB; divide by 1048576 for GiB.
   - summary.txt: free space, deleted files still held open, the Trash.
   - home.tsv: every folder of 50 MiB or more, five levels under ~ and three under ~/Library.
   - system.tsv: /Applications, /opt, the Homebrew Cellar, temp dirs.
   - repos.tsv: size, path, last activity, changed files, untracked files, stashes, local-only commits, worktrees.
   - toolchains.txt: installed Go, Rust, Node, Ruby and envtest versions, version pins, the brew cleanup estimate.
   - containers.txt: the Podman machine, its disk file, images and containers.
   - bb.txt: Loom projects, bb worktrees and the largest thread storage, with thread status.
   - scratch.txt: old entries in /private/tmp and the user temp dir, and which are open.
   - local.txt and local-rules.md, when present: sections and rules for this machine only. Read both; their rules add to the ones below.
2. Compare with the previous snapshot, the newest older folder in ~/.local/share/disk-audit/snapshots. Report free space then and now, and the folders in home.tsv and system.tsv that grew or shrank by 1 GiB or more. Look into anything that grew by 5 GiB or more and say why it grew.
3. Build a cleanup list. Give each item an id (A1, A2, ...), its size in GiB, the exact way to remove it, and a rating: safe (caches, build output, regenerable data; nothing is lost) or check (needs Kalindu's decision). Typical candidates: the Go build cache, npm, pnpm, Yarn, uv and pip caches, `brew cleanup --prune=all`, Podman images no container uses, Rust target, node_modules and .terraform providers in repos idle for weeks, repos in ~/src idle 6+ months, toolchain versions nothing pins, old /tmp and temp entries, bb worktrees and thread storage of archived threads, and files in ~/Downloads.
4. Reply to Kalindu. Open with one sentence giving free space now and the change since the last snapshot. Then say what grew, and show the cleanup list as one ```ui block built from the template at the end of this prompt: fill in `items`, `groups`, the title date and the two Metric values, and keep the rest as it is. Ask which items to clean. When Kalindu replies with picks in this thread, clean exactly those items, log each step with the space it freed, and report the result.
5. If free space is above 150 GiB and nothing grew by more than 10 GiB, keep the reply short: the numbers, what grew, and the top 5 candidates.

Rules:
- Never propose removing the Nix store (/nix), ~/go/pkg/mod, ~/backup, ~/.local/share/disk-audit, or anything a running or paused Loom project uses (check `bb loom list` and `bb loom show <slug>`).
- A repo idle 6+ months with no changed or untracked files, stashes or local-only commits is safe. A repo with any of those is check, and its local work must be backed up under ~/backup before deleting it: a git bundle of the local-only commits, stash and diff patches, and a tar of the untracked files. A local-only commit may already be merged through a squash merge.
- Keep every Ruby, Rust, Node or Go version that a pin in toolchains.txt names.
- Skip anything a process has open (check with lsof), and anything in /tmp or the temp dir modified in the last day. bb runs from a dev.bb.desktop.ShipIt.* folder in the temp dir; never touch those.
- Known traps: `podman system prune` also deletes the stopped kind clusters, so use `podman image prune -a`, then `podman machine ssh sudo fstrim -av` to shrink the VM disk file. The bash guard blocks `rm -rf` outside /tmp, so use `chmod -R u+w` and `rm -r` on exact paths. Root-owned items (apps in /Applications, /opt, /Library) need a sudo script that Kalindu runs.
- About 88 GiB sits in macOS-protected folders (Trash, Spotlight index, Google Drive) that this shell cannot read unless the terminal has Full Disk Access. Mention the Trash when summary.txt shows it changed since last week.
- Sizes are binary GiB. Finder shows decimal GB, about 7% larger.

Snapshot folders are named YYYY-MM-DDTHHMM, so a manual run on the same day as another never overwrites it.

Report template (tested; it renders a Metric row, a tab per group, a checklist with the safe items preselected, a live total and a Copy my picks button):

```ui
items = [
  {id: "A1", group: "Caches", what: "Go build cache", gib: 4.2, how: "go clean -cache", rating: "safe"},
  {id: "B1", group: "Repos", what: "Repo X, idle since 2024, with a stash", gib: 1.1, how: "back up the stash, then delete", rating: "check"}
]
label = (i) => `${i.id} · ${i.what} (${fmt(i.gib, 1)} GiB)`
safe = items.filter(i => i.rating == "safe").map(i => label(i))
$picks = safe
picked = items.filter(i => $picks.includes(label(i)))
groups = ["Caches", "Repos"]
Card("Weekly disk report · 2026-10-30", [
  Row([Metric("Free now", "269.3 GiB"), Metric("Since last report", "−2.9 GiB"), Metric("Picked", `${fmt(sum(picked.map(i => i.gib)), 1)} GiB`, `${picked.length} items`, tone: "good")]),
  Tabs(groups, groups.map(g => Table(["Id", "What", "GiB", "How to remove", "Rating"], items.filter(i => i.group == g).map(i => [i.id, i.what, i.gib, i.how, Badge(i.rating, tone: i.rating == "safe" ? "good" : "warn")])))),
  Checklist($picks, items.map(i => label(i)), label: "Clean these"),
  Row([Button("Only the safe ones", Set($picks, safe), variant: "secondary", icon: "RotateCcw"), Button("Copy my picks", Copy("Clean: " + picked.map(i => i.id).join(", ")), variant: "primary", icon: "Copy")])
])
```

If the check_ui tool is available, run the finished block through it before replying.
