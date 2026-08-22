#!/usr/bin/env node
// MCP stdio server routing small subagent tasks to a local Ollama model.
// Transport is newline-delimited JSON per the MCP stdio spec — NOT
// LSP-style Content-Length framing, which Claude Code/agent-shell reject.

import { createInterface } from "node:readline";
import { pathToFileURL } from "node:url";

const SERVER_NAME = "local-llm-router";
const SERVER_VERSION = "0.3.0";
const SUPPORTED_PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"];
const LATEST_PROTOCOL_VERSION = "2025-06-18";

const CHAT_TIMEOUT_MS = 120000;
const TAGS_TIMEOUT_MS = 15000;
const PULL_TIMEOUT_MS = 600000;

// Official-library tags only (no registry host/path): a registry-form tag
// would let prompt-injected tool calls pull an attacker-hosted model.
const PROVISIONABLE_TAG_PATTERN = /^[a-z0-9][a-z0-9._-]{0,99}(:[A-Za-z0-9._-]{1,100})?$/;

const MAX_TASK_CHARS = 200000;

export function parseOverrideMap(raw) {
  if (!raw) {
    return {};
  }
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return {};
    }
    return Object.fromEntries(
      Object.entries(parsed)
        .filter(([key, value]) => typeof key === "string" && typeof value === "string")
        .map(([key, value]) => [key.trim(), value.trim()])
        .filter(([key, value]) => key.length > 0 && value.length > 0),
    );
  } catch {
    return {};
  }
}

export function readConfig(env) {
  return {
    ollamaHost: (env.OLLAMA_HOST || "http://127.0.0.1:11434").replace(/\/+$/, ""),
    defaultModel: env.LOCAL_LLM_DEFAULT_MODEL || "qwen3:8b",
    fallbackModel: env.LOCAL_LLM_FALLBACK_MODEL || "",
    overrides: parseOverrideMap(env.LOCAL_LLM_MODEL_OVERRIDES),
  };
}

export function isProvisionableModelTag(tag) {
  return typeof tag === "string" && PROVISIONABLE_TAG_PATTERN.test(tag);
}

export function clampNumber(value, min, max, fallback) {
  if (!Number.isFinite(value)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, value));
}

export function resolveModel({ requestedModel, availableModels, config }) {
  const requested = (requestedModel || "").trim();
  const availableSet = new Set(availableModels);
  const override = requested ? config.overrides[requested] : undefined;

  if (override && availableSet.has(override)) {
    return {
      selectedModel: override,
      resolution: `override:${requested}->${override}`,
      requestedModel: requested,
    };
  }
  if (requested && availableSet.has(requested)) {
    return { selectedModel: requested, resolution: "requested", requestedModel: requested };
  }
  if (config.defaultModel && availableSet.has(config.defaultModel)) {
    return {
      selectedModel: config.defaultModel,
      resolution: "default",
      requestedModel: requested || null,
    };
  }
  if (config.fallbackModel && availableSet.has(config.fallbackModel)) {
    return {
      selectedModel: config.fallbackModel,
      resolution: "fallback",
      requestedModel: requested || null,
    };
  }
  // No first-available fallback: a model pulled by anyone (including a
  // prompt-injected provision call) must never silently become the reviewer.
  return { selectedModel: null, resolution: "none-available", requestedModel: requested || null };
}

