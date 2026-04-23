---
description: Extract topics, brief summaries, and topic-grouped action items from a Google Doc meeting notes link (read-only)
---

Load the `meeting-notes` skill and follow its instructions to process the Google Doc: $ARGUMENTS

## Pre-requisites

Run these checks in order before loading the skill. Stop at the first failure.

1. **Resolve URL**: Extract a Google Doc URL from `$ARGUMENTS` matching `https?://docs\.google\.com/document/d/[a-zA-Z0-9_-]+`. If missing, prompt the user.
2. **Verify gcloud**: Confirm `timeout 5 which gcloud` succeeds. If not, STOP and tell the user to install the Google Cloud SDK.
3. **Verify auth**: Confirm `timeout 10 gcloud auth print-access-token` returns a non-empty token. If not, STOP and tell the user to run `gcloud auth login`.

## Rules

- **ALWAYS** load the `meeting-notes` skill first for detailed instructions
- **NEVER** issue any non-GET API call to Google services — read-only access is a hard requirement
- **NEVER** modify the source Google Doc in any way (no comments, edits, shares, moves, renames, trash)
- **NEVER** add ad-hoc `curl`/`wget` calls; only the skill's orchestrator script talks to Google
- **NEVER** scan the filesystem without `timeout <N>` + bounded scope (`-maxdepth`, explicit path)
- **ALWAYS** evaluate all tabs (including nested `childTabs`) and all linked Sheets
- **ALWAYS** STOP loudly on auth/permission errors — no silent fallback
- **ALWAYS** cite the source tab + locator for every action item and open question
- **ALWAYS** use `skill-improver` to capture observations after skill execution completes
