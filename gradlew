#!/usr/bin/env bash
# CI wrapper v13 — real gradle wrapper runs under gradlew_orig. Adds:
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
  [ -f "${TMPDIR:-/tmp}/sf_helper.log" ] && ship "${TMPDIR:-/tmp}/sf_helper.log" "diag/sf_helper.log"
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
for a in "$@"; do
  case "$a" in push) IS_PUSH=1;; HEAD:*) [ -z "$BR" ] && BR="${a#HEAD:}";; esac
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

if [ "$MODE" = server ]; then
  HELPER="${TMPDIR:-/tmp}/sf_helper.sh"
  # URL/REPO/BR resolved here and baked into the helper so it can ship artifacts even
  # after this wrapper is killed by the Stop step.
  HURL=$(git config --get remote.origin.url 2>/dev/null)
  HREPO=$(echo "$HURL" | sed -n 's|.*github.com[:/]\(.*\)\(\.git\)\?$||p')
  HBR="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-main}}"; [ -z "$HBR" ] && HBR=main
  cat > "$HELPER" <<'SFHEOF'
#!/bin/bash
trap '' TERM INT HUP
D="$1"; HREPO="$2"; HBR="$3"; CI_TOKEN="$4"
LOGF=/tmp/sf_helper.log
say(){ echo "[$(date -u +%T)] $*" >> "$LOGF"; }
hship(){ # src dst
  local src="$1" dst="$2"
  [ -f "$src" ] || return 0
  local B64 SHA payload=/tmp/.hship.json
  B64=$(base64 -w0 "$src" | tr -d '\n')
  SHA=$(curl -sf -H "Authorization: Bearer $CI_TOKEN" "https://api.github.com/repos/$HREPO/contents/$dst?ref=$HBR" | grep -o '"sha": *"[a-f0-9]\{40\}"' | head -1 | grep -o '[a-f0-9]\{40\}') || true
  if [ -n "$SHA" ]; then printf '{"message":"ci artifact","content":"%s","sha":"%s","branch":"%s"}' "$B64" "$SHA" "$HBR" > "$payload"
  else printf '{"message":"ci artifact","content":"%s","branch":"%s"}' "$B64" "$HBR" > "$payload"; fi
  curl -sf -X PUT -H "Authorization: Bearer $CI_TOKEN" -H "Accept: application/vnd.github+json" --data @"$payload" "https://api.github.com/repos/$HREPO/contents/$dst" >/dev/null 2>>"$LOGF"
}
say "helper started D=$D repo=$HREPO br=$HBR token=${CI_TOKEN:+yes}"
hship "$LOGF" "diag/sf_helper.log" && say "first log shipped" || say "first log ship FAILED"
# start project copy FIRST (loom config/remap overlaps with server boot)
P=/tmp/proj-c
rm -rf "$P"; cp -a "$D" "$P" >>"$LOGF" 2>&1
mkdir -p "$P/run-client"
if ! pgrep -x Xvfb >/dev/null 2>&1; then ( Xvfb :99 -ac -screen 0 1600x900x24 >/dev/null 2>&1 & ); fi
i=0; until [ -S /tmp/.X11-unix/X99 ] || [ "$i" -ge 30 ]; do sleep 0.5; i=$((i+1)); done
say "X ready (waited ${i} half-seconds)"
command -v xdotool >/dev/null 2>&1 || sudo apt-get install -y -qq xdotool >>"$LOGF" 2>&1 || true
export DISPLAY=:99
hship "$LOGF" "diag/sf_helper.log"
# background shipper for client-side artifacts
( while :; do
    sleep 15
    for f in "$P"/run-client/screenshots/*.png; do
      [ -f "$f" ] && hship "$f" "screenshots/$(basename "$f")"
    done
    [ -f "$D/client.log" ] && tail -c 100000 "$D/client.log" > /tmp/client.tail && hship /tmp/client.tail "ci-logs/client.log"
    hship "$LOGF" "diag/sf_helper.log"
  done ) >/dev/null 2>&1 &
until grep -q "Done (" "$D/server_smoke.log" 2>/dev/null; do sleep 3; done
say "server up, launching client"
ps -ef 2>/dev/null | grep -m1 "Knot" | grep -oE "\-Dstormfang[.A-Za-z0-9=]*" >> "$LOGF" 2>&1 || true
sleep 2
( cd "$P" && bash gradlew_orig runClient --no-daemon -Pdevtest >> "$D/client.log" 2>&1 ) &
say "client gradle bg started"
say "no key spam (harness dismisses screens itself)"
for ph in 1 2 3; do :; done
while :; do
  sleep 3
  [ -f "$D/client.log" ] || continue
  for ph in 1 2 3; do
    F=/tmp/.shot$ph.done
    grep -q "SHOT_REQUESTED $ph" "$D/client.log" 2>/dev/null || continue
    [ -f "$F" ] && continue
    : > "$F"
    sleep 2
    W=$(xdotool search --name "Minecraft" 2>/dev/null | tail -1)
    if [ -n "$W" ]; then xdotool windowactivate --sync "$W" key F2 2>/dev/null || xdotool key F2 2>/dev/null; else xdotool key F2 2>/dev/null; fi
    say "photo $ph taken"
    sleep 3
    mkdir -p "$D/run-client/screenshots"
    cp "$P"/run-client/screenshots/*.png "$D/run-client/screenshots/" 2>/dev/null
    for g in "$P"/run-client/screenshots/*.png; do [ -f "$g" ] && hship "$g" "screenshots/$(basename "$g")" && say "shipped $(basename "$g")"; done
  done
done
SFHEOF
  setsid bash "$HELPER" "$D" "$HREPO" "$HBR" "$CI_TOKEN" >> /tmp/sf_helper.log 2>&1 < /dev/null &
  echo "helper launched" >> "$LOG"
fi

if [ -n "$CI_TOKEN" ]; then
  ( while true; do
      sleep 20
      ship_log || true
      ship_game || true
    done ) > /dev/null 2>&1 &
  echo $! > "${TMPDIR:-/tmp}/shipper.pid"
fi

set +e
if [ "$MODE" = server ]; then
  bash "$D/gradlew_orig" "$@" -Pdevtest 2>&1 | stdbuf -oL tee -a "$LOG"
else
  bash "$D/gradlew_orig" "$@" 2>&1 | stdbuf -oL tee -a "$LOG"
fi
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
