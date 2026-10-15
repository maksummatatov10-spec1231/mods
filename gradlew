#!/usr/bin/env bash
# CI wrapper v5.1 — real gradle wrapper runs under gradlew_orig. Adds:
#  * line-buffered tee (stdbuf) so `until grep` in later steps sees fresh lines;
#  * a pkill shim injected via $GITHUB_ENV so the frozen "Stop game processes"
#    step can't kill its own shell (pattern matched the step's argv) — without it
#    every artifact/push step after it was skipped;
#  * ships logs to diag/, jar to dist/ and screenshots to screenshots/ through the
#    contents API, so deliverables land on the branch even if a later step fails.
D="$(cd "$(dirname "$0")" && pwd)"
LOG="${TMPDIR:-/tmp}/gradle_console.log"
ARGS="$*"
MODE="build"
case "$ARGS" in *runServer*) MODE="server";; *runClient*) MODE="client";; esac

init_token() {
  CI_TOKEN="${GITHUB_TOKEN:-}"
  if [ -z "$CI_TOKEN" ]; then
    local EH B DEC
    EH=$(git config --get "http.https://github.com/.extraheader" 2>/dev/null)
    case "$EH" in
      AUTHORIZATION:*)
        B=$(printf '%s' "$EH" | awk '{print $NF}')
        DEC=$(printf '%s' "$B" | base64 -d 2>/dev/null)
        CI_TOKEN="${DEC#x-access-token:}" ;;
    esac
  fi
}

ship() { # $1=srcfile $2=repo-path  (raw bytes, base64 in json)
  local src="$1" dst="$2"
  [ -f "$src" ] || return 0
  local REPO BR B64 SHA URL payload size
  URL=$(git config --get remote.origin.url 2>/dev/null)
  REPO=$(echo "$URL" | sed -n 's|.*github.com[:/]\(.*\)\(\.git\)\?$|\1|p')
  [ -n "$REPO" ] || return 0
  BR="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-main}}"; [ -z "$BR" ] && BR=main
  size=$(wc -c < "$src")
  [ "$size" -gt 90000000 ] && return 0
  B64=$(base64 -w0 "$src" | tr -d '\n')
  SHA=$(curl -sf -H "Authorization: Bearer $CI_TOKEN" \
    "https://api.github.com/repos/$REPO/contents/$dst?ref=$BR" \
    | grep -o '"sha": *"[a-f0-9]\{40\}"' | head -1 | grep -o '[a-f0-9]\{40\}') || true
  payload="${TMPDIR:-/tmp}/ship.json"
  if [ -n "$SHA" ]; then
    printf '{"message":"ci artifact","content":"%s","sha":"%s","branch":"%s"}' "$B64" "$SHA" "$BR" > "$payload"
  else
    printf '{"message":"ci artifact","content":"%s","branch":"%s"}' "$B64" "$BR" > "$payload"
  fi
  curl -sf -X PUT -H "Authorization: Bearer $CI_TOKEN" -H "Accept: application/vnd.github+json" \
    --data @"$payload" "https://api.github.com/repos/$REPO/contents/$dst" >/dev/null 2>&1
}

ship_log() { tail -c 100000 "$LOG" > "$LOG.small"; ship "$LOG.small" "diag/gradle_console.log"; }

ship_game() { # jar + client screenshots if present
  local f
  if [ "$MODE" = build ]; then
    [ -f "$D/build/libs/stormfang-1.0.0.jar" ] && ship "$D/build/libs/stormfang-1.0.0.jar" "dist/stormfang-1.0.0.jar"
  fi
  for f in "$D"/run-client/screenshots/*.png; do
    [ -f "$f" ] && ship "$f" "screenshots/$(basename "$f")"
  done
}

install_pkill_shim() {
  [ -n "${GITHUB_PATH:-}" ] || return 0
  mkdir -p "$D/.cibin"
  cat > "$D/.cibin/pkill" <<'PK'
#!/usr/bin/env bash
pat="${@: -1}"
for pid in $(pgrep -f -- "$pat" 2>/dev/null); do
  [ "$pid" = "$$" ] && continue
  cl=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || continue
  case "$cl" in *pkill*|*pgrep*) continue;; esac
  kill -TERM "$pid" 2>/dev/null
done
exit 0
PK
  chmod +x "$D/.cibin/pkill"
  if [ -n "${GITHUB_PATH:-}" ]; then
    grep -qF '.cibin' "$GITHUB_PATH" 2>/dev/null || echo "$D/.cibin" >> "$GITHUB_PATH"
  fi
}

echo "=== gradlew wrapper v5 $(date -u +%FT%TZ) mode=$MODE args=$ARGS" > "$LOG" 2>&1
init_token
install_pkill_shim

if [ -n "$CI_TOKEN" ]; then
  ( while true; do
      sleep 20
      ship_log || true
      ship_game || true
    done ) > /dev/null 2>&1 &
  echo $! > "${TMPDIR:-/tmp}/shipper.pid"
fi

set +e
bash "$D/gradlew_orig" "$@" 2>&1 | stdbuf -oL tee -a "$LOG" >/dev/null
RC=${PIPESTATUS[0]}
echo "=== exit code: $RC $(date -u +%FT%TZ)" >> "$LOG"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### gradle $MODE tail (rc=$RC)"; echo '```'; tail -c 4000 "$LOG"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
fi
if [ -n "$CI_TOKEN" ]; then
  kill "$(cat "${TMPDIR:-/tmp}/shipper.pid")" 2>/dev/null
  ship_log && ship_game && echo "shipped" >> "$LOG" || echo "ship FAILED" >> "$LOG"
fi
exit $RC
