#!/bin/bash
# Page Kalindu through PagerDuty (Events API v2, his personal schedule).
# Usage:
#   page.sh trigger <dedup-key> "<one-line summary>" [--force]
#   page.sh acknowledge <dedup-key>
#   page.sh resolve <dedup-key>
# --force bypasses the 15-minute trigger limit for a different, new incident only.
# The routing key is read from $PAGER_ENV (default ~/.config/kalindu-pager/pagerduty.env)
# and is never printed. KALINDU_PAGER_LOG overrides page.log beside it;
# KALINDU_PAGER_URL overrides the PagerDuty Events API endpoint for isolated tests.
set -euo pipefail
ENV_FILE=${PAGER_ENV:-${HOME}/.config/kalindu-pager/pagerduty.env}
LOG=${KALINDU_PAGER_LOG:-$(dirname "${ENV_FILE}")/page.log}
URL=${KALINDU_PAGER_URL:-https://events.pagerduty.com/v2/enqueue}
FORCE=false
ARGS=()
for ARG in "$@"; do
  case "${ARG}" in
    --force) FORCE=true ;;
    *) ARGS+=("${ARG}") ;;
  esac
done
if [[ "${#ARGS[@]}" -gt 0 ]]; then
  set -- "${ARGS[@]}"
else
  set --
fi
[[ -r "${ENV_FILE}" ]] || { echo "page.sh: no key file at ${ENV_FILE}; see the page-kalindu skill's Setup section" >&2; exit 2; }
ACTION=${1:?usage: page.sh trigger|acknowledge|resolve <dedup-key> [summary]}
KEY=${2:?dedup key required}
SUMMARY=${3:-}
case "${ACTION}" in
  trigger) [[ -n "${SUMMARY}" ]] || { echo "page.sh: a trigger needs a one-line summary" >&2; exit 2; } ;;
  acknowledge|resolve) ;;
  *) echo "page.sh: action must be trigger, acknowledge or resolve" >&2; exit 2 ;;
esac
if [[ "${ACTION}" = trigger ]] && [[ "${FORCE}" = false ]] && [[ -f "${LOG}" ]]; then
  /usr/bin/ruby -rtime -e '
    last = nil
    File.foreach(ARGV[0]) do |line|
      time, _, action = line.split(" ", 4)
      last = Time.iso8601(time) if action == "trigger"
    end
    if last && Time.now - last < 15 * 60
      warn "page.sh: trigger refused: the last trigger was less than 15 minutes ago; use --force only for a different, new incident"
      exit 3
    end' "${LOG}"
fi
set -a
# shellcheck source=/dev/null
. "${ENV_FILE}"
set +a
[[ -n "${PAGERDUTY_ROUTING_KEY:-}" ]] || { echo "page.sh: PAGERDUTY_ROUTING_KEY is empty in ${ENV_FILE}" >&2; exit 2; }
SOURCE="bb thread ${BB_THREAD_ID:-unknown} on $(hostname -s)"
BODY=$(/usr/bin/ruby -rjson -e '
  a, k, s, src = ARGV
  b = {routing_key: ENV["PAGERDUTY_ROUTING_KEY"], event_action: a, dedup_key: k}
  b[:payload] = {summary: s[0, 1000], source: src, severity: "critical", custom_details: {thread: ENV["BB_THREAD_ID"]}} if a == "trigger"
  puts JSON.generate(b)' "${ACTION}" "${KEY}" "${SUMMARY}" "${SOURCE}")
CURL_EXIT=0
RESP=$(curl -sS -m 20 -w '\n%{http_code}' -X POST "${URL}" -H 'Content-Type: application/json' --data-binary @- <<<"${BODY}") || CURL_EXIT=$?
HTTP_STATUS=${RESP##*$'\n'}
RESP=${RESP%$'\n'*}
RESPONSE_EXIT=0
echo "${RESP}" | /usr/bin/ruby -rjson -e '
  r = (JSON.parse(STDIN.read) rescue {"error" => "unparseable response"})
  puts JSON.generate(r.reject { |k, _| k == "routing_key" })
  exit(r["status"] == "success" ? 0 : 1)' || RESPONSE_EXIT=$?
umask 077
if [[ "${CURL_EXIT}" -ne 0 ]] || [[ "${HTTP_STATUS}" != 2?? ]] || [[ "${RESPONSE_EXIT}" -ne 0 ]]; then
  printf '%s %s %s-failed %s %s curl_exit=%s http_status=%s\n' "$(date -u +%FT%TZ)" "${BB_THREAD_ID:-unknown}" "${ACTION}" "${KEY}" "${SUMMARY}" "${CURL_EXIT}" "${HTTP_STATUS}" >> "${LOG}"
  echo "page.sh: ${ACTION} failed (curl exit ${CURL_EXIT}, HTTP ${HTTP_STATUS})" >&2
  [[ "${CURL_EXIT}" -eq 0 ]] || exit "${CURL_EXIT}"
  exit 1
fi
printf '%s %s %s %s %s\n' "$(date -u +%FT%TZ)" "${BB_THREAD_ID:-unknown}" "${ACTION}" "${KEY}" "${SUMMARY}" >> "${LOG}"
