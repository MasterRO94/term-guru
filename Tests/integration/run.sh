#!/bin/bash
# Drives real zsh/bash sessions in a pty against a private headless app instance.
set -uo pipefail
cd "$(dirname "$0")/../.."

swift build >/dev/null || exit 1
BIN="$(swift build --show-bin-path)"
export GURU_SOCKET="${TMPDIR:-/tmp/}guru-test-$$.sock" GURU_HEADLESS=1 GURU_RESOURCES="$PWD/Resources"
export PATH="$BIN:$PATH"

FIXTURE="$(mktemp -d)"
mkdir -p "$FIXTURE/app/Models" "$FIXTURE/docs"
git -C "$FIXTURE" init -q

export GURU_CONFIG="$FIXTURE/.config"
mkdir -p "$GURU_CONFIG"
APP=
trap 'kill $APP 2>/dev/null; rm -rf "$FIXTURE" "$GURU_SOCKET"' EXIT

start_app() {
  [ -z "$APP" ] || { kill $APP; wait $APP 2>/dev/null; rm -f "$GURU_SOCKET"; }
  echo "{\"enterAction\":\"$1\"}" > "$GURU_CONFIG/settings.json"
  "$BIN/GuruApp" &
  APP=$!
  sleep 2
}

FAILED=0
check() {
  local shell=$1 expected=$2; shift 2
  local actual
  actual="$(python3 -I Tests/integration/pty_drive.py "$shell" "$PWD/Resources/shell/guru.${shell##*/}" "$FIXTURE" "$@")"
  if [[ $actual == "[$expected]"* ]]; then
    echo "ok   ${shell##*/}: $expected"
  else
    echo "FAIL ${shell##*/}: expected [$expected], got $actual"
    FAILED=1
  fi
}

SHELLS=()
for shell in /bin/zsh /opt/homebrew/bin/bash /usr/local/bin/bash; do
  [ -x "$shell" ] && SHELLS+=("$shell")
done

start_app insert
for shell in "${SHELLS[@]}"; do
  check "$shell" "git checkout " 'git ch' '\t'
  check "$shell" "git commit " 'git ' '\x1b[B' '\x1b[B' '\r'
  check "$shell" "git commit --amend " 'git commit --ame' '\t'
  check "$shell" "cd app/Models/" 'cd ap' '\t' 'Mo' '\t'
  check "$shell" "git status" 'git stauts' '\x7f\x7f\x7f' 'tus'
  check "$shell" "git checkout " 'git ch' '\r'
  # Nothing left to complete, so Return runs the line and the next prompt starts empty.
  check "$shell" "" 'git status' '\r'
  check "$shell" "" 'git ' '\r'
done

start_app execute
for shell in "${SHELLS[@]}"; do
  # The picked command runs, so the next prompt starts empty.
  check "$shell" "" 'git ' '\x1b[B' '\x1b[B' '\r'
  check "$shell" "git checkout " 'git ch' '\t'
done
exit $FAILED
