#!/usr/bin/env bash
# collect-context.sh — gather grounding FACTS for a handover brief.
#
# Read-only. Emits a clearly-delimited report the model reads BEFORE it
# synthesizes the handover brief. It does NOT summarize anything — that is
# the model's job. Its only purpose is to surface hard facts (exact paths,
# commands, git state, session metadata, prior compaction summaries, and —
# for a session the model did not live through — the transcript itself) so
# the brief is grounded in evidence rather than the model's fallible memory.
#
# Usage:
#   collect-context.sh                          # SELF mode: the current session ($PI_SESSION_FILE)
#   collect-context.sh --session <target>       # FOREIGN mode: another session
#   collect-context.sh --session <target> --latest   # target is a cortex task with several sessions: pick newest
#
#   <target> = .jsonl path | cortex task id (#123) | pi-<uuid> attribution tag | uuid / >=8-hex prefix
#              (resolved by resolve-session.sh next to this script)
#
# Options:
#   --digest           force the full transcript digest even in SELF mode
#   --no-active-path   do not drop abandoned /tree branches (mine every entry)
#   --out <file>       where to persist the report (default: $TMPDIR/handover-context-<session-id>.md)
#
# The whole report is ALSO written to the --out file, because pi's bash tool
# truncates long output (keeps the tail). If the tool reports truncation,
# `read` the report file instead of re-running.
#
# Env knobs: HANDOVER_DIGEST_LEVEL=full disables per-entry truncation in the digest.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
have() { command -v "$1" >/dev/null 2>&1; }
sep()  { printf '\n===== %s =====\n' "$1"; }

TARGET=""; LATEST=0; FORCE_DIGEST=0; ACTIVE_PATH=1; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --session) shift; TARGET="${1:-}"; [ -n "$TARGET" ] || { echo 'collect-context: --session needs a target' >&2; exit 1; } ;;
    --session=*) TARGET="${1#--session=}"; [ -n "$TARGET" ] || { echo 'collect-context: --session needs a target' >&2; exit 1; } ;;
    --latest) LATEST=1 ;;
    --digest) FORCE_DIGEST=1 ;;
    --no-active-path) ACTIVE_PATH=0 ;;
    --out) shift; OUT="${1:-}" ;;
    --out=*) OUT="${1#--out=}" ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'collect-context: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Resolve WHICH session we are grounding. Foreign targets go through
# resolve-session.sh; its exit code propagates (2 = ambiguous → ask the user).
# ---------------------------------------------------------------------------
MODE="self"
SF="${PI_SESSION_FILE:-}"
RESOLVED=""
if [ -n "$TARGET" ]; then
  args=("$TARGET"); [ "$LATEST" -eq 1 ] && args=(--latest "$TARGET")
  RESOLVED=$("$HERE/resolve-session.sh" "${args[@]}") || exit $?
  SF=$(printf '%s\n' "$RESOLVED" | awk -F' : ' '$1 ~ /^session_file/ {print $2}')
  is_current=$(printf '%s\n' "$RESOLVED" | awk -F' : ' '$1 ~ /^is_current/ {print $2}')
  [ "$is_current" = "yes" ] || MODE="foreign"
fi

rfield() { printf '%s\n' "$RESOLVED" | awk -F' : ' -v k="$1" '$1 ~ "^"k {print $2}'; }

T_ID=""; T_CWD=""; T_CREATED=""; T_LAST=""; T_NAME=""; T_VIA=""; T_CWD_STATE=""
if [ -n "$SF" ] && [ -f "$SF" ] && have jq; then
  hdr=$(head -n 1 "$SF")
  T_ID=$(printf '%s' "$hdr" | jq -r '.id // empty')
  T_CWD=$(printf '%s' "$hdr" | jq -r '.cwd // empty')
  T_CREATED=$(printf '%s' "$hdr" | jq -r '.timestamp // empty')
  T_LAST=$(tail -n 1 "$SF" | jq -r '.timestamp // empty' 2>/dev/null)
  T_NAME=$(jq -rR 'fromjson? | select(.type=="session_info") | .name // empty' "$SF" 2>/dev/null | tail -n 1)