// Null prototype + typeof check: profile is caller-controlled, and a lookup
// like "__proto__" or "constructor" must fall back, not resolve.
const PROFILE_PROMPTS = Object.assign(Object.create(null), {
  "test-review": [
    "You are a test-focused reviewer.",
    "Identify test gaps, flaky risks, and concise concrete fixes.",
    "Prioritize high-signal findings only.",
  ].join(" "),
  "security-review": [
    "You are a security-focused reviewer.",
    "Identify exploitable issues first (authz/authn, injection, secrets, deserialization, SSRF, RCE).",
    "Return concise, actionable remediation guidance.",
  ].join(" "),
  "summarize-log": [
    "You summarize command and build logs.",
    "Report: overall outcome, each distinct error or failure with its location, and the last action before failure.",
    "Preserve exact error messages, file paths, and exit codes verbatim. Omit passing noise. Be brief.",
  ].join(" "),
  "classify-diff": [
    "You classify code diffs.",
    "Output exactly: type (feat|fix|refactor|docs|test|chore|perf|ci|build|style), scope (subsystem touched),",
    "risk (low|medium|high) with a one-line reason, and a one-sentence summary of the change.",
  ].join(" "),
  "commit-message": [
    "You write git commit messages from diffs.",
    "Output only the message: a conventional-commit subject line '<type>: <description>' under 72 characters,",
    "then a blank line and a short body only when the why is not obvious from the subject.",
    "No markdown, no code fences, no commentary.",
  ].join(" "),
  general: "You are a concise engineering assistant. Focus on concrete, actionable output.",
});

function profilePrompt(profile) {
  const prompt = PROFILE_PROMPTS[profile];
  return typeof prompt === "string" ? prompt : PROFILE_PROMPTS.general;
}

// `output` mirrors the text block: clients that render structuredContent in
// its place would otherwise show routing metadata and drop the model's answer.
function formatToolResult(text, structuredContent, isError = false) {
  return {
    content: [{ type: "text", text }],
    structuredContent: { ...structuredContent, output: text },
    isError,
  };
}

// The body is consumed inside the timer's lifetime: clearing on header
// arrival would let a stalled body read hang the tool call forever.
async function fetchJsonWithTimeout(url, options, timeoutMs, label) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    if (!response.ok) {
      const body = await response.text();
      throw new Error(`${label} request failed (${response.status}): ${body.slice(0, 500)}`);
    }
    return await response.json();
  } finally {
    clearTimeout(timer);
  }
}

async function listLocalModels(config) {
  const payload = await fetchJsonWithTimeout(
    `${config.ollamaHost}/api/tags`,
    {},
    TAGS_TIMEOUT_MS,
    "Ollama tags",
  );
  const models = Array.isArray(payload?.models) ? payload.models : [];
  return models
    .map((entry) => entry?.name)
    .filter((name) => typeof name === "string" && name.length > 0);
}

async function postChat(config, body) {
  return fetchJsonWithTimeout(
    `${config.ollamaHost}/api/chat`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    },
    CHAT_TIMEOUT_MS,
    "Ollama chat",
  );
}

async function runChat(config, { model, task, system, temperature, maxTokens }) {
  const body = {
    model,
    stream: false,
    messages: [
      { role: "system", content: system },
      { role: "user", content: task },
    ],
    options: { temperature, num_predict: maxTokens },
  };

  // Reasoning models spend num_predict on thinking before emitting any
  // content, so a modest maxTokens yields an empty answer. Older Ollama
  // builds reject the field outright, hence the retry without it.
  let json;
  try {
    json = await postChat(config, { ...body, think: false });
  } catch (error) {
    if (!/think/i.test(error.message)) {
      throw error;
    }
    json = await postChat(config, body);
  }

  const content = json?.message?.content;
  if (typeof content !== "string" || content.length === 0) {
    const thinking = json?.message?.thinking;
    if (typeof thinking === "string" && thinking.length > 0) {
      throw new Error(
        `Ollama returned only reasoning tokens and no answer; raise maxTokens above ${maxTokens} or use a non-reasoning model`,
      );
    }
    throw new Error("Ollama returned an empty response");
  }
  return content;
}

// HTTP pull instead of spawnSync("ollama pull"): a sync spawn blocks the
// event loop for the whole download, so pings and other tool calls stall.
async function pullModel(config, model) {
  const json = await fetchJsonWithTimeout(
    `${config.ollamaHost}/api/pull`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ model, stream: false }),
    },
    PULL_TIMEOUT_MS,
    "Ollama pull",
  );

  if (json?.status !== "success") {
    throw new Error(`Ollama pull did not complete: ${JSON.stringify(json).slice(0, 500)}`);
  }
  return json.status;
}

