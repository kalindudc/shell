#!/usr/bin/env bash
# herdr-pickup.sh — Phase 4 of the handover skill (the ONLY place this skill
# drives Herdr).
#
# Inside a Herdr pane: split this pane, start a fresh pi in the new pane, send
# it `/pickup <task-id>`, wait for it to settle, verify the "Resumed from
# handover" banner, and hand focus to it. Every Herdr mutation happens exactly
# once; nothing is retried. Outside Herdr, or with a prerequisite missing, it
# exits 3 and prints the reason so the caller falls back to the manual
# "To resume" path.
#
# Usage:
#   herdr-pickup.sh <task-id> --cwd <repo-root> [options]
#
# Options:
#   --cwd <dir>             working directory for the new pane (required)
#   --direction right|down  split direction (default: down = stacked, new pane below)
#   --name <agent-name>     live-agent name (default: pickup-<task-id>, de-duplicated)
#   --shell-timeout <s>     wait for the new pane's shell to reach its prompt (default: 30)
#   --start-timeout <ms>    wait for pi to become ready for input (default: 60000)
#   --wait-timeout <ms>     wait for the pickup to settle (default: 180000)
#   --no-switch-focus       leave focus in the calling pane
#   --dry-run               run the read-only gate, print the commands, mutate nothing
#   -h, --help              show this help
#
# Output: key=value lines on stdout. Always ends with status=running|skipped|
# failed|dry-run. Other keys: reason= detail= (skipped), step= (failed),
# herdr_version= caller_pane= task= agent= pane_id= shell_ready_after= wait=
# banner=seen|not-seen focus=switched|kept. Diagnostics and verbatim Herdr
# errors go to stderr.
#
# `agent start` is re-asked once per second only while Herdr answers
# agent_pane_busy (the fresh shell has not reached its prompt; nothing was
# started). Any other error stops the script.
#
# Exit codes: 0 pickup running (or dry-run ok) · 1 a Herdr step failed
# · 2 usage error · 3 skipped (gate failed; manual path applies)

set -u

TASK_ID=""
ROOT=""
DIRECTION="down"
NAME=""
SHELL_TIMEOUT=30
START_TIMEOUT=60000
WAIT_TIMEOUT=180000
SWITCH_FOCUS=1
DRY_RUN=0

usage() {
  sed -n '2,/^$/p' "$0" | sed -e 's/^# \{0,1\}//' -e '/^$/d'
}

die_usage() {
  printf 'status=failed\nstep=usage\n'
  printf 'herdr-pickup.sh: %s\n' "$1" >&2
  printf 'run with --help for usage\n' >&2
  exit 2
}

skip() {
  printf 'reason=%s\n' "$1"
  [ -n "${2:-}" ] && printf 'detail=%s\n' "$2"
  printf 'status=skipped\n'
  exit 3
}

warn() { printf 'herdr-pickup.sh: warning: %s\n' "$1" >&2; }

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --cwd)              [ $# -ge 2 ] || die_usage "--cwd needs a value";           ROOT="$2"; shift 2 ;;
    --direction)        [ $# -ge 2 ] || die_usage "--direction needs a value";     DIRECTION="$2"; shift 2 ;;
    --name)             [ $# -ge 2 ] || die_usage "--name needs a value";          NAME="$2"; shift 2 ;;
    --shell-timeout)    [ $# -ge 2 ] || die_usage "--shell-timeout needs a value"; SHELL_TIMEOUT="$2"; shift 2 ;;
    --start-timeout)    [ $# -ge 2 ] || die_usage "--start-timeout needs a value"; START_TIMEOUT="$2"; shift 2 ;;
    --wait-timeout)     [ $# -ge 2 ] || die_usage "--wait-timeout needs a value";  WAIT_TIMEOUT="$2"; shift 2 ;;
    --no-switch-focus)  SWITCH_FOCUS=0; shift ;;
    --dry-run)          DRY_RUN=1; shift ;;
    -h|--help)          usage; exit 0 ;;
    -*)                 die_usage "unknown option: $1" ;;
    *)
      if [ -z "$TASK_ID" ]; then TASK_ID="$1"; shift
      else die_usage "unexpected argument: $1"; fi ;;
  esac
done

[ -n "$TASK_ID" ] || die_usage "missing <task-id>"
TASK_ID="${TASK_ID#\#}"
TASK_ID="${TASK_ID#task:}"
case "$TASK_ID" in
  ''|*[!0-9]*) die_usage "task id must be numeric (got '$TASK_ID')" ;;
esac

[ -n "$ROOT" ] || die_usage "--cwd <repo-root> is required"
[ -d "$ROOT" ] || die_usage "--cwd '$ROOT' is not a directory"
ROOT=$(cd "$ROOT" && pwd -P)