fi
[ -n "$RESOLVED" ] && { T_VIA=$(rfield resolved_via); T_CWD_STATE=$(rfield cwd_state); }

# Git facts come from the TARGET session's cwd in foreign mode, else from here.
GIT_CWD="$PWD"
if [ "$MODE" = "foreign" ] && [ -n "$T_CWD" ]; then GIT_CWD="$T_CWD"; fi
g() { git -C "$GIT_CWD" "$@"; }

if [ -z "$OUT" ]; then
  base="${TMPDIR:-/tmp}"; base="${base%/}"
  OUT="$base/handover-context-${T_ID:-${PI_SESSION_ID:-ephemeral}}.md"
fi

# ---------------------------------------------------------------------------
report() {
printf 'report_file     : %s   (full copy of this output — `read` it if the tool truncated)\n' "$OUT"

sep "SESSION METADATA"
if [ "$MODE" = "foreign" ]; then
  cat <<'EOF'
mode            : FOREIGN — you are grounding a session you did NOT live through.
                  You have NO in-context memory of it. The transcript digest below (and
                  the raw file) is the ONLY source of truth. Do not fill gaps from memory
                  or from the CURRENT conversation. Mark anything the transcript does not
                  prove as unverified. The brief is a snapshot "as of last_activity".
EOF
else
  echo   'mode            : SELF — grounding the current conversation; reconcile with in-context memory.'
fi
printf 'generating_sess : %s  (%s/%s, reasoning=%s)\n' "${PI_SESSION_ID:-<none>}" "${PI_PROVIDER:-?}" "${PI_MODEL:-?}" "${PI_REASONING_LEVEL:-?}"
printf 'generating_cwd  : %s\n' "$PWD"
printf 'generated_at    : %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
echo   '--- target session (the one the brief is ABOUT) ---'
printf 'session_id      : %s\n' "${T_ID:-${PI_SESSION_ID:-<none>}}"
printf 'session_file    : %s\n' "${SF:-<none / ephemeral>}"
printf 'session_cwd     : %s%s\n' "${T_CWD:-$PWD}" "${T_CWD_STATE:+  [$T_CWD_STATE]}"
printf 'session_name    : %s\n' "${T_NAME:--}"
printf 'created         : %s\n' "${T_CREATED:-?}"
printf 'last_activity   : %s\n' "${T_LAST:-?}"
[ -n "$T_VIA" ] && printf 'resolved_via    : %s\n' "$T_VIA"
if [ "$MODE" = "foreign" ]; then
  if [ -n "$SF" ] && [ -f "$SF" ] && have jq; then
    pm=$(jq -rR 'fromjson? | select(.type=="model_change") | .provider + "/" + .modelId' "$SF" 2>/dev/null | tail -n 1)
    [ -n "$pm" ] || pm=$(jq -rR 'fromjson? | select(.type=="message" and .message.role=="assistant") | (.message.provider // "?") + "/" + (.message.model // "?")' "$SF" 2>/dev/null | tail -n 1)
    printf 'provider/model  : %s  (from transcript)\n' "${pm:-?}"
    # Liveness: a file touched in the last 10 minutes may belong to a RUNNING session.
    # mtime, portably. Probe GNU (-c %Y) then BSD (-f %m) and VALIDATE each result:
    # GNU stat treats `-f %m` as --file-system and still prints `  File: "…"` on
    # stdout while exiting 1, so a plain `a || b` chain captures garbage.
    now=$(date +%s)
    mt=$(stat -c %Y "$SF" 2>/dev/null)
    case "$mt" in ''|*[!0-9]*) mt=$(stat -f %m "$SF" 2>/dev/null);; esac
    case "$mt" in ''|*[!0-9]*) mt=$now;; esac
    age=$(( now - mt ))
    if [ "$age" -lt 600 ]; then
      printf 'liveness        : file modified %ss ago — the session MAY STILL BE RUNNING; say so in the brief and treat the tail as in-flight.\n' "$age"
    else
      printf 'liveness        : file idle for %s min — treat as ended/paused.\n' "$(( age / 60 ))"
    fi
  fi
