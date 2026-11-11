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
  # A plugin or paste sends the line and Return at once: late suggestions for it must not open the popup while it runs.
  GURU_PASTE=1 check "$shell" "hidden" "sleep 1; echo \"[\$(tgr status | awk '/^popup/{print \$2}')]\"; git status\r"
  check "$shell" "git checkout " 'git ch' '\r'
  # Nothing left to complete, so Return runs the line and the next prompt starts empty.
  check "$shell" "" 'git status' '\r'
  check "$shell" "" 'git ' '\r'
  # Redirect targets list files, whatever the command's spec says.
  check "$shell" "echo hi > app/" 'echo hi > ap' '\t'
  check "$shell" "git status >docs/" 'git status >do' '\t'
  # cd lists parent levels; the top entry for ../.. is the next level up.
  check "$shell" "cd ../../" 'cd ../..' '\t'
  # With nothing to suggest, Tab runs the shell's own completion (here: a shell variable; bash adds a space).
  space=; [[ $shell == *bash ]] && space=' '
  GURU_PRE='TGRFALLBACK=1' check "$shell" "echo \$TGRFALLBACK$space" 'echo $TGRFALL' '\t'
  # Alt-b still moves back a word while and after the popup shows.
  check "$shell" "git Xch" 'git ch' '\x1bb' 'X'
  # vi mode: Esc dismisses and enters command mode in one press; then 0 goes to column 0.
  GURU_VI=1 check "$shell" "Xgit ch" 'git ch' '\x1b' '0iX'
  # vi mode: after Esc the popup stays hidden, so Return runs the line.
  GURU_VI=1 check "$shell" "" 'git ch' '\x1b' 'A' '\r'
  GURU_VI=1 check "$shell" "git checkout " 'git ch' '\t'
done

ZSH=/bin/zsh
if [ -x "$ZSH" ]; then
  check "$ZSH" "git Xch" 'git ch' '\x1b' '\x1bb' 'X'
  # Ctrl-G types KEYTIMEOUT into the line while the popup shows: shortened only from the default.
  KT='_kt() { LBUFFER+=$KEYTIMEOUT }; zle -N _kt; bindkey "^G" _kt'
  GURU_PRE="$KT" check "$ZSH" "git ch10" 'git ch' '\x07'
  GURU_PRE="KEYTIMEOUT=25; $KT" check "$ZSH" "git ch25" 'git ch' '\x07'
  GURU_PRE='KEYTIMEOUT=25' GURU_SHOW='$KEYTIMEOUT' check "$ZSH" "25" 'git ch' '\x1b'
  GURU_SHOW='$KEYTIMEOUT' check "$ZSH" "40" 'git ch' '\x1b'
fi

start_app execute
for shell in "${SHELLS[@]}"; do
  # The picked command runs, so the next prompt starts empty.
  check "$shell" "" 'git ' '\x1b[B' '\x1b[B' '\r'
  check "$shell" "git checkout " 'git ch' '\t'
done
exit $FAILED
