#!/usr/bin/env bash
# resolve-session.sh — turn a handover TARGET into a pi session file path.
#
# Read-only. Used by `/handover <target>` so a brief can be generated for a session
# OTHER than the current one. Accepts every identifier a user is likely to
# have at hand and prints machine-readable `key : value` facts about the
# resolved session (path, id, cwd, timestamps, size, name).
#
# Usage:
#   resolve-session.sh [--latest] [--session-dir DIR] <target>
#
# Target forms (detected in this order):
#   /abs/or/rel/path.jsonl   a pi session file (anything containing "/" or ending in .jsonl)
#   #123 | 123 | task:123    a cortex task id -> the pi-attributed sessions in its updates
#   pi-<uuid> | <uuid>       a cortex attribution tag / pi session id (full uuid)
#   <uuid-prefix>            >= 8 hex chars of a session id (pi --session semantics)
#
# Exit codes:
#   0  resolved to exactly one session file (facts on stdout)
#   2  ambiguous — several candidates; a numbered table is printed. Re-run with
#      the chosen `pi-<uuid>`, or pass --latest to auto-pick the most recent.
#   1  not found / malformed target / missing dependency
#
# Search roots: --session-dir, else $PI_CODING_AGENT_SESSION_DIR, else
# ~/.pi/agent/sessions. Searched recursively (minion sessions live in a
# `minions/` subdirectory). Filename glob first, header scan as fallback, and
# the header `id` is always verified against the requested id.

set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
die()  { printf 'resolve-session: %s\n' "$*" >&2; exit 1; }

LATEST=0
SESSION_DIR=""
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --latest) LATEST=1 ;;
    --session-dir) shift; SESSION_DIR="${1:-}" ;;
    --session-dir=*) SESSION_DIR="${1#--session-dir=}" ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown flag: $1" ;;
    *) [ -n "$TARGET" ] && die "only one target allowed (got '$TARGET' and '$1')"; TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || die "no target given (see --help)"
have jq || die "jq is required"

ROOT="${SESSION_DIR:-${PI_CODING_AGENT_SESSION_DIR:-$HOME/.pi/agent/sessions}}"
ROOT="${ROOT/#\~/$HOME}"
[ -d "$ROOT" ] || die "session root not found: $ROOT"

UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
HEXPREFIX_RE='^[0-9a-fA-F-]{8,}$'

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# header_field FILE FIELD -> value from the first line (session header), or ""
header_field() { head -n 1 "$1" 2>/dev/null | jq -r --arg f "$2" '.[$f] // empty' 2>/dev/null; }

# Print the resolved facts for one session file and exit 0.
emit() {
  local f="$1" via="$2"
  [ -f "$f" ] || die "resolved path is not a file: $f"
  local abs; abs=$(cd "$(dirname "$f")" 2>/dev/null && printf '%s/%s' "$PWD" "$(basename "$f")") || abs="$f"
  local hdr; hdr=$(head -n 1 "$abs" 2>/dev/null)
  local hid hcwd hts
  hid=$(printf '%s' "$hdr" | jq -r '.id // empty' 2>/dev/null)
  hcwd=$(printf '%s' "$hdr" | jq -r '.cwd // empty' 2>/dev/null)
  hts=$(printf '%s' "$hdr" | jq -r '.timestamp // empty' 2>/dev/null)
  [ -n "$hid" ] || die "no session header (first line lacks .id) — not a pi session file: $abs"
  local last name entries size
  last=$(tail -n 1 "$abs" 2>/dev/null | jq -r '.timestamp // empty' 2>/dev/null)
  name=$(jq -rR 'fromjson? | select(.type=="session_info") | .name // empty' "$abs" 2>/dev/null | tail -n 1)
  entries=$(wc -l < "$abs" | tr -d ' ')
  size=$(du -h "$abs" 2>/dev/null | cut -f1 | tr -d ' ')
  local same="no"
  [ "${PI_SESSION_ID:-}" = "$hid" ] && same="yes"
  local cwd_state="present"
  [ -d "$hcwd" ] || cwd_state="MISSING (repo facts unavailable; brief must say so)"
  printf 'resolved_via    : %s\n' "$via"
  printf 'session_file    : %s\n' "$abs"
  printf 'session_id      : %s\n' "$hid"
  printf 'session_cwd     : %s\n' "${hcwd:-<none>}"
  printf 'cwd_state       : %s\n' "$cwd_state"
  printf 'created         : %s\n' "${hts:-?}"
  printf 'last_activity   : %s\n' "${last:-?}"
  printf 'entries         : %s\n' "$entries"
  printf 'size            : %s\n' "$size"
  printf 'session_name    : %s\n' "${name:--}"
  printf 'is_current      : %s\n' "$same"
  exit 0
}