else
  printf 'provider/model  : %s/%s\n' "${PI_PROVIDER:-?}" "${PI_MODEL:-?}"
fi

sep "REPO / GIT STATE (resume runbook facts)"
if [ "$MODE" = "foreign" ]; then
  echo "NOTE: this is the CURRENT state of the target session's cwd ($GIT_CWD),"
  echo "      which may have moved on since last_activity=${T_LAST:-?}. Label it as such in the brief."
fi
if [ ! -d "$GIT_CWD" ]; then
  echo "target cwd does not exist on this machine: $GIT_CWD (no git runbook facts; the brief must say so)"
elif have git && g rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  root=$(g rev-parse --show-toplevel 2>/dev/null)
  branch=$(g rev-parse --abbrev-ref HEAD 2>/dev/null)
  upstream=$(g rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo '<none>')
  printf 'repo_root       : %s\n' "$root"
  printf 'repo_name       : %s\n' "$(basename "$root")"
  printf 'branch          : %s\n' "$branch"
  printf 'upstream        : %s\n' "$upstream"
  printf 'head_commit     : %s\n' "$(g log -1 --oneline 2>/dev/null)"
  printf 'head_date       : %s\n' "$(g log -1 --format=%cI 2>/dev/null)"
  echo   '--- git status --short (uncommitted work) ---'
  g status --short 2>/dev/null | head -60
  echo   '--- recent commits (last 10) ---'
  g log --oneline -10 2>/dev/null
  echo   '--- diff --stat vs upstream/base (best effort) ---'
  base=$(g merge-base HEAD "$upstream" 2>/dev/null)
  if [ -n "${base:-}" ]; then
    g diff --stat "$base"...HEAD 2>/dev/null | tail -40
  else
    g diff --stat 2>/dev/null | tail -40
  fi
  # gh-stack awareness (never invoke interactive form)
  if have gh && (cd "$GIT_CWD" && gh stack view --json >/dev/null 2>&1); then
    echo '--- gh stack view --json (this branch is a stack layer) ---'
    (cd "$GIT_CWD" && gh stack view --json 2>/dev/null | head -40)
  fi
else
  echo "not a git repository: $GIT_CWD (no git runbook facts available)"
fi

sep "CORTEX (durable handoff target)"
if have cortex; then
  lane=$(g rev-parse --show-toplevel 2>/dev/null | xargs -I{} basename {} 2>/dev/null)
  [ -n "$lane" ] || lane=$(basename "$GIT_CWD")
  printf 'cortex_bin      : %s\n' "$(command -v cortex)"
  printf 'suggested_lane  : %s   (derived from the TARGET session cwd)\n' "$lane"
  echo   '--- open tasks in this lane (avoid duplicates; consider cross-linking) ---'
  cortex ls -l "$lane" 2>/dev/null | head -25 || echo '(none / lane empty)'
  case "$T_VIA" in
    task:*)
      src="${T_VIA#task:}"; src="${src%% *}"
      echo "--- source task #$src (the target was resolved from it — cross-link with @$src) ---"
      cortex show "$src" --json 2>/dev/null | jq -r '
        "[\(.task.id)] \(.task.title)  status=\(.task.status) lane=\(.task.lane) tags=\(.task.tags|join(","))",
        "--- last 12 updates (newest first) ---",
        (.updates | sort_by(-.created) | .[0:12][] | "\(.created/1000|todate) [\(.author)] \(.summary)")' 2>/dev/null
      ;;
  esac
