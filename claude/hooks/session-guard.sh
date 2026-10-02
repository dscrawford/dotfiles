#!/usr/bin/env bash
# PreToolUse guard: deny Bash commands that would end the desktop session;
# a kill may only reach a session process (sway, greetd, emacs...) the agent started.
set -uo pipefail

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
grep -qE '(^|[^[:alnum:]_-])(kill|pkill|killall|swaymsg|loginctl|systemctl)([^[:alnum:]_-]|$)' <<<"$cmd" || exit 0

PROTECTED='^(sway|Xwayland|greetd|systemd|launchd|WindowServer|loginwindow|\.?emacs.*)$'

deny() {
  jq -n --arg r "$1 It would end the user's desktop session. Only kill processes you started, by the PID you saved (\$!) or a pgrep -f pattern unique to them." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

name_of() { basename "$(ps -o comm= -p "$1" 2>/dev/null)" 2>/dev/null; }
parent_of() { ps -o ppid= -p "$1" 2>/dev/null | tr -d ' '; }

agent_root() {
  if [ -n "${SESSION_GUARD_ROOT:-}" ]; then echo "$SESSION_GUARD_ROOT"; return; fi
  local p=$PPID
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    [ "$(name_of "$p")" = claude ] && { echo "$p"; return; }
    p=$(parent_of "$p")
  done
  echo "$PPID"
}
ROOT=$(agent_root)

descends_from_agent() {
  local p=$1
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    [ "$p" = "$ROOT" ] && return 0
    p=$(parent_of "$p")
  done
  return 1
}

check_pids() {
  local pid name
  for pid in "$@"; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    [ "$pid" -le 1 ] && deny "Refusing to signal PID $pid."
    name=$(name_of "$pid")
    [[ -n "$name" && "$name" =~ $PROTECTED ]] && ! descends_from_agent "$pid" &&
      deny "PID $pid is '$name', which the agent did not start."
  done
}

matching() { pgrep "$@" 2>/dev/null | awk '$1 ~ /^[0-9]+$/ {print $1}'; }

check_kill() {
  local signal_seen=0 group w
  for w in "$@"; do
    case "$w" in
    --) signal_seen=1 ;;
    -s | -n) ;;
    -[0-9]*)
      if [ "$signal_seen" = 0 ] && [ "$#" -gt 1 ]; then signal_seen=1; continue; fi
      group=${w#-}
      [ "$group" -le 1 ] && deny "Refusing to signal every process (kill $w)."
      check_pids "$group" $(matching -g "$group")
      ;;
    -*) signal_seen=1 ;;
    [0-9]*) check_pids "$w" ;;
    esac
  done
}

check_pkill() {
  local args=() w skip=0
  for w in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$w" in
    --signal) skip=1 ;;
    --signal=* | -[0-9]* | -[A-Z]*) ;;
    *) args+=("$w") ;;
    esac
  done
  check_pids $(matching "${args[@]}")
}

check_killall() {
  local names=() user=() regex=0 skip=""
  for w in "$@"; do
    if [ -n "$skip" ]; then [ "$skip" = u ] && user=(-u "$w"); skip=""; continue; fi
    case "$w" in
    -u | --user) skip=u ;;
    -s | --signal) skip=s ;;
    -r | --regexp) regex=1 ;;
    -*) ;;
    *) names+=("$w") ;;
    esac
  done
  [ "${#names[@]}" = 0 ] && [ "${#user[@]}" -gt 0 ] && check_pids $(matching "${user[@]}")
  local exact=(-x)
  [ "$regex" = 1 ] && exact=()
  for w in "${names[@]}"; do check_pids $(matching "${exact[@]}" "${user[@]}" "$w"); done
}

check_segment() {
  local words i=0 private=0
  read -ra words <<<"$1"
  words=("${words[@]//[\'\"]/}")
  while [ "$i" -lt "${#words[@]}" ]; do
    case "${words[$i]}" in
    SWAYSOCK=*) private=1 ;;
    sudo | env | command | exec | nohup | *=*) ;;
    *) break ;;
    esac
    i=$((i + 1))
  done
  local verb=${words[$i]:-} rest=("${words[@]:$((i + 1))}")
  local all=" ${rest[*]} "
  case "$(basename -- "$verb" 2>/dev/null)" in
  kill) check_kill "${rest[@]}" ;;
  pkill) check_pkill "${rest[@]}" ;;
  killall) check_killall "${rest[@]}" ;;
  pgrep) [ "$KILLS" = 1 ] && check_pids $(matching "${rest[@]}") ;;
  pidof) [ "$KILLS" = 1 ] && for w in "${rest[@]}"; do check_pids $(matching -x "$w"); done ;;
  swaymsg)
    [[ "$all" == *" exit "* && "$private" = 0 && "$all" != *" -s "* && "$all" != *" --socket"* ]] &&
      deny "swaymsg exit targets the user's sway."
    ;;
  loginctl)
    [[ "$all" =~ \ (terminate|kill)-(session|user|seat)\  ]] && deny "loginctl ${BASH_REMATCH[1]}-${BASH_REMATCH[2]} ends logins."
    ;;
  systemctl)
    [[ "$all" == *" --user "* && "$all" =~ \ exit\ |(stop|kill|restart)\ .*(sway|graphical-session) ]] &&
      deny "systemctl --user would stop the session."
    ;;
  esac
}

KILLS=0
grep -qE '(^|[^[:alnum:]_-])kill[[:space:]]' <<<"$cmd" && KILLS=1
while IFS= read -r segment; do
  [ -n "${segment// /}" ] && check_segment "$segment"
done < <(sed -E 's/\|\||&&|[;|&()`]|\$\(/\n/g' <<<"$cmd")
exit 0
