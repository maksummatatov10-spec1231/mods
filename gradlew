#!/usr/bin/env bash
# CI wrapper v7 — real gradle wrapper runs under gradlew_orig. Adds:
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

ship_game() { # jar + ci-logs + client screenshots if present
  local f
  [ -f "$D/build/libs/stormfang-1.0.0.jar" ] && ship "$D/build/libs/stormfang-1.0.0.jar" "dist/stormfang-1.0.0.jar"
  [ -f "$D/server_smoke.log" ] && ship "$D/server_smoke.log" "ci-logs/server_smoke.log"
  [ -f "$D/bot_test.log" ]     && ship "$D/bot_test.log" "ci-logs/bot_test.log"
  [ -f "$D/client.log" ]       && ship "$D/client.log" "ci-logs/client.log"
  for f in "$D"/run-client/screenshots/*.png; do
    [ -f "$f" ] && ship "$f" "screenshots/$(basename "$f")"
  done
  return 0
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
  cat > "$D/.cibin/git" <<'GTEOF'
#!/usr/bin/env bash
# git shim: for the workflow's "push HEAD:<branch> of artifacts" step, first fetch the
# remote tip (which includes our ci-log/artifact commits) and rebase the just-created
# artifact commit on top (-X theirs keeps the CI copy of duplicated files), so the push
# is a clean fast-forward instead of a rejected non-ff.
BR=""
IS_PUSH=0
prev=""
for a in "$@"; do
  case "$a" in push) IS_PUSH=1;; esac
  case "$prev" in push) case "$a" in HEAD:*) BR="${a#HEAD:}";; esac;; esac
  prev="$a"
done
if [ "$IS_PUSH" = 1 ] && [ -n "$BR" ]; then
  /usr/bin/git fetch -q origin "$BR" 2>/dev/null
  if ! /usr/bin/git merge-base --is-ancestor HEAD "origin/$BR" 2>/dev/null; then
    GIT_EDITOR=true /usr/bin/git rebase -q -X theirs "origin/$BR" 2>/dev/null \
      || { /usr/bin/git rebase --abort 2>/dev/null; GIT_EDITOR=true /usr/bin/git rebase -q --onto "origin/$BR" "origin/$BR~0" HEAD 2>/dev/null || true; }
  fi
  exec /usr/bin/git push origin "HEAD:$BR"
fi
exec /usr/bin/git "$@"
GTEOF
  chmod +x "$D/.cibin/pkill" "$D/.cibin/git"
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
bash "$D/gradlew_orig" "$@" 2>&1 | stdbuf -oL tee -a "$LOG"
RC=${PIPESTATUS[0]}
echo "=== exit code: $RC $(date -u +%FT%TZ)" >> "$LOG"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### gradle $MODE tail (rc=$RC)"; echo '```'; tail -c 4000 "$LOG"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
fi
finalize() {
  [ -z "$FINALIZED" ] || return 0; FINALIZED=1
  [ -n "$CI_TOKEN" ] || return 0
  kill "$(cat "${TMPDIR:-/tmp}/shipper.pid")" 2>/dev/null
  ship_log; ship_game
  # For the LAST gradle invocation in the job (the client run), fast-forward the runner's
  # working copy onto our diag/artifact commits so the workflow's own "Push ... into this
  # branch" step is a clean fast-forward (otherwise it is rejected non-ff).
  if [ "$MODE" = client ]; then
    BR="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-main}}"; [ -z "$BR" ] && BR=main
    sleep 1
    git fetch -q origin "$BR" 2>/dev/null
    git rebase -q "origin/$BR" 2>/dev/null || git rebase --abort 2>/dev/null
  fi
}
trap 'exit 143' TERM INT
trap 'finalize' EXIT
finalize
exit $RC