else
  echo 'cortex not installed — handover task creation will be skipped; brief still goes to clipboard'
fi

# ---- Everything below mines the persistent session JSONL. -------------------
if [ -z "$SF" ] || [ ! -f "$SF" ]; then
  sep "SESSION TRANSCRIPT"
  echo 'No persistent session file (ephemeral session). Synthesize the brief'
  echo 'from your in-context understanding of the conversation instead.'
  return 0
fi
if ! have jq; then
  sep "SESSION TRANSCRIPT"
  echo 'jq not installed — cannot mine the session file. Synthesize the brief'
  echo 'from your in-context understanding of the conversation instead.'
  return 0
fi

# Active path: pi's leaf on reload is the LAST entry; walk parentId to the root.
# Entries off that path are abandoned /tree branches — noise for a cold reader.
AP="$SF"
total=$(wc -l < "$SF" | tr -d ' ')
if [ "$ACTIVE_PATH" -eq 1 ]; then
  tmpd=$(mktemp -d -t handover-ap.XXXXXX)
  jq -rR 'fromjson? | select(.type!="session" and has("id")) | [.id, (.parentId // "")] | @tsv' "$SF" > "$tmpd/adj" 2>/dev/null
  awk -F'\t' '{ p[$1]=$2; last=$1 } END { id=last; while (id != "" && !(id in seen)) { seen[id]=1; print id; id=p[id] } }' "$tmpd/adj" > "$tmpd/keep"
  if [ -s "$tmpd/keep" ]; then
    jq -Rn '[inputs] | map({(.):true}) | add // {}' "$tmpd/keep" > "$tmpd/keep.json"
    APF="${OUT%.md}.active.jsonl"   # kept next to the report for drill-down
    jq -cR --slurpfile keep "$tmpd/keep.json" 'fromjson? | select(.type=="session" or (.id != null and ($keep[0][.id] // false)))' "$SF" > "$APF" 2>/dev/null
    kept=$(wc -l < "$APF" | tr -d ' ')
    if [ "${kept:-0}" -gt 1 ]; then AP="$APF"; else rm -f "$APF"; fi
  fi
  rm -f "$tmpd/adj" "$tmpd/keep" "$tmpd/keep.json"; rmdir "$tmpd" 2>/dev/null
fi
sep "ACTIVE PATH (what the session actually 'is')"
if [ "$AP" = "$SF" ]; then
  printf 'entries_total   : %s   (active-path filter %s — mining every entry)\n' "$total" "$([ "$ACTIVE_PATH" -eq 1 ] && echo 'unavailable' || echo 'disabled')"
else
  printf 'entries_total   : %s\nentries_active  : %s\nentries_dropped : %s   (abandoned /tree branches — NOT part of the final conversation)\n' "$total" "$kept" "$(( total - kept ))"
  printf 'active_path_file: %s\n' "$AP"
fi

# Shared jq helper: flatten a content field (string OR array of blocks) to text.
JQDEF='def totext: if type=="string" then . elif type=="array" then ([.[] | select(.type=="text") | .text] | join("\n")) else "" end;'
J() { jq -rR "$JQDEF"' fromjson? | '"$1" "$AP" 2>/dev/null; }

sep "ENTRY-TYPE HISTOGRAM (shape of the conversation)"
J '.type + (if .message then ":"+.message.role else "" end)' | sort | uniq -c

sep "PRIOR COMPACTION / BRANCH SUMMARIES (fold these in — they hold dropped context)"
found=$(J 'select(.type=="compaction" or .type=="branch_summary") | "### ["+.type+" @ "+(.timestamp|tostring)+"]\n"+(.summary // "")')
if [ -n "$found" ]; then echo "$found"; else echo '(none — full history is intact in the transcript below)'; fi

sep "ORIGINAL REQUEST (first user message — preserve intent VERBATIM)"
J 'select(.type=="message" and .message.role=="user") | .message.content | totext' | head -80

