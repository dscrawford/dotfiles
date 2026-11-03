const MAX_RESULT_CHARS = 20000;

const KIND_WORDS = [
  ["execute", ["bash", "shell", "exec", "run", "terminal", "command"]],
  ["edit", ["edit", "editor", "write", "patch", "replace", "create"]],
  ["search", ["grep", "search", "find", "glob"]],
  ["read", ["read", "view", "cat", "ls", "list", "open"]],
  ["fetch", ["fetch", "http", "web", "url", "browse", "download"]],
  ["think", ["think", "plan", "todo"]],
];

export function toolKind(name) {
  const words = String(name ?? "").split("__").pop().toLowerCase().split(/[^a-z]+/);
  for (const [kind, vocab] of KIND_WORDS) if (words.some((w) => vocab.includes(w))) return kind;
  return "other";
}

const text = (t) => ({ type: "text", text: t });

function parseArgs(raw) {
  if (!raw) return undefined;
  try {
    return JSON.parse(raw);
  } catch {
    return raw;
  }
}

function toolTitle(name, input) {
  if (input && typeof input === "object") {
    const detail = input.command ?? input.cmd ?? input.path ?? input.file_path ?? input.url ?? input.pattern ?? input.query;
    if (typeof detail === "string" && detail) return `${name}: ${detail.length > 120 ? detail.slice(0, 117) + "..." : detail}`;
  }
  return name;
}

function clip(s) {
  return s.length > MAX_RESULT_CHARS ? s.slice(0, MAX_RESULT_CHARS) + `\n… (${s.length - MAX_RESULT_CHARS} more chars)` : s;
}

export function createTranslator() {
  const roles = new Map();
  const tools = new Map();

  return function translate(event) {
    switch (event.type) {
      case "TEXT_MESSAGE_START":
        roles.set(event.messageId, event.role);
        return [];
      case "TEXT_MESSAGE_CONTENT": {
        if (!event.delta) return [];
        const kind = roles.get(event.messageId) === "user" ? "user_message_chunk" : "agent_message_chunk";
        return [{ sessionUpdate: kind, content: text(event.delta), messageId: event.messageId }];
      }
      case "REASONING_MESSAGE_CONTENT":
        return event.delta ? [{ sessionUpdate: "agent_thought_chunk", content: text(event.delta) }] : [];
      case "TOOL_CALL_START":
        tools.set(event.toolCallId, { name: event.toolCallName, args: "" });
        return [
          {
            sessionUpdate: "tool_call",
            toolCallId: event.toolCallId,
            title: event.toolCallName,
            kind: toolKind(event.toolCallName),
            status: "in_progress",
          },
        ];
      case "TOOL_CALL_ARGS": {
        const t = tools.get(event.toolCallId);
        if (t) t.args += event.delta ?? "";
        return [];
      }
      case "TOOL_CALL_END": {
        const t = tools.get(event.toolCallId);
        if (!t?.args) return [];
        const rawInput = parseArgs(t.args);
        return [{ sessionUpdate: "tool_call_update", toolCallId: event.toolCallId, title: toolTitle(t.name, rawInput), rawInput }];
      }
      case "TOOL_CALL_RESULT":
        tools.delete(event.toolCallId);
        return [
          {
            sessionUpdate: "tool_call_update",
            toolCallId: event.toolCallId,
            status: "completed",
            content: [{ type: "content", content: text(clip(String(event.content ?? ""))) }],
          },
        ];
      case "SYSTEM_MESSAGE": {
        const who = event.sender ? `${event.source} (${event.sender})` : event.source;
        return [{ sessionUpdate: "agent_message_chunk", content: text(`\n\n> **${who}:** ${String(event.text ?? "").replace(/\n/g, "\n> ")}\n\n`) }];
      }
      case "CONTEXT_USAGE":
        return event.contextWindow > 0 ? [{ sessionUpdate: "usage_update", used: event.usedTokens, size: event.contextWindow }] : [];
      case "RUN_RETRYING":
        return [{ sessionUpdate: "agent_thought_chunk", content: text(`\n[retrying ${event.attempt}/${event.max} after ${event.code ?? "error"}]\n`) }];
      case "RUN_ERROR":
        return [{ sessionUpdate: "agent_message_chunk", content: text(`\n\n**Scooter run failed:** ${event.message}\n`) }];
      default:
        return [];
    }
  };
}

export function userTurnStarts(events) {
  const starts = [];
  events.forEach((e, i) => {
    if (e.type === "TEXT_MESSAGE_START" && e.role === "user") starts.push(i);
  });
  return starts;
}
