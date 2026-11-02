---
name: bb-sync
description: Capture or restore the work-free bb setup in the shell repo, review the changes, and commit and push when requested. Use for syncing existing bb preferences across machines, not for editing plugins or moving a bb server.
---

## Scope

Locate the shell checkout from this file's real path: four directories above its folder. Read `docs/bb.md` there for the current branch's commands, exclusions, and Ruby workaround. Work in that checkout, not `~/.bb` or a Nix store copy.

## Capture and publish

1. Check the current branch, upstream, and staged and unstaged changes. Record existing work so it is not accidentally included. Confirm `bb status` points at the intended server.
2. On the machine whose preferences should be kept, run `task bb:export`, then `task check:leaks`. STOP on a failure; NEVER bypass privacy checks or expand the allowlist automatically.
3. Review the diff in `bb.yml`, including `ui_capture_allowlist`. Keep only approved work-free settings. Report excluded or unavailable items; do not silently promote them. Use any separate backup commands in `docs/bb.md` only when the user requested those categories too.
4. Commit and push ONLY when the user explicitly requested them. Follow the repo's Git protocol, stage only the reviewed sync files, and inspect the staged diff. NEVER include unrelated staged work, use `git add -A`, or force-push. If there is no relevant diff, report that and skip the commit.
5. Push the requested branch and verify its remote tip matches the local commit. Updating another maintained branch requires an explicit request and branch-aware integration, not copying installer files.

## Restore

When the user asks to apply the saved setup on another machine, run `task bb:plan` and inspect its commands before `task bb`. Do not export the target machine first: that would replace the preferred source's saved settings. NEVER restore automations or private overlays as part of an ordinary settings sync.

## Privacy and completion

- NEVER copy the bb data directory, database, history, credentials, private endpoints, or work-specific configuration into the repo.
- Use the branch's documented process-local Ruby workaround if needed. NEVER run the full installer, stow, or a Nix switch to repair a capture command.
- Report the settings files changed, privacy-check result, commit and branch pushed, remote verification, and any exclusions or untested restore steps. Do not print secret values.