sep "ALL USER MESSAGES (the human's steering signal, in order — includes scope changes; #1's full text is in ORIGINAL REQUEST above)"
J 'select(.type=="message" and .message.role=="user") | "----\n" + (.message.content | totext)' | head -400 | awk '
  /^----$/ { n++; if (n==1) { print "---- [user message #1 — full verbatim text is in ORIGINAL REQUEST above]"; skip=1; next } else { skip=0 } }
  skip==1 { next }
  { print }'

sep "FILES READ (read/fetch tool calls — the map of what was inspected)"
J 'select(.type=="message" and .message.role=="assistant") | .message.content[]? | select(.type=="toolCall" and (.name=="read" or .name=="web_fetch" or .name=="fetch_content")) | (.arguments.path // .arguments.url // empty), (.arguments.urls[]? // empty)' | awk 'NF' | sort -u | head -80

sep "FILES MODIFIED (edit/write tool calls — the change surface)"
J 'select(.type=="message" and .message.role=="assistant") | .message.content[]? | select(.type=="toolCall" and (.name=="edit" or .name=="write")) | .arguments.path // empty' | awk 'NF' | sort -u | head -80

sep "COMMANDS RUN (bash tool calls + inline executions — reusable runbook)"
{
  J 'select(.type=="message" and .message.role=="assistant") | .message.content[]? | select(.type=="toolCall" and .name=="bash") | .arguments.command // empty'
  J 'select(.type=="message" and .message.role=="bashExecution") | .message.command // empty'
} | awk 'NF' | sed 's/\n/ /g' | cut -c1-200 | awk '!seen[$0]++' | tail -50

sep "MODEL CHANGES (context on capability shifts mid-session)"
J 'select(.type=="model_change") | "-> "+(.provider // "?")+"/"+(.modelId // "?")+" @ "+(.timestamp|tostring)' | head -20 || true

sep "LAST ASSISTANT MESSAGE (most recent state of thinking — where things stand)"
J 'select(.type=="message" and .message.role=="assistant") | .message.content | totext' | awk 'NF' | tail -60

