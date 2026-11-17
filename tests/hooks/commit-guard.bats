#!/usr/bin/env bats

setup() {
  GUARD="$BATS_TEST_DIRNAME/../../claude/hooks/commit-guard.sh"
}

guard() { printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | bash "$GUARD"; }
denied() { [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = deny ]; }

@test "non-conventional subjects are denied however git is invoked" {
  for cmd in "git commit -m 'bad message'" "git -C /tmp/repo commit -m 'bad'" "git -c core.x=y commit -am 'bad'" "git --no-pager commit -m 'bad'"; do
    run guard "$cmd"
    echo "cmd: $cmd | out: $output"
    denied
  done
}

@test "conventional subjects and non-commit commands pass through" {
  for cmd in "git commit -m 'fix(hooks): guard sees git -C'" "git log --oneline" "echo git commits" "git commit --amend -m 'whatever'"; do
    run guard "$cmd"
    echo "cmd: $cmd | out: $output"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "-m subjects are parsed without GNU grep -P (macOS BSD grep)" {
  shim="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$shim"
  real_grep=$(command -v grep)
  printf '#!/usr/bin/env bash\nfor a; do [[ $a == -*P* && $a != --* ]] && { echo "grep: invalid option -- P" >&2; exit 2; }; done\nexec %s "$@"\n' "$real_grep" >"$shim/grep"
  chmod +x "$shim/grep"
  PATH="$shim:$PATH" run guard "git commit -m 'bad message'"
  echo "out: $output"
  [ "$status" -eq 0 ]
  denied
  PATH="$shim:$PATH" run guard "git commit -am \"fix(hooks): portable -m parsing\""
  echo "out: $output"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "only the commit's own heredoc is read as its message" {
  run guard "python3 - <<'EOF'
$(seq 12)
EOF
git commit -m \"\$(cat <<'EOF'
fix(hooks): read the commit's own heredoc
EOF
)\""
  echo "out: $output"
  [ -z "$output" ]
  run guard "python3 - <<'PY'
print('edit')
PY
git commit -m 'fix(hooks): ok'"
  echo "out: $output"
  [ -z "$output" ]
}

@test "heredoc messages with any delimiter are checked" {
  run guard "git commit -m \"\$(cat <<'MSG'
bad subject
MSG
)\""
  echo "out: $output"
  denied
}

@test "every commit in a command is checked, but not heredoc text" {
  run guard "git commit -m 'fix(x): ok' && cd /r && git commit -m 'bad'"
  echo "out: $output"
  denied
  run guard "cat > f <<'EOF'
git commit -m 'bad'
EOF"
  [ -z "$output" ]
}

@test "deny reason says staged files stay staged" {
  run guard "git add -A && git commit -m 'bad'"
  [[ $(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output") == *"git status"* ]]
}
