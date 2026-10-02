#!/usr/bin/env bats
# The PreToolUse session guard: kills that would end the desktop session are denied.

setup() {
  GUARD="$BATS_TEST_DIRNAME/../../claude/hooks/session-guard.sh"
  FAKE="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKE"
  printf '#!/bin/sh\nsleep 30\n' >"$FAKE/sway"
  chmod +x "$FAKE/sway"
  export SESSION_GUARD_ROOT=$$
}

teardown() {
  pkill -f "$FAKE/sway" 2>/dev/null || true
}

guard() { printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | bash "$GUARD"; }
denied() { [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = deny ]; }

outside_sway() {
  ( "$FAKE/sway" >/dev/null 2>&1 & )
  for _ in $(seq 50); do
    pid=$(pgrep -f "$FAKE/sway" | head -1)
    [ -n "$pid" ] && [ "$(cat /proc/$pid/comm)" = sway ] && break
    sleep 0.05
  done
  echo "$pid"
}

@test "kill of a sway the agent did not start is denied" {
  pid=$(outside_sway)
  run guard "kill $pid 2>/dev/null; echo done"
  denied
  [[ "$output" == *"$pid"* ]]
}

@test "kill -9 and process-group forms are denied too" {
  pid=$(outside_sway)
  for cmd in "kill -9 $pid" "kill -s TERM $pid" "kill -KILL -- -$pid" "sudo kill $pid"; do
    run guard "$cmd"
    echo "cmd: $cmd | out: $output"
    denied
  done
}

@test "kill of a sway the agent started is allowed" {
  "$FAKE/sway" &
  child=$!
  for _ in $(seq 50); do [ "$(cat /proc/$child/comm)" = sway ] && break; sleep 0.05; done
  run guard "kill $child"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "kill of PID 1 and of every process are denied" {
  for cmd in "kill 1" "kill -9 -1" "kill -- -1"; do
    run guard "$cmd"
    echo "cmd: $cmd | out: $output"
    denied
  done
}

@test "pkill and killall by a session process name are denied" {
  outside_sway >/dev/null
  for cmd in "pkill sway" "pkill -x sway" "pkill -9 '^sway\$'" "killall sway" "killall -9 sway" "kill \$(pgrep sway)" "kill \$(pidof sway)"; do
    run guard "$cmd"
    echo "cmd: $cmd | out: $output"
    denied
  done
}

@test "pkill with a pattern that only matches the agent's own processes is allowed" {
  outside_sway >/dev/null
  run guard "pkill -f 'sway -c /tmp/tmp.abc/cfg'"
  [ -z "$output" ]
}

@test "session-ending commands are denied" {
  for cmd in "swaymsg exit" "loginctl terminate-session 3" "loginctl kill-user daniel" "loginctl terminate-user \$USER" "systemctl --user exit" "pkill -u daniel" "killall -u daniel"; do
    run guard "$cmd"
    echo "cmd: $cmd | out: $output"
    denied
  done
}

@test "swaymsg exit against a private sway socket is allowed" {
  for cmd in "SWAYSOCK=/tmp/tmp.x/sway.sock swaymsg exit" "swaymsg -s \$rt/sway.sock exit"; do
    run guard "$cmd"
    echo "cmd: $cmd | out: $output"
    [ -z "$output" ]
  done
}

@test "unrelated commands pass through" {
  for cmd in "ls -la" "kill %1" "kill \$sp" "echo killall is a word" "git commit -m 'fix: kill sway guard'" "swaymsg reload" "pgrep -a sway"; do
    run guard "$cmd"
    echo "cmd: $cmd | out: $output"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}