# ---------------------------------------------------------------------------
# Foreign mode: the model never saw this conversation, so surface the whole
# active path as a bounded, ordered digest (user + assistant text, tool calls
# as one-liners, bash results + tool errors, compactions, model changes).
# ---------------------------------------------------------------------------
if [ "$MODE" = "foreign" ] || [ "$FORCE_DIGEST" -eq 1 ]; then
  if [ "${HANDOVER_DIGEST_LEVEL:-}" = "full" ]; then U=1000000; A=1000000; T=1000000; E=1000000; S=1000000
  else U=4000; A=3000; T=240; E=600; S=8000; fi
  sep "TRANSCRIPT DIGEST (active path, chronological — READ ALL OF IT; this is your only memory of the session)"
  echo "legend: USER / ASSISTANT text; '→ tool {args}' = tool call; TOOL-ERROR / BASH-RESULT = evidence; per-entry caps user=$U assistant=$A toolargs=$T results=$E summaries=$S chars (HANDOVER_DIGEST_LEVEL=full lifts them)"
  jq -rR --argjson U "$U" --argjson A "$A" --argjson T "$T" --argjson E "$E" --argjson S "$S" "$JQDEF"'
    def cut($n): if length > $n then .[0:$n] + "\n…[+" + ((length - $n)|tostring) + " chars truncated — drill down with jq]" else . end;
    def ts: ((.timestamp // "?") | tostring | .[5:16]);
    fromjson? | select(has("type")) |
    if .type=="message" then
      (.message.role) as $r |
      if $r=="user" then
        "\n[" + ts + " USER #" + .id + "]\n" + (.message.content | totext | cut($U))
      elif $r=="assistant" then
        "\n[" + ts + " ASSISTANT #" + .id + " " + (.message.model // "")
          + (if (.message.stopReason=="error" or .message.stopReason=="aborted") then " !" + .message.stopReason + " " + (.message.errorMessage // "") else "" end) + "]\n"
          + ([ .message.content[]?
               | if .type=="text" then (.text | cut($A))
                 elif .type=="toolCall" then "→ " + .name + " " + (.arguments | tojson | cut($T))
                 else empty end ] | join("\n"))
      elif $r=="toolResult" then
        if .message.isError then
          "\n[" + ts + " TOOL-ERROR " + (.message.toolName // "?") + " call=" + (.message.toolCallId // "?") + "]\n" + (.message.content | totext | cut($E))
        elif (.message.toolName // "") == "bash" then
          "\n[" + ts + " BASH-RESULT call=" + (.message.toolCallId // "?") + "]\n" + (.message.content | totext | cut($E))
        else empty end
      elif $r=="bashExecution" then
        "\n[" + ts + " BASH! exit=" + ((.message.exitCode // "?")|tostring) + "]\n$ " + (.message.command // "") + "\n" + ((.message.output // "") | cut($E))
      elif $r=="custom" then
        "\n[" + ts + " CUSTOM " + (.message.customType // "?") + "]\n" + (.message.content | totext | cut($E))
      else empty end
    elif .type=="compaction" then "\n[" + ts + " COMPACTION tokensBefore=" + ((.tokensBefore // 0)|tostring) + "]\n" + ((.summary // "") | cut($S))
    elif .type=="branch_summary" then "\n[" + ts + " BRANCH-SUMMARY]\n" + ((.summary // "") | cut($S))
    elif .type=="custom_message" then "\n[" + ts + " EXT-MESSAGE " + (.customType // "?") + "]\n" + (.content | totext | cut($E))
    elif .type=="model_change" then "\n[" + ts + " MODEL → " + (.provider // "?") + "/" + (.modelId // "?") + "]"
    elif .type=="thinking_level_change" then "\n[" + ts + " THINKING → " + (.thinkingLevel // "?") + "]"
    elif .type=="session_info" then "\n[" + ts + " SESSION NAME: " + (.name // "") + "]"
    elif .type=="label" then "\n[" + ts + " LABEL " + (.label // "<cleared>") + " on #" + (.targetId // "?") + "]"
    else empty end' "$AP" 2>/dev/null

  sep "DRILL-DOWN CHEAT SHEET (raw file; use when the digest truncated something you need as evidence)"
  cat <<EOF
# a specific entry by id
jq -c 'select(.id=="<entry-id>")' "$AP"
# a tool result by toolCallId (evidence for a claim)
jq -r 'select(.type=="message" and .message.role=="toolResult" and .message.toolCallId=="<call-id>") | .message.content[] | select(.type=="text") | .text' "$AP"
# all tool calls of one tool with their arguments
jq -c 'select(.type=="message" and .message.role=="assistant") | .message.content[]? | select(.type=="toolCall" and .name=="edit") | .arguments' "$AP"
# grep the transcript
grep -n -i '<term>' "$AP" | cut -c1-300
# full text of an assistant message
jq -r 'select(.id=="<entry-id>") | .message.content[] | select(.type=="text") | .text' "$AP"
EOF
fi

sep "END OF GROUNDING FACTS"
printf 'report_file     : %s\n' "$OUT"
if [ "$MODE" = "foreign" ]; then
  echo 'Now synthesize the handover brief per references/brief-template.md FOR THE TARGET SESSION.'
  echo 'The transcript digest is your only memory of it: quote it for evidence, mark gaps as'
  echo 'unverified, set provenance origin = target session, and note the snapshot time.'
else
  echo 'Now synthesize the handover brief per references/brief-template.md.'
  echo 'Use these facts to VERIFY and enrich your in-context memory — do not rely'
  echo 'on memory alone for exact paths, commands, and the verbatim request.'
fi
}

report 2>&1 | tee "$OUT"
