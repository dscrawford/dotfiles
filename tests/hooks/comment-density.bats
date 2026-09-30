#!/usr/bin/env bats
# The PostToolUse comment challenge: which added lines count as a comment.

setup() {
  HOOK="$BATS_TEST_DIRNAME/../../claude/hooks/comment-density.sh"
}

edit() {
  jq -cn --arg f "$1" --arg s "$2" '{tool_input: {file_path: $f, new_string: $s}}' | bash "$HOOK"
}
ctx_of() { jq -r '.hookSpecificOutput.additionalContext' <<<"$1"; }

assert_challenged() {
  run edit "$1" "$2"
  echo "file: $1 | out: $output"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$(ctx_of "$output")" == *"Comment challenge"* ]]
  [ "$(jq -r '.decision // "none"' <<<"$output")" = "none" ]
}

assert_silent() {
  run edit "$1" "$2"
  echo "file: $1 | out: $output"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a single whole-line comment is challenged" {
  assert_challenged "a.py" $'x = 1\n# bump it\nx += 1'
}

@test "one challenge per edit, reporting the count and first comment" {
  run edit "a.py" $'# one\nx = 1\n# two\n# three'
  [ "$(jq -s length <<<"$output")" -eq 1 ]
  [[ "$(ctx_of "$output")" == *"a.py +3 (\`# one\`)"* ]]
  [ "$(ctx_of "$output" | wc -c)" -lt 200 ]
}

@test "code without comments is silent" {
  assert_silent "a.py" $'def f():\n    return 1'
}

@test "trailing comments are challenged per language" {
  assert_challenged "a.sh" 'rm -rf "$tmp"  # cleanup'
  assert_challenged "a.js" 'const n = 1; // count'
  assert_challenged "a.el" '(setq x 1) ;; init'
  assert_challenged "a.lua" 'local n = 1 -- count'
}

@test "other languages' comment leaders are not trailing comments" {
  assert_silent "a.py" 'q = a // b'
  assert_silent "a.sh" 'git log -- path'
  assert_silent "a.c" 'x = y # z;'
}

@test "URLs and parameter expansion are not comments" {
  assert_silent "a.js" 'const u = "https://example.com/x";'
  assert_silent "a.sh" 'echo "${path#/}"'
}

@test "cli flag continuation lines are not comments" {
  assert_silent "a.sh" $'cmd \\\n  --foo \\\n  --bar'
}

@test "preprocessor and attribute lines are not comments" {
  assert_silent "a.c" $'#include <stdio.h>\n#define X 1\n#ifdef Y\n#endif'
  assert_silent "a.rs" '#[derive(Debug)]'
}

@test "tooling directives are exempt" {
  assert_silent "a.sh" $'#!/usr/bin/env bash\n# shellcheck disable=SC2034'
  assert_silent "a.py" $'x = 1  # noqa: E501\ny = 2  # type: ignore'
  assert_silent "a.ts" $'// eslint-disable-next-line\n// @ts-expect-error'
  assert_silent "a.el" $';;; -*- lexical-binding: t -*-\n;;;###autoload'
  assert_silent "a.go" '//go:embed static'
  assert_silent "a.c" '// SPDX-License-Identifier: MIT'
}

@test "elisp package-lint headers and rust doc comments are exempt" {
  assert_silent "a.el" $';;; a.el --- thing\n;;; Commentary:\n;;; Code:\n;;; a.el ends here'
  assert_silent "a.rs" $'/// Doc line\n//! Crate doc'
  assert_challenged "a.el" ';;; Section banner'
}

@test "prose files are ignored" {
  assert_silent "README.md" '# Heading'
  assert_silent "notes.org" '# not code'
}

@test "unknown extensions use every whole-line leader, no trailing check" {
  assert_challenged "Dockerfile" $'FROM x\n# why'
  assert_challenged "a.unknownext" '// note'
  assert_silent "a.unknownext" 'x = 1 // 2'
}

@test "Write content and MultiEdit edits are scanned" {
  run bash -c 'jq -cn "{tool_input: {file_path: \"a.py\", content: \"# w\\nx=1\"}}" | bash "$0"' "$HOOK"
  [[ "$(ctx_of "$output")" == *"Comment challenge"* ]]
  run bash -c 'jq -cn "{tool_input: {file_path: \"a.py\", edits: [{new_string: \"x=1\"}, {new_string: \"# m\"}]}}" | bash "$0"' "$HOOK"
  [[ "$(ctx_of "$output")" == *"Comment challenge"* ]]
}

@test "edits without a file path are silent" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"ls\"}}" | bash "$0"' "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

copilot() {
  jq -cn --arg t "$1" --argjson a "$2" \
    '{toolName: $t, toolArgs: $a, toolResult: {resultType: "success", textResultForLlm: "ok"}}' | bash "$HOOK"
}
copilot_ctx() { jq -r '.additionalContext' <<<"$1"; }

@test "copilot edit and create payloads are scanned, answering in copilot shape" {
  run copilot edit '{"path": "/tmp/a.py", "old_str": "x=1", "new_str": "# bump\nx=2"}'
  [ "$status" -eq 0 ]
  [[ "$(copilot_ctx "$output")" == *"Comment challenge: a.py +1"* ]]
  [ "$(jq -r '.hookSpecificOutput // "none"' <<<"$output")" = "none" ]
  run copilot create '{"path": "/tmp/b.sh", "file_text": "#!/usr/bin/env bash\n# why\nls"}'
  [[ "$(copilot_ctx "$output")" == *"Comment challenge: b.sh +1"* ]]
  run copilot str_replace_editor '{"command": "str_replace", "path": "/tmp/c.js", "old_str": "a", "new_str": "// note\nb"}'
  [[ "$(copilot_ctx "$output")" == *"Comment challenge: c.js +1"* ]]
}

@test "copilot payloads without comments or without a path are silent" {
  run copilot edit '{"path": "/tmp/a.py", "old_str": "x=1", "new_str": "x=2"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run copilot bash '{"command": "ls # list"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