# find_by_uuid UUID_OR_PREFIX [exact:1|0] -> newline list of matching files
find_by_uuid() {
  local id; id=$(lower "$1"); local exact="$2" out
  if [ "$exact" = 1 ]; then
    out=$(find "$ROOT" -type f -name "*_${id}.jsonl" 2>/dev/null)
  else
    out=$(find "$ROOT" -type f -name "*_${id}*.jsonl" 2>/dev/null)
  fi
  # Fallback: filename did not match (renamed/custom file) — scan headers.
  if [ -z "$out" ]; then
    out=$(find "$ROOT" -type f -name '*.jsonl' -print0 2>/dev/null \
      | xargs -0 -n 50 sh -c 'for f; do h=$(head -n 1 "$f" 2>/dev/null); case "$h" in *"\"id\":\"$0"*) printf "%s\n" "$f";; esac; done' "$id" 2>/dev/null)
  fi
  # Verify header id (prefix match) so a stray filename cannot mislead.
  local f hid keep=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    hid=$(lower "$(header_field "$f" id)")
    case "$hid" in "$id"*) keep="${keep}${f}"$'\n' ;; esac
  done <<EOF
$out
EOF
  printf '%s' "$keep"
}

# ---------------------------------------------------------------- 1. path --
case "$TARGET" in
  */*|*.jsonl)
    f="${TARGET/#\~/$HOME}"
    [ -f "$f" ] || die "session file not found: $f"
    emit "$f" "path"
    ;;
esac

# ------------------------------------------------------- 2. cortex task id --
t="${TARGET#\#}"; t="${t#task:}"
if printf '%s' "$t" | grep -Eq '^[0-9]+$'; then
  have cortex || die "target looks like a cortex task id but cortex is not installed"
  json=$(cortex show "$t" --json 2>&1) || die "cortex show $t failed: $json"
  title=$(printf '%s' "$json" | jq -r '.task.title // "?"')
  # Aggregate pi-attributed authors exactly like `cortex resume`: uuidv7-shaped
  # suffix only, newest lastSeen first.
  cands=$(printf '%s' "$json" | jq -r '
    [ .updates[]
      | select(.author | test("^pi-[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")) ]
    | group_by(.author)
    | map({ author: .[0].author,
            count: length,
            lastSeen: (map(.created) | max),
            lastSummary: ((sort_by(.created) | last).summary // "") })
    | sort_by(-.lastSeen)
    | .[] | [ .author, (.count|tostring), (.lastSeen/1000|todate), (.lastSummary|gsub("[\\n\\t]"; " ")|.[0:70]) ] | @tsv')
  n=$(printf '%s\n' "$cands" | awk 'NF' | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || die "task $t ('$title') has no pi-attributed (resumable) sessions in its updates — nothing to resolve. Pass a session file or id instead."
  if [ "$n" -gt 1 ] && [ "$LATEST" -ne 1 ]; then
    {
      printf 'resolve-session: task %s (%s) has %s pi-attributed sessions — AMBIGUOUS.\n' "$t" "$title" "$n"
      printf 'Ask the user which one to hand over, or re-run with --latest for the most recent.\n\n'
      printf '#\tauthor (pass this back as the target)\tupdates\tlast update (UTC)\tlast summary\ton disk\n'
      i=0
      printf '%s\n' "$cands" | awk 'NF' | while IFS=$'\t' read -r author count last summary; do
        i=$((i+1)); uuid="${author#pi-}"
        files=$(find_by_uuid "$uuid" 1); ondisk="yes"; [ -n "$files" ] || ondisk="NOT FOUND"
        printf '%s\t%s\t×%s\t%s\t"%s"\t%s\n' "$i" "$author" "$count" "$last" "$summary" "$ondisk"
      done
    } >&2
    exit 2
  fi
  author=$(printf '%s\n' "$cands" | awk 'NF' | head -n 1 | cut -f1)
  [ "$n" -gt 1 ] && printf 'resolve-session: --latest picked %s (of %s sessions on task %s)\n' "$author" "$n" "$t" >&2
  files=$(find_by_uuid "${author#pi-}" 1)
  [ -n "$files" ] || die "task $t points at $author but no session file *_${author#pi-}.jsonl exists under $ROOT (different machine or deleted?)"
  emit "$(printf '%s\n' "$files" | head -n 1)" "task:$t → $author"
fi

# ------------------------------------------- 3. attribution tag / uuid(-prefix) --
u="$TARGET"; u="${u#pi-}"
if printf '%s' "$u" | grep -Eq "$UUID_RE"; then
  files=$(find_by_uuid "$u" 1)
  [ -n "$files" ] || die "no session file with id $u under $ROOT"
  emit "$(printf '%s\n' "$files" | head -n 1)" "session-id:$u"
elif printf '%s' "$u" | grep -Eq "$HEXPREFIX_RE"; then
  files=$(find_by_uuid "$u" 0)
  n=$(printf '%s' "$files" | awk 'NF' | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || die "no session id starting with '$u' under $ROOT"
  if [ "$n" -gt 1 ]; then
    {
      printf 'resolve-session: prefix %s matches %s sessions — AMBIGUOUS. Use a longer prefix or the full id:\n\n' "$u" "$n"
      printf '%s\n' "$files" | awk 'NF' | while IFS= read -r f; do
        printf '%s\t%s\t%s\n' "$(header_field "$f" id)" "$(header_field "$f" cwd)" "$f"
      done
    } >&2
    exit 2
  fi
  emit "$(printf '%s\n' "$files" | awk 'NF' | head -n 1)" "session-id-prefix:$u"
fi

die "unrecognised target '$TARGET' — expected a .jsonl path, a cortex task id (#123), a pi-<uuid> attribution tag, or a session uuid/prefix (>= 8 hex chars)"
