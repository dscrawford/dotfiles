#!/nix/store/v8sa6r6q037ihghxfbwzjj4p59v2x0pv-bash-5.3p9/bin/bash
# Capture hook guidance for Claude visibility
GUIDANCE_FILE=".claude-flow/last-guidance.txt"
mkdir -p .claude-flow

case "$1" in
  "route")
    npx agentic-flow@alpha hooks route "$2" 2>&1 | tee "$GUIDANCE_FILE"
    ;;
  "pre-edit")
    npx agentic-flow@alpha hooks pre-edit "$2" 2>&1 | tee "$GUIDANCE_FILE"
    ;;
esac