const TOOL_DEFS = [
  {
    name: "local_model_status",
    description:
      "Check whether Ollama is reachable, list local models, and show configured model overrides.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "local_model_provision",
    description: "Pull a local model into Ollama so sub-agents can use it.",
    inputSchema: {
      type: "object",
      properties: {
        model: { type: "string", description: "Model tag to pull, e.g. qwen3:8b" },
      },
      required: ["model"],
      additionalProperties: false,
    },
  },
  {
    name: "local_model_run",
    description:
      "Run a small scoped task through a local model. If requestedModel has an override, the local mapped model is used.",
    inputSchema: {
      type: "object",
      properties: {
        task: { type: "string", description: "Task or prompt to run locally" },
        requestedModel: {
          type: "string",
          description:
            "Optional upstream model hint (e.g. claude-sonnet-5); resolved to local override when configured.",
        },
        profile: {
          type: "string",
          enum: [
            "general",
            "test-review",
            "security-review",
            "summarize-log",
            "classify-diff",
            "commit-message",
          ],
          default: "general",
        },
        temperature: { type: "number", minimum: 0, maximum: 2, default: 0.2 },
        maxTokens: { type: "integer", minimum: 64, maximum: 8192, default: 1024 },
      },
      required: ["task"],
      additionalProperties: false,
    },
  },
];

async function handleStatus(config) {
  try {
    const models = await listLocalModels(config);
    const text = [
      `Ollama host: ${config.ollamaHost}`,
      `Default model: ${config.defaultModel}`,
      `Fallback model: ${config.fallbackModel || "(none)"}`,
      `Local models (${models.length}): ${models.length > 0 ? models.join(", ") : "(none)"}`,
      `Override map entries: ${Object.keys(config.overrides).length}`,
    ].join("\n");
    return formatToolResult(text, {
      host: config.ollamaHost,
      defaultModel: config.defaultModel,
      fallbackModel: config.fallbackModel || null,
      localModels: models,
      modelOverrides: config.overrides,
    });
  } catch (error) {
    return formatToolResult(
      `Local model status failed: ${error.message}`,
      { host: config.ollamaHost, error: error.message },
      true,
    );
  }
}

async function handleProvision(config, args) {
  const model = typeof args?.model === "string" ? args.model.trim() : "";
  if (!isProvisionableModelTag(model)) {
    return formatToolResult(
      "model must be an official library tag (no registry host), e.g. qwen3:8b",
      { model, error: "invalid model tag" },
      true,
    );
  }
  try {
    const status = await pullModel(config, model);
    return formatToolResult(`Provisioned model '${model}'.`, { model, status });
  } catch (error) {
    return formatToolResult(
      `Failed to provision model '${model}': ${error.message}`,
      { model, error: error.message },
      true,
    );
  }
}

async function handleRun(config, args) {
  const task = typeof args?.task === "string" ? args.task.trim() : "";
  if (!task) {
    return formatToolResult("task is required", { error: "task is required" }, true);
  }
  if (task.length > MAX_TASK_CHARS) {
    return formatToolResult(
      `task exceeds ${MAX_TASK_CHARS} characters; split it or summarize first`,
      { error: "task too large", taskChars: task.length },
      true,
    );
  }

  const profile = typeof args?.profile === "string" ? args.profile : "general";
  const temperature = clampNumber(args?.temperature, 0, 2, 0.2);
  const maxTokens = Number.isInteger(args?.maxTokens)
    ? clampNumber(args.maxTokens, 64, 8192, 1024)
    : 1024;
  const requestedModel = typeof args?.requestedModel === "string" ? args.requestedModel : "";

  try {
    const availableModels = await listLocalModels(config);
    const resolved = resolveModel({ requestedModel, availableModels, config });

    if (!resolved.selectedModel) {
      return formatToolResult(
        "No usable local model: none of override/requested/default/fallback is pulled. Pull one first with local_model_provision.",
        {
          requestedModel: resolved.requestedModel,
          resolution: resolved.resolution,
          availableModels,
        },
        true,
      );
    }

    const text = await runChat(config, {
      model: resolved.selectedModel,
      task,
      system: profilePrompt(profile),
      temperature,
      maxTokens,
    });

    return formatToolResult(text, {
      selectedModel: resolved.selectedModel,
      requestedModel: resolved.requestedModel,
      resolution: resolved.resolution,
      profile,
      temperature,
      maxTokens,
    });
  } catch (error) {
    return formatToolResult(
      `Local model execution failed: ${error.message}`,
      { error: error.message, requestedModel, profile },
      true,
    );
  }
}

