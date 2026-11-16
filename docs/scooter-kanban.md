# Scooter kanban: how a card reaches the model

Scooter (scooter.dcraw.net) is deployed from
[KubeServer](https://github.com/dscrawford/KubeServer) `src/scooter/scooter.nix`,
rendered to `config/scooter/rendered.yaml` by `scripts/render-scooter.sh`. This note
covers the server side of kanban boards. The Emacs side (`C-c K`, cards in tabs) is in
`shared/emacs/scooter.nix` and the README.

## What the model gets

`contribs.kanban.enable = true` turns a sidebar folder into a board (stages Design / In
progress / Review / Done, editable per board) and its conversations into cards. The
model learns about its card from these sources:

| Source | Event | What it adds |
|---|---|---|
| `kanban.session-start` hook | `SessionStart` | the board, stage, tags, description, and the names of the board's skills, which it is told to read |
| `kanban.prompt-submit` hook | `UserPromptSubmit` | the card's current stage with each message, plus blockers and gates |
| `kanban.stop` hook | `Stop` | asks the model to call `kanban_set_status` if it ended a run without setting one |
| `kanban.board` skill provider | skill listing | the skills the user wrote on the board (e.g. `board-repos-to-work-with`) |
| broker MCP tools | — | `kanban_set_status`, `kanban_set_tags`, `kanban_set_details`, `kanban_set_blockers`, `kanban_answer_gate`, … |

All four of them call `agent-broker kanban/...`, and at the pinned Scooter rev they run
**inside the conversation's sandbox**.

## The cold-sandbox override (KubeServer#55)

A conversation's first message usually arrives before its sandbox pod is Ready. The
upstream defaults made that fail quietly:

- the agent-host skips skippable (`failClosed = false`) `SessionStart` and
  `UserPromptSubmit` hooks while the pod is starting (`Hooks skipped because your
  sandbox is still starting: kanban.session-start, kanban.prompt-submit`);
- the board skill provider waits only 5s (`waitSec = 5`, `timeoutSec = 20`).

As a result, the model's first turn on a card had no card context and no board skills.
It didn't know it was a card, didn't set a stage, and ignored the board's repo notes.

The fix is config only, in `src/scooter/scooter.nix`:

```nix
contribs.kanban = {
  enable = true;
  # Wait for a cold sandbox; drop once chadac-me/scooter#1370 is pinned.
  agent.hooks = lib.genAttrs [ "session-start" "prompt-submit" ] (_: {
    failClosed = true;
    timeout = 180;
  });
  agent.skillProviders.board = {
    timeout = lib.mkForce 180;
    wait = lib.mkForce null;   # null = wait up to `timeout`
  };
};
```

In the rendered manifest this changes `AGENT_HOOKS_JSON` (`failClosed: true`,
`timeoutSec: 180` on both hooks) and `SKILL_PROVIDERS_JSON` (`timeoutSec`/`waitSec`
180).

- `failClosed` hooks are never skipped, so the agent-host waits for the pod (up to
  180s). The hook scripts `exit 0` when the broker errors, so the prompt is blocked only
  when the pod doesn't come up at all.
- Trade-off: the first message on a cold board conversation waits for the pod instead
  of starting right away.
- `kanban.stop` keeps its defaults. It runs at the end of a turn, when the pod is
  already up.

## When to remove it

[chadac-me/scooter#1370](https://github.com/chadac-me/scooter/pull/1370) runs the kanban
hooks and skill providers through the broker, with no sandbox needed. It's on the
dscrawford/scooter fork's main but still open upstream, and the fork can't be pinned
ahead of upstream's images. Once a Scooter bump includes it, drop the `agent.hooks` and
`agent.skillProviders.board` overrides, then re-render.

## Checking it

```bash
# In KubeServer: the four overridden fields
grep -oE '"id":"kanban\.[a-z-]+"|"failClosed":(true|false)|"timeoutSec":[0-9]+|"waitSec":[0-9]+' \
  config/scooter/rendered.yaml
```

In a board conversation, the first reply should follow the board skills and set a stage
without being asked. If it says nothing about the card, look in the chat for the
"Hooks skipped" notice.
