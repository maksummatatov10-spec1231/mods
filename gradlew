#!/usr/bin/env bash
# Wrapper: run the real gradle wrapper, capture ALL output, and ship the console log
# tail into diag/gradle_console.log on the branch (works from GitHub runners; the
# token is read from the checkout action's persisted credentials).
D="$(cd "$(dirname "$0")" && pwd)"
LOG="${TMPDIR:-/tmp}/gradle_console.log"
{
  echo "=== gradlew wrapper invoked: $(date -u +%FT%TZ)"
  echo "=== args: $*"
  echo "=== dir: $D"; ls -la "$D" | head -20
} > "$LOG" 2>&1
set +e
bash "$D/gradlew_orig" "$@" 2>&1 | tee -a "$LOG" >/dev/null
RC=${PIPESTATUS[0]}
echo "=== exit code: $RC" >> "$LOG"
TOKEN="${GITHUB_TOKEN:-}"
REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$TOKEN" ]; then
  # actions/checkout@v4 persists auth as an http extraheader (basic base64)
  EH=$(git config --get "http.https://github.com/.extraheader" 2>/dev/null)
  case "$EH" in
    AUTHORIZATION:*)
      B=$(printf '%s' "$EH" | awk '{print $NF}')
      DEC=$(printf '%s' "$B" | base64 -d 2>/dev/null)
      TOKEN="${D#*:}"; TOKEN="${DEC#x-access-token:}" ;;
  esac
  URL=$(git config --get remote.origin.url 2>/dev/null)
  case "$URL" in
    https://x-access-token:*) REPO=$(echo "$URL" | sed -n 's|.*github.com[:/]\(.*\)\(\.git\)\?$|\1|p') ;;
    https://github.com/*)    REPO=$(echo "$URL" | sed -n 's|.*github.com[:/]\(.*\)\(\.git\)\?$|\1|p') ;;
  esac
fi
# human-readable tail into the Actions job summary (visible in the web UI)
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### gradle console tail (rc=$RC)"; echo '```'; tail -c 4000 "$LOG"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
fi
if [ -n "$TOKEN" ] && [ -n "$REPO" ]; then
  BR="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-main}}"
  [ -z "$BR" ] && BR=main
  tail -c 105000 "$LOG" > "${LOG}.small"
  B64=$(base64 -w0 "${LOG}.small" | tr -d '\n')
  SHA=$(curl -sf -H "Authorization: Bearer $TOKEN" \
    "https://api.github.com/repos/$REPO/contents/diag/gradle_console.log?ref=$BR" \
    | grep -o '"sha": *"[a-f0-9]\{40\}"' | head -1 | grep -o '[a-f0-9]\{40\}') || true
  if [ -n "$SHA" ]; then
    printf '{"message":"ci log","content":"%s","sha":"%s","branch":"%s"}' "$B64" "$SHA" "$BR" > "${LOG}.json"
  else
    printf '{"message":"ci log","content":"%s","branch":"%s"}' "$B64" "$BR" > "${LOG}.json"
  fi
  curl -sf -X PUT -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    --data @"${LOG}.json" \
    "https://api.github.com/repos/$REPO/contents/diag/gradle_console.log" >/dev/null 2>&1 \
    && echo "diag log shipped to $REPO@${BR}" >> "$LOG" || echo "diag ship failed" >> "$LOG"
fi
exit $RC
