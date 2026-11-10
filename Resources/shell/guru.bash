# TermGuru bash integration. Loaded by: eval "$(tgr init bash)"
[[ $- == *i* ]] || return 0
[[ -z $_guru_loaded ]] || return 0
# READLINE_LINE and coproc need bash 4; macOS system bash is 3.2.
(( BASH_VERSINFO[0] >= 4 )) || return 0
command -v tgr >/dev/null 2>&1 || return 0

_guru_loaded=1
_guru_us=$'\x1f'
_guru_rs=$'\x1e'
_guru_alias_file="$HOME/.config/term-guru/aliases.sh"
_guru_visible=0
_guru_last=
_guru_sent_aliases=
_guru_alias_mtime=0
_guru_in=
_guru_out=
declare -A _guru_orig

_guru_connect() {
  [[ -n $_guru_out ]] && kill -0 "$_guru_relay_pid" 2>/dev/null && return 0
  _guru_in= _guru_out=
  [[ -S "${GURU_SOCKET:-$HOME/Library/Application Support/TermGuru/run/guru.sock}" ]] || return 1
  { coproc _GURU_RELAY { tgr _relay; }; } 2>/dev/null || return 1
  _guru_relay_pid=$_GURU_RELAY_PID
  # Private descriptors survive later coprocs and keep job-control messages away from the prompt.
  exec {_guru_in}<&"${_GURU_RELAY[0]}" {_guru_out}>&"${_GURU_RELAY[1]}"
  disown "$_guru_relay_pid" 2>/dev/null
  _guru_sent_aliases=
  _guru_send "H${_guru_us}$$${_guru_us}bash${_guru_us}$(tty)${_guru_us}${PATH}"
}

_guru_send() {
  [[ -n $_guru_out ]] || return 1
  printf '%s\n' "$1" >&"$_guru_out" 2>/dev/null || { _guru_out=; return 1; }
}

_guru_apply() {
  local IFS=$_guru_us
  local -a f
  read -r -a f <<<"$1"
  case ${f[0]} in
    V) _guru_visible=${f[1]:-0} ;;
    I|R)
      local -i replace=${f[1]:-0} back=${f[3]:-0}
      local text=${f[2]}
      READLINE_LINE="${READLINE_LINE:0:READLINE_POINT-replace}${text}${READLINE_LINE:READLINE_POINT}"
      READLINE_POINT=$(( READLINE_POINT - replace + ${#text} - back ))
      ;;
  esac
}

# Runs after every key: reports the line and picks up the popup state.
_guru_hook() {
  local state="$READLINE_POINT$_guru_us$READLINE_LINE" line
  [[ $state == "$_guru_last" ]] && return 0
  _guru_last=$state
  _guru_send "E${_guru_us}${READLINE_POINT}${_guru_us}${PWD}${_guru_us}${READLINE_LINE//$'\n'/$_guru_rs}" || return 0
  if IFS= read -r -t 0.12 -u "$_guru_in" line; then
    _guru_apply "$line"
    while IFS= read -r -t 0.001 -u "$_guru_in" line; do _guru_apply "$line"; done
  fi
}

# First half of a key: decides whether the popup takes it, then points the second half
# at either nothing or the key's original action.
_guru_key() {
  local name=$1 line pass=1
  while IFS= read -r -t 0.001 -u "$_guru_in" line 2>/dev/null; do _guru_apply "$line"; done
  if (( _guru_visible )) && _guru_send "K${_guru_us}${name}"; then
    while IFS= read -r -t 0.3 -u "$_guru_in" line; do
      case $line in
        V*) _guru_apply "$line" ;;
        I*) _guru_apply "$line"; pass=0; break ;;
        R*) _guru_apply "$line"; break ;;
        # Esc dismisses and still enters movement mode.
        N*) [[ $name == esc ]] || pass=0; break ;;
        *) break ;;
      esac
    done
  fi
  local action='""' map
  (( pass )) && action=${_guru_orig[$name]}
  for map in emacs vi-insert; do
    bind -m "$map" "\"\C-x\C-_2${name}\": ${action}"
  done
}

_guru_bind_keymap() {
  local map=$1 code key name
  bind -m "$map" -x '"\C-x\C-_h": _guru_hook'
  for (( code = 32; code < 127; code++ )); do
    printf -v key '\\%03o' "$code"
    bind -m "$map" "\"\C-x\C-_s${key}\": self-insert"
    bind -m "$map" "\"${key}\": \"\C-x\C-_s${key}\C-x\C-_h\""
  done
  bind -m "$map" '"\C-x\C-_b": backward-delete-char'
  bind -m "$map" '"\C-?": "\C-x\C-_b\C-x\C-_h"'
  bind -m "$map" '"\C-h": "\C-x\C-_b\C-x\C-_h"'

  for name in tab enter up down esc; do
    bind -m "$map" -x "\"\C-x\C-_1${name}\": _guru_key ${name}"
  done
  bind -m "$map" '"\C-i": "\C-x\C-_1tab\C-x\C-_2tab\C-x\C-_h"'
  # No trailing hook after Enter: it would be typed into the next prompt.
  bind -m "$map" '"\C-m": "\C-x\C-_1enter\C-x\C-_2enter"'
  bind -m "$map" '"\e[A": "\C-x\C-_1up\C-x\C-_2up\C-x\C-_h"'
  bind -m "$map" '"\eOA": "\C-x\C-_1up\C-x\C-_2up\C-x\C-_h"'
  bind -m "$map" '"\e[B": "\C-x\C-_1down\C-x\C-_2down\C-x\C-_h"'
  bind -m "$map" '"\eOB": "\C-x\C-_1down\C-x\C-_2down\C-x\C-_h"'
}

_guru_bind() {
  _guru_orig=([tab]=complete [enter]=accept-line [up]=previous-history [down]=next-history [esc]=vi-movement-mode)
  _guru_bind_keymap emacs
  _guru_bind_keymap vi-insert
  # Only vi-insert: in emacs mode \e prefixes every arrow and Meta key, so binding it alone
  # would hold each Esc for readline's keyseq-timeout. No hook after it: movement mode has none.
  bind -m vi-insert '"\e": "\C-x\C-_1esc\C-x\C-_2esc"'
}

_guru_sync_aliases() {
  if [[ -r $_guru_alias_file ]]; then
    local mtime
    mtime=$(stat -f %m "$_guru_alias_file" 2>/dev/null)
    if [[ -n $mtime && $mtime != "$_guru_alias_mtime" ]]; then
      _guru_alias_mtime=$mtime
      source "$_guru_alias_file"
    fi
  fi
  [[ -n $_guru_out ]] || return 0
  local name dump=
  for name in "${!BASH_ALIASES[@]}"; do
    dump+="${_guru_us}${name}${_guru_us}${BASH_ALIASES[$name]}"
  done
  [[ $dump == "$_guru_sent_aliases" ]] && return 0
  _guru_sent_aliases=$dump
  _guru_send "A${dump//$'\n'/$_guru_rs}"
}

_guru_prompt() {
  local status=$?
  _guru_last=
  _guru_visible=0
  _guru_connect && _guru_send L
  _guru_sync_aliases
  return $status
}

_guru_bind
PROMPT_COMMAND="_guru_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
