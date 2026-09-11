#!/usr/bin/env bash
# collect-context.sh — gather grounding FACTS for a /handover brief.
#
# Read-only. Emits a clearly-delimited report the model reads BEFORE it
# synthesizes the handover brief. It does NOT summarize anything — that is
# the model's job. Its only purpose is to surface hard facts (exact paths,
# commands, git state, session metadata, prior compaction summaries) so the
# brief is grounded in evidence rather than the model's fallible memory.
#
# Usage: collect-context.sh
# Relies on PI_SESSION_* env vars injected into pi's bash tool.

set -uo pipefail

sep() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

sep "SESSION METADATA"
printf 'session_id      : %s\n' "${PI_SESSION_ID:-<none>}"
printf 'session_file    : %s\n' "${PI_SESSION_FILE:-<none / ephemeral>}"
printf 'provider/model  : %s/%s\n' "${PI_PROVIDER:-?}" "${PI_MODEL:-?}"
printf 'reasoning_level : %s\n' "${PI_REASONING_LEVEL:-?}"
printf 'cwd             : %s\n' "$PWD"
printf 'generated_at    : %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"

sep "REPO / GIT STATE (resume runbook facts)"
if have git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo '<none>')
  printf 'repo_root       : %s\n' "$root"
  printf 'repo_name       : %s\n' "$(basename "$root")"
  printf 'branch          : %s\n' "$branch"
  printf 'upstream        : %s\n' "$upstream"
  printf 'head_commit     : %s\n' "$(git log -1 --oneline 2>/dev/null)"
  echo   '--- git status --short (uncommitted work) ---'
  git status --short 2>/dev/null | head -60
  echo   '--- recent commits (last 10) ---'
  git log --oneline -10 2>/dev/null
  echo   '--- diff --stat vs upstream/base (best effort) ---'
  base=$(git merge-base HEAD "$upstream" 2>/dev/null)
  if [ -n "${base:-}" ]; then
    git diff --stat "$base"...HEAD 2>/dev/null | tail -40
  else
    git diff --stat 2>/dev/null | tail -40
  fi
  # gh-stack awareness (never invoke interactive form)
  if have gh && gh stack view --json >/dev/null 2>&1; then
    echo '--- gh stack view --json (this branch is a stack layer) ---'
    gh stack view --json 2>/dev/null | head -40
  fi
else
  echo 'not a git repository (no git runbook facts available)'
fi

sep "CORTEX (durable handoff target)"
if have cortex; then
  lane=$(git rev-parse --show-toplevel 2>/dev/null | xargs -I{} basename {} 2>/dev/null || basename "$PWD")
  printf 'cortex_bin      : %s\n' "$(command -v cortex)"
  printf 'suggested_lane  : %s\n' "$lane"
  echo   '--- open tasks in this lane (avoid duplicates; consider cross-linking) ---'
  cortex ls -l "$lane" 2>/dev/null | head -25 || echo '(none / lane empty)'
else
  echo 'cortex not installed — handover task creation will be skipped; brief still goes to clipboard'
fi

# ---- Everything below mines the persistent session JSONL. -------------------
SF="${PI_SESSION_FILE:-}"
if [ -z "$SF" ] || [ ! -f "$SF" ]; then
  sep "SESSION TRANSCRIPT"
  echo 'No persistent session file (ephemeral session). Synthesize the brief'
  echo 'from your in-context understanding of the conversation instead.'
  exit 0
fi
if ! have jq; then
  sep "SESSION TRANSCRIPT"
  echo 'jq not installed — cannot mine the session file. Synthesize the brief'
  echo 'from your in-context understanding of the conversation instead.'
  exit 0
fi

# Shared jq helper: flatten a content field (string OR array of blocks) to text.
JQDEF='def totext: if type=="string" then . elif type=="array" then ([.[] | select(.type=="text") | .text] | join("\n")) else "" end;'

sep "ENTRY-TYPE HISTOGRAM (shape of the conversation)"
jq -r '.type + (if .message then ":"+.message.role else "" end)' "$SF" 2>/dev/null | sort | uniq -c

sep "PRIOR COMPACTION / BRANCH SUMMARIES (fold these in — they hold dropped context)"
found=$(jq -r 'select(.type=="compaction" or .type=="branch_summary") | "### ["+.type+" @ "+(.timestamp|tostring)+"]\n"+(.summary // "")' "$SF" 2>/dev/null)
if [ -n "$found" ]; then echo "$found"; else echo '(none — full history is intact in the transcript below)'; fi

sep "ORIGINAL REQUEST (first user message — preserve intent VERBATIM)"
jq -r "$JQDEF"' select(.type=="message" and .message.role=="user") | .message.content | totext' "$SF" 2>/dev/null | head -80

sep "ALL USER MESSAGES (the human's steering signal, in order — includes scope changes)"
jq -r "$JQDEF"' select(.type=="message" and .message.role=="user") | "----\n" + (.message.content | totext)' "$SF" 2>/dev/null | head -400

sep "FILES READ (read/fetch tool calls — the map of what was inspected)"
jq -r 'select(.type=="message" and .message.role=="assistant") | .message.content[]? | select(.type=="toolCall" and (.name=="read" or .name=="fetch_content")) | .arguments.path // .arguments.url // empty' "$SF" 2>/dev/null | awk 'NF' | sort -u | head -80

sep "FILES MODIFIED (edit/write tool calls — the change surface)"
jq -r 'select(.type=="message" and .message.role=="assistant") | .message.content[]? | select(.type=="toolCall" and (.name=="edit" or .name=="write")) | .arguments.path // empty' "$SF" 2>/dev/null | awk 'NF' | sort -u | head -80

sep "COMMANDS RUN (bash tool calls + inline executions — reusable runbook)"
{
  jq -r 'select(.type=="message" and .message.role=="assistant") | .message.content[]? | select(.type=="toolCall" and .name=="bash") | .arguments.command // empty' "$SF" 2>/dev/null
  jq -r 'select(.type=="message" and .message.role=="bashExecution") | .message.command // empty' "$SF" 2>/dev/null
} | awk 'NF' | sed 's/\n/ /g' | cut -c1-200 | awk '!seen[$0]++' | tail -50

sep "MODEL CHANGES (context on capability shifts mid-session)"
jq -r 'select(.type=="model_change") | "-> "+(.provider // "?")+"/"+(.modelId // "?")+" @ "+(.timestamp|tostring)' "$SF" 2>/dev/null | head -20 || true

sep "LAST ASSISTANT MESSAGE (most recent state of thinking — where things stand)"
jq -r "$JQDEF"' select(.type=="message" and .message.role=="assistant") | .message.content | totext' "$SF" 2>/dev/null | awk 'NF' | tail -60

sep "END OF GROUNDING FACTS"
echo 'Now synthesize the handover brief per references/brief-template.md.'
echo 'Use these facts to VERIFY and enrich your in-context memory — do not rely'
echo 'on memory alone for exact paths, commands, and the verbatim request.'
