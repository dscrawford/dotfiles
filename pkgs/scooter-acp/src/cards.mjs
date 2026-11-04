import { INVALID_PARAMS, RpcError } from "./jsonrpc.mjs";

export const ANSWER = "scooter:answer";
export const DISMISS = "scooter:dismiss";
export const BROWSER = "scooter:browser";

const MAX_RAW_CHARS = 4000;

const browserOption = { optionId: BROWSER, name: "Open in browser", kind: "allow_always" };

const strings = (v) => (typeof v === "string" ? [v] : Array.isArray(v) ? v.filter((x) => typeof x === "string") : []);
const bullets = (items) => items.map((i) => `  - ${i}`).join("\n");

export function questionsOf(data) {
  const raw = data?.questions;
  if (!Array.isArray(raw)) return undefined;
  const qs = raw
    .filter((q) => typeof q?.question === "string")
    .map((q) => ({
      question: q.question,
      header: typeof q.header === "string" ? q.header : "",
      multiSelect: q.multiSelect === true,
      options: (Array.isArray(q.options) ? q.options : []).filter((o) => typeof o?.label === "string"),
    }));
  return qs.length ? qs : undefined;
}

function questionsText(qs) {
  return qs
    .map((q, i) => {
      const head = `${i + 1}. ${q.header ? `[${q.header}] ` : ""}${q.question}${q.multiSelect ? " (pick any)" : ""}`;
      const opts = q.options.map((o) => `${o.label}${o.description ? ` — ${o.description}` : ""}`);
      return opts.length ? `${head}\n${bullets(opts)}` : head;
    })
    .join("\n\n");
}

export function answerOf(q, picks) {
  const given = strings(picks).map((s) => s.trim()).filter(Boolean);
  if (!q.multiSelect) return given[0] ?? "";
  const labels = q.options.map((o) => o.label);
  return [...labels.filter((l) => given.includes(l)), ...given.filter((g) => !labels.includes(g))].join(", ");
}

const CUSTOM_ANSWER_META = "_askUserQuestionCustomAnswer";
const fieldKey = (i) => `q${i}`;
const customKey = (i) => `q${i}_other`;

function questionFields(q, i) {
  const options = q.options.map((o) => ({ const: o.label, title: o.label, ...(o.description ? { description: o.description } : {}) }));
  const base = { title: q.header || q.question, description: q.question };
  if (!options.length) return [[fieldKey(i), { type: "string", ...base }]];
  const select = q.multiSelect ? { type: "array", ...base, items: { anyOf: options } } : { type: "string", ...base, oneOf: options };
  const other = { type: "string", title: "Other", _meta: { [CUSTOM_ANSWER_META]: { questionId: fieldKey(i) } } };
  return [[fieldKey(i), select], [customKey(i), other]];
}

export function questionSchema(qs) {
  return {
    type: "object",
    properties: Object.fromEntries(qs.flatMap(questionFields)),
    required: qs.map((_, i) => fieldKey(i)),
  };
}

export function formPicks(qs, content) {
  return qs.map((_, i) => content?.[customKey(i)] ?? content?.[fieldKey(i)]);
}

function collect(questions, answers) {
  if (!Array.isArray(answers) || answers.length !== questions.length) {
    throw new RpcError(INVALID_PARAMS, `expected ${questions.length} answers`);
  }
  const out = {};
  questions.forEach((q, i) => {
    const a = answerOf(q, answers[i]);
    if (!a) throw new RpcError(INVALID_PARAMS, `no answer to: ${q.question}`);
    out[q.question] = a;
  });
  return out;
}

function statementsOf(policy) {
  const raw = policy?.Statement;
  const list = Array.isArray(raw) ? raw : raw && typeof raw === "object" ? [raw] : [];
  return list.filter((s) => s && typeof s === "object");
}

