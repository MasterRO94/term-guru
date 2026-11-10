# TermGuru zsh integration. Loaded by: eval "$(tgr init zsh)"
[[ -o interactive ]] || return 0
[[ -n $_guru_loaded ]] && return 0
zmodload zsh/net/socket zsh/datetime zsh/parameter 2>/dev/null || return 0
zmodload -F zsh/stat b:zstat 2>/dev/null
autoload -Uz add-zsh-hook add-zle-hook-widget

typeset -g _guru_loaded=1
typeset -g _guru_sock="${GURU_SOCKET:-$HOME/Library/Application Support/TermGuru/run/guru.sock}"
typeset -g _guru_alias_file="$HOME/.config/term-guru/aliases.sh"
typeset -g _guru_us=$'\x1f' _guru_rs=$'\x1e'
typeset -g _guru_fd= _guru_visible=0 _guru_last= _guru_sent_aliases= _guru_alias_mtime=0
typeset -gi _guru_retry=0
typeset -gA _guru_orig

_guru_close() {
  [[ -n $_guru_fd ]] || return 0
  zle -F $_guru_fd 2>/dev/null
  exec {_guru_fd}>&-
  _guru_fd=
  _guru_set_visible 0
}

_guru_send() {
  [[ -n $_guru_fd ]] || return 1
  print -r -u $_guru_fd -- "$1" 2>/dev/null || { _guru_close; return 1 }
}

_guru_connect() {
  [[ -n $_guru_fd ]] && return 0
  (( EPOCHSECONDS < _guru_retry )) && return 1
  if [[ ! -S $_guru_sock ]] || ! zsocket $_guru_sock 2>/dev/null; then
    _guru_retry=$(( EPOCHSECONDS + 3 ))
    return 1
  fi
  _guru_fd=$REPLY
  zle -F -w $_guru_fd _guru_recv
  _guru_sent_aliases=
  _guru_send "H${_guru_us}$$${_guru_us}zsh${_guru_us}${TTY}${_guru_us}${PATH}"
}

# Escape is bound only while the popup shows, so it keeps its normal meaning otherwise.
# In vi mode it is vi-cmd-mode, which _guru_key_esc still runs after dismissing.
_guru_set_visible() {
  (( $1 == _guru_visible )) && return 0
  _guru_visible=$1
  if (( _guru_visible )); then
    local current=${$(bindkey -M main '^[')[2]}
    if [[ $current != _guru_key_esc ]]; then
      _guru_orig[esc]=$current
      bindkey -M main '^[' _guru_key_esc
    fi
    # The default 400 ms makes Esc feel stuck; a value the user picked is theirs.
    if [[ $KEYTIMEOUT == 40 ]]; then
      _guru_orig[keytimeout]=$KEYTIMEOUT
      KEYTIMEOUT=10
    fi
  else
    if [[ -n $_guru_orig[esc] ]]; then
      if [[ $_guru_orig[esc] == undefined-key ]]; then
        bindkey -M main -r '^['
      else
        bindkey -M main '^[' $_guru_orig[esc]
      fi
      _guru_orig[esc]=
    fi
    if [[ -n $_guru_orig[keytimeout] ]]; then
      KEYTIMEOUT=$_guru_orig[keytimeout]
      _guru_orig[keytimeout]=
    fi
  fi
}

_guru_insert() {
  local -i replace=$1 back=$3
  (( replace > 0 )) && LBUFFER=${LBUFFER[1,$(( ${#LBUFFER} - replace ))]}
  LBUFFER+=$2
  (( back > 0 )) && CURSOR=$(( CURSOR - back ))
  return 0
}

_guru_apply() {
  local -a f
  f=("${(@ps:\x1f:)1}")
  case $f[1] in
    V) _guru_set_visible $f[2] ;;
    I|R) _guru_insert "$f[2]" "${f[3]//$_guru_rs/$'\n'}" "$f[4]"; zle -R ;;
  esac
}

_guru_recv() {
  local line
  if [[ -n $2 ]] || ! IFS= read -r -u $1 line; then
    _guru_close
    return
  fi
  _guru_apply "$line"
}

_guru_redraw() {
  [[ $KEYMAP == vicmd ]] && return 0
  _guru_connect || return 0
  (( PENDING )) && return 0
  local state="$CURSOR$_guru_us$BUFFER"
  [[ $state == "$_guru_last" ]] && return 0
  _guru_last=$state
  _guru_send "E${_guru_us}${CURSOR}${_guru_us}${PWD}${_guru_us}${BUFFER//$'\n'/$_guru_rs}"
}

# Command mode has no popup; leaving it by our own Esc already hid it.
_guru_keymap_select() {
  [[ $KEYMAP == vicmd ]] && (( _guru_visible )) || return 0
  _guru_set_visible 0
  _guru_send X
  return 0
}

_guru_line_init() {
  _guru_last=
  _guru_set_visible 0
  _guru_connect && _guru_send L
  return 0
}

_guru_key() {
  local name=$1 orig=$_guru_orig[$1] line
  if (( _guru_visible )) && _guru_send "K${_guru_us}${name}"; then
    while IFS= read -r -t 0.3 -u $_guru_fd line; do
      case $line in
        V*) _guru_apply "$line" ;;
        I*) _guru_apply "$line"; return 0 ;;
        R*) _guru_apply "$line"; break ;;
        N*) [[ $name == esc && $orig != undefined-key ]] && zle $orig; return 0 ;;
        *) break ;;
      esac
    done
  fi
  [[ -n $orig && $orig != undefined-key ]] && zle $orig
}

_guru_key_up() { _guru_key up }
_guru_key_down() { _guru_key down }
_guru_key_tab() { _guru_key tab }
_guru_key_enter() { _guru_key enter }
_guru_key_esc() { _guru_key esc }
zle -N _guru_key_up
zle -N _guru_key_down
zle -N _guru_key_tab
zle -N _guru_key_enter
zle -N _guru_key_esc
zle -N _guru_recv

# Re-wrap on every prompt: plugins loaded later (fzf-tab, autosuggestions) may rebind these keys.
_guru_bind() {
  local name seq current
  for name seq in up '^[[A' up '^[OA' down '^[[B' down '^[OB' tab '^I' enter '^M'; do
    current=${$(bindkey -M main -- $seq)[2]}
    [[ $current == _guru_key_$name ]] && continue
    [[ -z $_guru_orig[$name] || $current != undefined-key ]] && _guru_orig[$name]=$current
    bindkey -M main -- $seq _guru_key_$name
  done
}

_guru_sync_aliases() {
  if [[ -r $_guru_alias_file ]]; then
    local -a st
    if zstat -A st +mtime -- $_guru_alias_file 2>/dev/null && (( st[1] != _guru_alias_mtime )); then
      _guru_alias_mtime=$st[1]
      source $_guru_alias_file
    fi
  fi
  [[ -n $_guru_fd ]] || return 0
  local dump="${(pj:\x1f:)${(@kv)aliases}}"
  [[ $dump == "$_guru_sent_aliases" ]] && return 0
  _guru_sent_aliases=$dump
  _guru_send "A${_guru_us}${dump//$'\n'/$_guru_rs}"
}

_guru_precmd() {
  _guru_connect
  _guru_bind
  _guru_sync_aliases
  return 0
}

_guru_preexec() {
  _guru_set_visible 0
  _guru_send X
  return 0
}

add-zsh-hook precmd _guru_precmd
add-zsh-hook preexec _guru_preexec
add-zle-hook-widget line-pre-redraw _guru_redraw
add-zle-hook-widget line-init _guru_line_init
add-zle-hook-widget keymap-select _guru_keymap_select
