---
name: ruflo-agent-shell
description: Ruflo + Emacs agent-shell integration — orchestrate ruflo agents from Emacs, bridge sessions, coordinate per-tmux-pane agent-shell instances. Use when the user wants to control agents from Emacs or coordinate between Claude Code and agent-shell.
argument-hint: "[action] e.g. 'open session', 'send command', 'bridge sessions'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo + agent-shell — Emacs Integration

Control ruflo agents from within Emacs agent-shell sessions. Agent-shell provides
an interactive ACP-based shell for AI agents inside Emacs buffers.

## Setup

Agent-shell is configured in `shared/emacs.nix`:
- Keybinding: `C-c s` opens agent-shell
- Session strategy: `prompt` (asks for session name)
- Data directory: `~/.emacs.d/agent-shell/<project>/`
- ACP command: `claude-agent-acp` (from `@zed-industries/claude-agent-acp`)

## Per-Tmux-Pane Targeting

The user's Emacs setup uses per-tmux-pane servers. Target the right one:

```bash
# Use the current pane's Emacs server
emacsclient -s "$EMACS_SERVER" -e '(agent-shell)'

# If $EMACS_SERVER is not set, derive from TMUX_PANE
EMACS_SERVER="emacs-${TMUX_PANE#%}"
emacsclient -s "$EMACS_SERVER" -e '(agent-shell)'
```

## Commands

### Open an Agent-Shell Session
```bash
emacsclient -s "$EMACS_SERVER" -e '(agent-shell)' 2>&1
```

### Send Input to Active Session
```bash
emacsclient -s "$EMACS_SERVER" -e '(agent-shell-send-input "ruflo status")' 2>&1
```

### Send a File for Analysis
```bash
emacsclient -s "$EMACS_SERVER" -e '(agent-shell-send-file "/path/to/file")' 2>&1
```

### Cycle Session Mode
```bash
# C-M-<tab> in agent-shell buffer, or:
emacsclient -s "$EMACS_SERVER" -e '(agent-shell-cycle-session-mode)' 2>&1
```

## Coordination Patterns

### Delegate from Claude Code to Agent-Shell
When Claude Code is running a complex task and wants to spawn a parallel
agent in Emacs:

1. Save ruflo session: `timeout 30 ruflo session save -n "handoff" 2>&1`
2. Open agent-shell in Emacs: `emacsclient -s "$EMACS_SERVER" -e '(agent-shell)'`
3. The agent-shell session can access the same ruflo memory/state

### Monitor Ruflo from Emacs
Use agent-shell to watch ruflo status while Claude Code works:

```bash
# In agent-shell, the user can run:
# ruflo status
# ruflo session current
# ruflo daemon status
```

### Session Bridging
Ruflo sessions persist in `.swarm/` and agent-shell transcripts in
`~/.emacs.d/agent-shell/<project>/`. Both share the same project directory
context, so ruflo memory and agent state are accessible from either interface.

## Supported Agents in Agent-Shell

Agent-shell supports 15+ agents via ACP:
- Anthropic Claude Agent / Claude Code
- OpenAI Codex
- Google Gemini CLI
- Cursor, Kimi Code, Kiro Code, Block Goose
- Augmentcode Auggie, Factory Droid, Pi, OpenCode

Each agent-shell session is isolated per buffer with its own ACP subprocess.