case "$DIRECTION" in right|down) ;; *) die_usage "--direction must be right or down" ;; esac
case "$SHELL_TIMEOUT" in ''|*[!0-9]*) die_usage "--shell-timeout must be an integer (s)" ;; esac
case "$START_TIMEOUT" in ''|*[!0-9]*) die_usage "--start-timeout must be an integer (ms)" ;; esac
case "$WAIT_TIMEOUT"  in ''|*[!0-9]*) die_usage "--wait-timeout must be an integer (ms)" ;; esac

# ---------------------------------------------------------------------------
# Gate (read-only). Any failure => exit 3, the manual path applies.
# ---------------------------------------------------------------------------
[ "${HERDR_ENV:-}" = 1 ]        || skip not-inside-herdr "HERDR_ENV is not 1"
command -v herdr >/dev/null 2>&1 || skip herdr-cli-missing "no herdr binary on PATH"
command -v jq    >/dev/null 2>&1 || skip jq-missing "jq is required to parse Herdr responses"
command -v cortex >/dev/null 2>&1 || skip cortex-missing "nothing to pick up without cortex"

# Never run bare `herdr` (it launches the TUI). The bare command group prints
# help and exits non-zero, so capture first, then inspect.
KINDS=$(herdr agent 2>&1 | grep -E '^ *kinds:' | sed 's/^ *kinds: *//' | tr '|' '\n')
printf '%s\n' "$KINDS" | grep -qx 'pi' || skip pi-kind-unsupported "herdr agent does not list pi as a kind"

HERDR_VERSION=$(herdr --version 2>/dev/null | awk '{print $2}')
printf 'herdr_version=%s\n' "${HERDR_VERSION:-unknown}"
printf 'caller_pane=%s\n' "${HERDR_PANE_ID:-unknown}"
# Target the calling pane explicitly: `--current` can resolve to the UI-focused
# pane, which may belong to another workspace the user clicked into.
if [ -n "${HERDR_PANE_ID:-}" ]; then SPLIT_TARGET="--pane $HERDR_PANE_ID"; else SPLIT_TARGET="--current"; fi

# The task must exist; a wrong id is a usage error, not a Herdr failure.
TASK_JSON=$(cortex show "$TASK_ID" --json 2>&1) || die_usage "cortex show $TASK_ID failed: $TASK_JSON"
TASK_TITLE=$(printf '%s' "$TASK_JSON" | jq -r '.task.title // empty' 2>/dev/null)
[ -n "$TASK_TITLE" ] || die_usage "cortex task #$TASK_ID has no title in: $TASK_JSON"
printf 'task=#%s %s\n' "$TASK_ID" "$TASK_TITLE"
if ! printf '%s' "$TASK_JSON" | jq -e '.task.tags | any(. == "handover")' >/dev/null 2>&1; then
  warn "task #$TASK_ID is not tagged 'handover'; the receiving side will ask the user to confirm"
fi

# Live-agent name: [a-z][a-z0-9_-]{0,31}, unique among live agents.
[ -n "$NAME" ] || NAME="pickup-$TASK_ID"
case "$NAME" in
  [a-z]*) ;;
  *) die_usage "--name must start with a lowercase letter" ;;
esac
printf '%s' "$NAME" | grep -Eq '^[a-z][a-z0-9_-]{0,31}$' || die_usage "--name '$NAME' must match [a-z][a-z0-9_-]{0,31}"
BASE_NAME="$NAME"
n=2
while herdr agent get "$NAME" >/dev/null 2>&1; do
  NAME="$BASE_NAME-$n"
  n=$((n + 1))
  [ "$n" -le 9 ] || die_usage "could not find a free agent name after $BASE_NAME-8"
done
printf 'agent=%s\n' "$NAME"

if [ "$DRY_RUN" = 1 ]; then
  printf 'would_run=herdr pane split %s --direction %s --cwd %s --no-focus\n' "$SPLIT_TARGET" "$DIRECTION" "$ROOT"
  printf 'would_run=herdr agent start %s --kind pi --pane <new-pane-id> --timeout %s   (re-asked while agent_pane_busy, up to %ss)\n' "$NAME" "$START_TIMEOUT" "$SHELL_TIMEOUT"
  printf 'would_run=herdr agent prompt %s "/pickup %s" --wait --timeout %s\n' "$NAME" "$TASK_ID" "$WAIT_TIMEOUT"
  printf 'would_run=herdr agent read %s --source recent-unwrapped --lines 80\n' "$NAME"
  if [ "$SWITCH_FOCUS" = 1 ]; then
    printf 'would_run=herdr agent focus %s\n' "$NAME"
  else
    printf 'would_run=(focus kept: --no-switch-focus)\n'
  fi
  printf 'status=dry-run\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# Helpers for the mutating steps
# ---------------------------------------------------------------------------
ERR_FILE=$(mktemp -t herdr-pickup.XXXXXX)
trap 'rm -f "$ERR_FILE"' EXIT

