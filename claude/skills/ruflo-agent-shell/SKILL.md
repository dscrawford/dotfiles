---
name: ruflo-agent-shell
description: Ruflo + Emacs agent-shell integration — orchestrate ruflo agents from Emacs, bridge sessions, coordinate per-tmux-pane agent-shell instances. Use when the user wants to control agents from Emacs or coordinate between Claude Code and agent-shell.
argument-hint: "[action] e.g. 'open session', 'send command', 'bridge sessions'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo + agent-shell — Emacs Integration

Ruflo is the orchestration/intelligence layer; agent-shell is the UI/interaction
layer. They connect through MCP (for Claude Code sessions) and shared project
directory context (for all agents).

## Architecture

```
agent-shell (Emacs buffer, ACP protocol)
  └─ Claude Code / Codex / Gemini CLI / etc.
       └─ MCP ──► ruflo claude-flow server (memory, tasks, routing, swarms)

ruflo (CLI / daemon)
  ├─ session management   — persists context across conversations
  ├─ memory system        — shares knowledge across agents
  ├─ task routing         — Q-learning agent-to-task assignment
  ├─ hooks/intelligence   — learns from agent activity
  └─ swarm coordination   — multi-agent orchestration
```

## Setup

Agent-shell is configured in `shared/emacs.nix`:
- Keybinding: `C-c s` opens agent-shell
- Session strategy: `prompt` (asks for session name)
- Data directory: `~/.emacs.d/agent-shell/<project>/`
- ACP command: `claude-agent-acp` (from `@zed-industries/claude-agent-acp`)

Ruflo MCP is configured in `.mcp.json` with `autoStart: true`, so every
Claude Code session inside agent-shell automatically gets ruflo tools.

### Auto-Registration Hook

When an agent-shell buffer opens, a mode hook registers the session with ruflo:

```elisp
;; In shared/emacs.nix extraConfig:
(add-hook 'agent-shell-mode-hook #'my/ruflo-register-session)
```

This calls `ruflo session save -n "agent-shell:<project>:<buffer>"` so ruflo
knows about active agent-shell sessions for coordination.

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

### MCP-Based (Claude Code in agent-shell)

When Claude Code runs inside agent-shell, it has direct access to ruflo MCP
tools. The agent can use ruflo for orchestration without any shell commands:

- **Memory**: Store/retrieve context that persists across sessions
- **Tasks**: Create, assign, and track work items
- **Routing**: Let ruflo's Q-learning pick the best agent for a task
- **Swarms**: Spawn multi-agent workflows from within the conversation

This is automatic when `.mcp.json` has `autoStart: true`.

### Delegate from Claude Code to Agent-Shell

When Claude Code is running a complex task and wants to spawn a parallel
agent in Emacs:

1. Save ruflo session: `timeout 30 ruflo session save -n "handoff" 2>&1`
2. Open agent-shell in Emacs: `emacsclient -s "$EMACS_SERVER" -e '(agent-shell)'`
3. The agent-shell session can access the same ruflo memory/state

### Monitor Ruflo from Agent-Shell

Use agent-shell to watch ruflo status while Claude Code works:

```bash
# In agent-shell, the user can ask the agent to run:
ruflo status              # system overview
ruflo session current     # active session info
ruflo task list           # pending/active tasks
ruflo memory list         # stored memories
ruflo agent list          # running agents
ruflo daemon status       # background workers
```

### Cross-Session Memory Sharing

Ruflo memory bridges agent-shell and Claude Code sessions:

```bash
# Store context from one session
ruflo memory store -k "auth-design" -v "JWT with rotating refresh tokens" 2>&1

# Retrieve in another session (agent-shell or Claude Code)
ruflo memory retrieve -k "auth-design" 2>&1

# Search across all stored memories
ruflo memory search -q "authentication" 2>&1
```

### Task Handoff Between Sessions

```bash
# Create a task in Claude Code
ruflo task create -t "Implement auth middleware" -d "JWT validation, rate limiting" 2>&1

# Pick it up in agent-shell (or vice versa)
ruflo task list 2>&1
ruflo task update <id> --status in_progress 2>&1
```

### Session Bridging

Ruflo sessions persist in `.swarm/` and agent-shell transcripts in
`~/.emacs.d/agent-shell/<project>/`. Both share the same project directory
context, so ruflo memory and agent state are accessible from either interface.

```bash
# List all ruflo sessions (including agent-shell registrations)
ruflo session list 2>&1

# Restore a previous session's context
ruflo session restore -n "agent-shell:dotfiles:*agent-shell*" 2>&1
```

## Supported Agents in Agent-Shell

Agent-shell supports 15+ agents via ACP:
- Anthropic Claude Agent / Claude Code
- OpenAI Codex
- Google Gemini CLI
- Cursor, Kimi Code, Kiro Code, Block Goose
- Augmentcode Auggie, Factory Droid, Pi, OpenCode

Each agent-shell session is isolated per buffer with its own ACP subprocess.
Only Claude Code sessions get ruflo MCP tools automatically; other agents
can use ruflo through shell commands within the conversation.
