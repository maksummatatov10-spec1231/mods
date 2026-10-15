#!/usr/bin/env bash
# Wrapper: run the real gradle wrapper, capture ALL output, and on CI push the
# console log tail into diag/gradle_console.log so failures are debuggable without
# access to GitHub log storage.
D="$(cd "$(dirname "$0")" && pwd)"
LOG="${TMPDIR:-/tmp}/gradle_console.log"
: > "$LOG"
set +e
bash "$D/gradlew_orig" "$@" 2>&1 | cat | tee "$LOG" >/dev/null
RC=${PIPESTATUS[0]}
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPOSITORY" ]; then
  B64=$(tail -c 110000 "$LOG" | base64 -w0)
  BR="${GITHUB_REF_NAME:-main}"
  SHA=$(curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/contents/diag/gradle_console.log?ref=$BR" \
    | grep -o '"sha": *"[a-f0-9]\{40\}"' | head -1 | grep -o '[a-f0-9]\{40\}') || true
  if [ -n "$SHA" ]; then
    JSON="{\"message\":\"diag log\",\"content\":\"$B64\",\"sha\":\"$SHA\",\"branch\":\"$BR\"}"
  else
    JSON="{\"message\":\"diag log\",\"content\":\"$B64\",\"branch\":\"$BR\"}"
  fi
  curl -sf -X PUT -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "$JSON" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/contents/diag/gradle_console.log" >/dev/null || echo "diag push failed"
fi
exit $RC