OUT=""; RC=0; ERRTXT=""
run() {
  OUT=$("$@" 2>"$ERR_FILE"); RC=$?
  ERRTXT=$(cat "$ERR_FILE")
}

PANE_ID=""
diag() {
  # Read-only look at the new pane so the caller can see what pi is showing.
  [ -n "$PANE_ID" ] || return 0
  printf -- '--- %s: recent output of pane %s ---\n' "$1" "$PANE_ID" >&2
  herdr pane read "$PANE_ID" --source recent-unwrapped --lines 40 2>/dev/null | cut -c1-4000 >&2
  printf -- '--- end ---\n' >&2
}

fail() {
  # fail <step> <verbatim error>
  printf 'step=%s\n' "$1"
  [ -n "$PANE_ID" ] && printf 'pane_id=%s\n' "$PANE_ID"
  printf 'status=failed\n'
  printf 'herdr-pickup.sh: step %s failed. Herdr said:\n%s\n' "$1" "$2" >&2
  printf 'herdr-pickup.sh: nothing was retried; inspect the pane before doing anything else.\n' >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Split THIS pane (exactly once), without stealing focus.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2086  # SPLIT_TARGET is intentionally two words
run herdr pane split $SPLIT_TARGET --direction "$DIRECTION" --cwd "$ROOT" --no-focus
[ "$RC" -eq 0 ] || fail split "${ERRTXT}${OUT}"
PANE_ID=$(printf '%s' "$OUT" | jq -r '.result.pane.pane_id // empty' 2>/dev/null)
[ -n "$PANE_ID" ] || fail split "could not parse .result.pane.pane_id from: ${OUT}${ERRTXT}"
printf 'pane_id=%s\n' "$PANE_ID"

# ---------------------------------------------------------------------------
# 2. Start pi in the new pane. The fresh shell needs a moment to reach its
#    prompt; until then Herdr rejects the start with agent_pane_busy and starts
#    nothing, so keep asking Herdr (the authority on availability) once per
#    second up to --shell-timeout. Any other error stops immediately.
# ---------------------------------------------------------------------------
waited=0
while :; do
  run herdr agent start "$NAME" --kind pi --pane "$PANE_ID" --timeout "$START_TIMEOUT"
  [ "$RC" -eq 0 ] && break
  case "${ERRTXT}${OUT}" in
    *agent_pane_busy*)
      if [ "$waited" -ge "$SHELL_TIMEOUT" ]; then
        diag "agent start (shell not available after ${SHELL_TIMEOUT}s)"
        fail start "${ERRTXT}${OUT}"
      fi
      sleep 1
      waited=$((waited + 1)) ;;
    *)
      diag "agent start"
      fail start "${ERRTXT}${OUT}" ;;
  esac
done
printf 'shell_ready_after=%ss\n' "$waited"

# ---------------------------------------------------------------------------
# 3. Send /pickup and wait for the first settled state (idle/done/blocked).
#    A stall or timeout does NOT prove the prompt was not delivered: never resend.
# ---------------------------------------------------------------------------
run herdr agent prompt "$NAME" "/pickup $TASK_ID" --wait --timeout "$WAIT_TIMEOUT"
if [ "$RC" -eq 0 ]; then
  SETTLED=$(printf '%s' "$OUT" | jq -c '.result // .' 2>/dev/null | cut -c1-300)
  printf 'wait=settled %s\n' "${SETTLED:-$OUT}"
else
  COMBINED="${ERRTXT}${OUT}"
  case "$COMBINED" in
    *agent_prompt_stalled*)
      diag "agent prompt (stalled)"
      fail prompt "$COMBINED" ;;
    *timeout*)
      printf 'wait=timeout after %sms (pickup still working; not a failure)\n' "$WAIT_TIMEOUT" ;;
    *)
      diag "agent prompt"
      fail prompt "$COMBINED" ;;
  esac
fi

# ---------------------------------------------------------------------------
# 4. Verify with evidence: the receiving side's banner must be on screen.
# ---------------------------------------------------------------------------
run herdr agent read "$NAME" --source recent-unwrapped --lines 80
BANNER=not-seen
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'Resumed from handover'; then
  BANNER=seen
fi
printf 'banner=%s\n' "$BANNER"
[ "$BANNER" = seen ] || diag "verify (banner not seen)"

# ---------------------------------------------------------------------------
# 5. Hand focus to the new agent only when the pickup demonstrably resumed.
# ---------------------------------------------------------------------------
FOCUS=kept
if [ "$SWITCH_FOCUS" = 1 ] && [ "$BANNER" = seen ]; then
  run herdr agent focus "$NAME"
  if [ "$RC" -eq 0 ]; then FOCUS=switched; else warn "agent focus failed: ${ERRTXT}${OUT}"; fi
fi
printf 'focus=%s\n' "$FOCUS"
printf 'status=running\n'
exit 0