function awsText(d) {
  if (typeof d?.account !== "string" || typeof d?.risk !== "string") return undefined;
  const writes = new Set(strings(d.write_actions));
  const lines = [`AWS account ${d.account}, ${d.risk} risk`];
  if (d.justification) lines.push(`Why: ${d.justification}`);
  if (d.summary) lines.push(`Summary: ${d.summary}`);
  for (const s of statementsOf(d.policy_document)) {
    const actions = strings(s.Action).map((a) => (writes.has(a) ? `${a} (write)` : a));
    lines.push(`${s.Effect ?? "Allow"}:\n${bullets(actions)}\n  on ${strings(s.Resource).join(", ") || "*"}`);
    if (s.Condition) lines.push(`  when ${JSON.stringify(s.Condition)}`);
  }
  const arns = strings(d.managed_policy_arns);
  if (arns.length) lines.push(`Managed policies:\n${bullets(arns)}`);
  const obligations = Array.isArray(d.obligations) ? d.obligations : [];
  if (obligations.length) {
    lines.push(`Approvals:\n${bullets(obligations.map((o) => `${strings(o?.rules).join(", ")}: ${o?.approved_by ? `approved by ${o.approved_by}` : "waiting"}`))}`);
  }
  return lines.join("\n");
}

function commitsText(d) {
  if (typeof d?.name !== "string" || typeof d?.email !== "string" || !d.name || !d.email) return undefined;
  return `Use this as your commit identity?\n  ${d.name} <${d.email}>\nApproving withdraws other agents' proposals.`;
}

function rawText(kind, data) {
  const json = JSON.stringify(data ?? null, null, 2) ?? "null";
  const clipped = json.length > MAX_RAW_CHARS ? `${json.slice(0, MAX_RAW_CHARS)}\n…` : json;
  return `Emacs has no card for ${kind} requests; open it in the browser for the full card.\n\`\`\`json\n${clipped}\n\`\`\``;
}

const DISPLAY = { "aws.permissions": awsText, "commits.identity": commitsText };

function describe(intr) {
  const m = intr.metadata ?? {};
  const options = (Array.isArray(m.options) ? m.options : []).map((o) => ({ optionId: o.optionId, name: o.name ?? o.optionId, kind: o.kind ?? "allow_once" }));
  const kind = typeof m.kind === "string" && m.kind ? m.kind : undefined;
  if (!kind) return { options };
  const questions = kind === "ask-user.questions" ? questionsOf(m.data) : undefined;
  if (questions && options.length) {
    return {
      questions,
      answerWith: options[0].optionId,
      detail: questionsText(questions),
      rawInput: { questions },
      options: [
        { optionId: ANSWER, name: questions.length > 1 ? "Answer…" : "Answer", kind: "allow_once" },
        { optionId: DISMISS, name: "Dismiss", kind: "reject_once" },
        browserOption,
      ],
    };
  }
  const detail = DISPLAY[kind]?.(m.data) ?? rawText(kind, m.data);
  return { detail, options: [...options, browserOption] };
}

export function createCards() {
  const results = new Map();

  return {
    permission(intr) {
      const card = describe(intr);
      const title = intr.message ?? "Scooter needs your choice";
      const toolCall = { toolCallId: intr.toolCallId ?? intr.id, title, status: "pending" };
      if (card.detail) toolCall.content = [{ type: "content", content: { type: "text", text: card.detail } }];
      if (card.rawInput) toolCall.rawInput = card.rawInput;
      return { toolCall, options: card.options };
    },

    form(intr) {
      const card = describe(intr);
      if (!card.questions) return undefined;
      const toolCallId = intr.toolCallId ?? intr.id;
      const title = intr.message ?? "Scooter has a question";
      return {
        toolCall: { toolCallId, title, kind: "other", status: "pending", rawInput: card.rawInput },
        params: { mode: "form", toolCallId, message: title, requestedSchema: questionSchema(card.questions) },
      };
    },

    formResolved(intr, response) {
      if (response?.action !== "accept") return { entry: { status: "cancelled" }, text: "Dismissed" };
      const { questions, answerWith } = describe(intr);
      const answers = collect(questions, formPicks(questions, response.content));
      const text = Object.entries(answers).map(([q, a]) => `${q}: ${a}`).join("\n");
      return { entry: { status: "resolved", payload: { optionId: answerWith, result: { answers } } }, text };
    },

    answer(intr, answers) {
      const card = describe(intr);
      if (!card.questions) throw new RpcError(INVALID_PARAMS, `interrupt ${intr.id} takes no answers`);
      results.set(intr.id, { answers: collect(card.questions, answers) });
    },

    resume(intr, optionId) {
      if (!optionId || optionId === DISMISS) return { status: "cancelled" };
      if (optionId === BROWSER) return undefined;
      if (optionId === ANSWER) {
        const result = results.get(intr.id);
        results.delete(intr.id);
        return result ? { status: "resolved", payload: { optionId: describe(intr).answerWith, result } } : undefined;
      }
      return { status: "resolved", payload: { optionId } };
    },
  };
}