export async function handleToolCall(config, name, args) {
  if (name === "local_model_status") {
    return handleStatus(config);
  }
  if (name === "local_model_provision") {
    return handleProvision(config, args);
  }
  if (name === "local_model_run") {
    return handleRun(config, args);
  }
  return formatToolResult(`Unknown tool: ${name}`, { error: `Unknown tool: ${name}` }, true);
}

function writeMessage(payload) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

export async function handleRequest(config, request) {
  if (!request || typeof request !== "object" || request.jsonrpc !== "2.0") {
    return;
  }

  const { id, method, params } = request;
  const respond = (result) => writeMessage({ jsonrpc: "2.0", id, result });
  const fail = (code, message) => writeMessage({ jsonrpc: "2.0", id, error: { code, message } });

  if (typeof method !== "string" || method.length === 0) {
    if (id !== undefined) {
      fail(-32600, "Invalid Request: method is required");
    }
    return;
  }
  if (method.startsWith("notifications/")) {
    return;
  }
  // JSON-RPC notification: never respond, never execute side effects.
  if (id === undefined) {
    return;
  }

  if (method === "initialize") {
    const requested = params?.protocolVersion;
    respond({
      protocolVersion: SUPPORTED_PROTOCOL_VERSIONS.includes(requested)
        ? requested
        : LATEST_PROTOCOL_VERSION,
      capabilities: { tools: {} },
      serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
    });
    return;
  }
  if (method === "ping") {
    respond({});
    return;
  }
  if (method === "tools/list") {
    respond({ tools: TOOL_DEFS });
    return;
  }
  if (method === "tools/call") {
    const toolName = params?.name;
    if (typeof toolName !== "string" || toolName.length === 0) {
      respond(formatToolResult("Invalid tool call: missing name", { error: "missing name" }, true));
      return;
    }
    respond(await handleToolCall(config, toolName, params?.arguments || {}));
    return;
  }

  fail(-32601, `Method not found: ${method}`);
}

export function startStdioServer(config) {
  const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
  let inFlight = 0;
  let stdinClosed = false;
  const maybeExit = () => {
    if (stdinClosed && inFlight === 0) {
      process.exit(0);
    }
  };
  rl.on("line", (line) => {
    const trimmed = line.trim();
    if (!trimmed) {
      return;
    }
    let message;
    try {
      message = JSON.parse(trimmed);
    } catch {
      return;
    }
    inFlight += 1;
    handleRequest(config, message)
      .catch((error) => {
        if (message?.id !== undefined) {
          writeMessage({
            jsonrpc: "2.0",
            id: message.id,
            error: { code: -32603, message: `Internal error: ${error.message}` },
          });
        }
      })
      .finally(() => {
        inFlight -= 1;
        maybeExit();
      });
  });
  // Parent gone: drain in-flight work (bounded by the request timeouts) so
  // piped one-shot use still gets its response, then exit instead of
  // lingering as an orphan holding a GPU generation.
  rl.on("close", () => {
    stdinClosed = true;
    maybeExit();
  });
  process.stdout.on("error", () => process.exit(0));
  process.stdin.on("error", () => {
    process.exitCode = 1;
  });
}

const isMain =
  typeof process.argv[1] === "string" &&
  import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  startStdioServer(readConfig(process.env));
}
