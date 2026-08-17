// Tests for pkgs/local-llm-mcp/server.mjs: pure-function units plus
// stdio protocol integration against a mock Ollama HTTP server.
import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { createInterface } from "node:readline";
import { once } from "node:events";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  clampNumber,
  isProvisionableModelTag,
  parseOverrideMap,
  readConfig,
  resolveModel,
} from "../../pkgs/local-llm-mcp/server.mjs";

const SERVER_PATH = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../pkgs/local-llm-mcp/server.mjs",
);

test("parseOverrideMap", async (t) => {
  const cases = [
    ["undefined env", undefined, {}],
    ["empty string", "", {}],
    ["invalid JSON", "{not json", {}],
    ["array input", '["a","b"]', {}],
    ["null", "null", {}],
    ["scalar", '"x"', {}],
    ["empty object", "{}", {}],
    ["drops non-string values", '{"a":1,"b":"m"}', { b: "m" }],
    ["drops boolean and null values", '{"a":true,"b":null,"c":"m"}', { c: "m" }],
    ["drops nested object values", '{"a":{"x":"y"},"b":"m"}', { b: "m" }],
    ["trims keys and values", '{" sonnet ":" qwen3:8b "}', { sonnet: "qwen3:8b" }],
    ["drops empty after trim", '{"  ":"m","a":"  "}', {}],
    ["unicode keys survive", '{"sønnet→":"qwen3:8b"}', { "sønnet→": "qwen3:8b" }],
    ["valid map", '{"claude-sonnet-5":"qwen3:8b"}', { "claude-sonnet-5": "qwen3:8b" }],
  ];
  for (const [name, raw, want] of cases) {
    await t.test(name, () => assert.deepEqual(parseOverrideMap(raw), want));
  }
});

test("isProvisionableModelTag", async (t) => {
  const cases = [
    ["plain tag", "qwen3:8b", true],
    ["no version", "llama3", true],
    ["registry path (attacker-hosted model)", "registry.example.com/user/model:v1.2", false],
    ["slash without host", "user/model:1b", false],
    ["uppercase name rejected", "Qwen3:8b", false],
    ["uppercase in tag allowed", "qwen3:8B", true],
    ["name at 100-char limit", "a".repeat(100), true],
    ["name over 100-char limit", "a".repeat(101), false],
    ["tag at 100-char limit", `m:${"a".repeat(100)}`, true],
    ["tag over 100-char limit", `m:${"a".repeat(101)}`, false],
    ["empty", "", false],
    ["non-string", 42, false],
    ["null", null, false],
    ["leading dash (flag injection)", "--insecure", false],
    ["leading dot", ".hidden:1", false],
    ["double colon", "a:b:c", false],
    ["trailing colon", "qwen3:", false],
    ["whitespace", "qwen3 8b", false],
    ["embedded newline", "qwen3\n:8b", false],
    ["shell metacharacters", "m;rm -rf /", false],
    ["overlong name", `${"a".repeat(300)}:8b`, false],
  ];
  for (const [name, tag, want] of cases) {
    await t.test(name, () => assert.equal(isProvisionableModelTag(tag), want));
  }
});

test("clampNumber", async (t) => {
  const cases = [
    ["in range", 1, 0, 2, 0.2, 1],
    ["at min boundary", 0, 0, 2, 0.2, 0],
    ["at max boundary", 2, 0, 2, 0.2, 2],
    ["below min", -5, 0, 2, 0.2, 0],
    ["above max", 99, 0, 2, 0.2, 2],
    ["NaN falls back", NaN, 0, 2, 0.2, 0.2],
    ["undefined falls back", undefined, 0, 2, 0.2, 0.2],
    ["null falls back", null, 0, 2, 0.2, 0.2],
    ["numeric string falls back", "1", 0, 2, 0.2, 0.2],
    ["Infinity falls back", Infinity, 0, 2, 0.2, 0.2],
    ["-Infinity falls back", -Infinity, 0, 2, 0.2, 0.2],
  ];
  for (const [name, value, min, max, fallback, want] of cases) {
    await t.test(name, () => assert.equal(clampNumber(value, min, max, fallback), want));
  }
});

test("resolveModel precedence", async (t) => {
  const config = {
    defaultModel: "default-m",
    fallbackModel: "fallback-m",
    overrides: { "claude-sonnet-5": "mapped-m" },
  };
  const cases = [
    ["override wins when pulled", "claude-sonnet-5", ["mapped-m", "default-m"], "mapped-m", "override:claude-sonnet-5->mapped-m"],
    ["override missing -> default", "claude-sonnet-5", ["default-m"], "default-m", "default"],
    ["override missing but requested name pulled -> requested", "claude-sonnet-5", ["claude-sonnet-5", "default-m"], "claude-sonnet-5", "requested"],
    ["untrimmed request still hits override", "  claude-sonnet-5  ", ["mapped-m"], "mapped-m", "override:claude-sonnet-5->mapped-m"],
    ["requested tag pulled locally", "other-m", ["other-m"], "other-m", "requested"],
    ["requested equals default", "default-m", ["default-m"], "default-m", "requested"],
    ["no request -> default", "", ["default-m", "fallback-m"], "default-m", "default"],
    ["default missing -> fallback", "", ["fallback-m", "x"], "fallback-m", "fallback"],
    ["no match despite pulls -> none (no first-available)", "", ["only-m"], null, "none-available"],
    ["nothing pulled", "", [], null, "none-available"],
    ["unknown request with nothing pulled", "ghost-m", [], null, "none-available"],
    ["whitespace request treated as empty", "   ", ["default-m"], "default-m", "default"],
  ];
  for (const [name, requestedModel, availableModels, wantModel, wantResolution] of cases) {
    await t.test(name, () => {
      const got = resolveModel({ requestedModel, availableModels, config });
      assert.equal(got.selectedModel, wantModel);
      assert.equal(got.resolution, wantResolution);
    });
  }
});

test("readConfig", async (t) => {
  const defaults = {
    ollamaHost: "http://127.0.0.1:11434",
    defaultModel: "qwen3:8b",
    fallbackModel: "",
    overrides: {},
  };
  const cases = [
    ["empty env applies defaults", {}, defaults],
    ["strips trailing slashes", { OLLAMA_HOST: "http://x:1234///" }, { ...defaults, ollamaHost: "http://x:1234" }],
    ["empty OLLAMA_HOST falls back", { OLLAMA_HOST: "" }, defaults],
    ["empty default model falls back", { LOCAL_LLM_DEFAULT_MODEL: "" }, defaults],
    [
      "fallback and overrides pass through",
      { LOCAL_LLM_FALLBACK_MODEL: "llama3", LOCAL_LLM_MODEL_OVERRIDES: '{"a":"b"}' },
      { ...defaults, fallbackModel: "llama3", overrides: { a: "b" } },
    ],
  ];
  for (const [name, env, want] of cases) {
    await t.test(name, () => assert.deepEqual(readConfig(env), want));
  }
});

function startMockOllama({
  models = [],
  chatContent = "mock reply",
  chatStatus = 200,
  chatRawBody = null,
  chatDelayMs = 0,
  tagsRawBody = null,
  pullStatus = 200,
  pullBody = { status: "success" },
} = {}) {
  const requests = [];
  const server = createServer((req, res) => {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      requests.push({ url: req.url, body });
      res.setHeader("content-type", "application/json");
      if (req.url === "/api/tags") {
        res.end(tagsRawBody ?? JSON.stringify({ models: models.map((name) => ({ name })) }));
      } else if (req.url === "/api/chat") {
        const send = () => {
          res.statusCode = chatStatus;
          res.end(
            chatRawBody ?? JSON.stringify({ message: { role: "assistant", content: chatContent } }),
          );
        };
        if (chatDelayMs > 0) {
          setTimeout(send, chatDelayMs);
        } else {
          send();
        }
      } else if (req.url === "/api/pull") {
        res.statusCode = pullStatus;
        res.end(JSON.stringify(pullBody));
      } else {
        res.statusCode = 404;
        res.end("{}");
      }
    });
  });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      resolve({
        host: `http://127.0.0.1:${server.address().port}`,
        requests,
        close: () =>
          new Promise((r) => {
            server.closeAllConnections?.();
            server.close(r);
          }),
      });
    });
  });
}

function startMcp(env) {
  const proc = spawn(process.execPath, [SERVER_PATH], {
    env: { ...process.env, ...env },
    stdio: ["pipe", "pipe", "inherit"],
  });
  const pending = new Map();
  const lines = [];
  const rl = createInterface({ input: proc.stdout });
  rl.on("line", (line) => {
    const msg = JSON.parse(line);
    lines.push(msg);
    const resolve = pending.get(msg.id);
    if (resolve) {
      pending.delete(msg.id);
      resolve(msg);
    }
  });
  let nextId = 1;
  return {
    lines,
    expect(id) {
      return new Promise((resolve) => pending.set(id, resolve));
    },
    request(method, params, terminator = "\n") {
      const id = nextId++;
      const reply = new Promise((resolve) => pending.set(id, resolve));
      proc.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}${terminator}`);
      return reply;
    },
    writeRaw(text) {
      proc.stdin.write(text);
    },
    endInput() {
      proc.stdin.end();
    },
    exited: once(proc, "exit").then(([code]) => code),
    async close() {
      proc.kill();
      await once(proc, "exit");
    },
  };
}

test("stdio protocol", async (t) => {
  const ollama = await startMockOllama({ models: ["qwen3:8b", "other-m"] });
  const mcp = startMcp({
    OLLAMA_HOST: ollama.host,
    LOCAL_LLM_DEFAULT_MODEL: "qwen3:8b",
    LOCAL_LLM_MODEL_OVERRIDES: '{"claude-sonnet-5":"other-m"}',
  });
  t.after(async () => {
    await mcp.close();
    await ollama.close();
  });

  await t.test("initialize negotiates the protocol version", async () => {
    const cases = [
      ["echoes 2025-06-18", { protocolVersion: "2025-06-18" }, "2025-06-18"],
      ["echoes 2025-03-26", { protocolVersion: "2025-03-26" }, "2025-03-26"],
      ["echoes 2024-11-05", { protocolVersion: "2024-11-05" }, "2024-11-05"],
      ["unknown falls back to latest", { protocolVersion: "1999-01-01" }, "2025-06-18"],
      ["missing params falls back", undefined, "2025-06-18"],
      ["non-string version falls back", { protocolVersion: 42 }, "2025-06-18"],
    ];
    for (const [name, params, want] of cases) {
      const reply = await mcp.request("initialize", params);
      assert.equal(reply.result.protocolVersion, want, name);
      assert.equal(reply.result.serverInfo.name, "local-llm-router", name);
    }
  });

  await t.test("tools/list returns the three tools", async () => {
    const reply = await mcp.request("tools/list", {});
    assert.deepEqual(
      reply.result.tools.map((tool) => tool.name),
      ["local_model_status", "local_model_provision", "local_model_run"],
    );
  });

  await t.test("ping returns an empty result", async () => {
    const reply = await mcp.request("ping", {});
    assert.deepEqual(reply.result, {});
  });

  await t.test("id 0 and string ids round-trip", async () => {
    const p0 = mcp.expect(0);
    const ps = mcp.expect("string-id");
    mcp.writeRaw('{"jsonrpc":"2.0","id":0,"method":"ping"}\n');
    mcp.writeRaw('{"jsonrpc":"2.0","id":"string-id","method":"ping"}\n');
    assert.deepEqual((await p0).result, {});
    assert.deepEqual((await ps).result, {});
  });

  await t.test("CRLF line endings are handled", async () => {
    const reply = await mcp.request("ping", {}, "\r\n");
    assert.deepEqual(reply.result, {});
  });

  await t.test("two messages coalesced into one write are both served", async () => {
    const p1 = mcp.expect(9001);
    const p2 = mcp.expect(9002);
    mcp.writeRaw(
      '{"jsonrpc":"2.0","id":9001,"method":"ping"}\n{"jsonrpc":"2.0","id":9002,"method":"ping"}\n',
    );
    assert.deepEqual((await p1).result, {});
    assert.deepEqual((await p2).result, {});
  });

  await t.test("local_model_status lists pulled models", async () => {
    const reply = await mcp.request("tools/call", { name: "local_model_status", arguments: {} });
    assert.equal(reply.result.isError, false);
    assert.deepEqual(reply.result.structuredContent.localModels, ["qwen3:8b", "other-m"]);
    assert.deepEqual(reply.result.structuredContent.modelOverrides, {
      "claude-sonnet-5": "other-m",
    });
  });

  await t.test("local_model_run applies the override map", async () => {
    const reply = await mcp.request("tools/call", {
      name: "local_model_run",
      arguments: { task: "review this", requestedModel: "claude-sonnet-5" },
    });
    assert.equal(reply.result.isError, false);
    assert.equal(reply.result.content[0].text, "mock reply");
    assert.equal(reply.result.structuredContent.selectedModel, "other-m");
    assert.equal(
      reply.result.structuredContent.resolution,
      "override:claude-sonnet-5->other-m",
    );
    const chat = ollama.requests.find((r) => r.url === "/api/chat");
    assert.ok(chat, "chat request reached ollama");
    const payload = JSON.parse(chat.body);
    assert.equal(payload.model, "other-m");
    assert.equal(payload.messages[1].content, "review this");
  });

  await t.test("profile selects the system prompt sent to ollama", async () => {
    const cases = [
      ["test-review", /test-focused reviewer/],
      ["security-review", /security-focused reviewer/],
      ["general", /concise engineering assistant/],
      ["not-a-real-profile", /concise engineering assistant/],
    ];
    for (const [profile, wantSystem] of cases) {
      const task = `profile-task-${profile}`;
      const reply = await mcp.request("tools/call", {
        name: "local_model_run",
        arguments: { task, profile },
      });
      assert.equal(reply.result.isError, false, profile);
      const chat = ollama.requests.find((r) => r.url === "/api/chat" && r.body.includes(task));
      assert.ok(chat, `chat request for profile ${profile}`);
      assert.match(JSON.parse(chat.body).messages[0].content, wantSystem, profile);
    }
  });

  await t.test("sampling params reach ollama; boundary and bogus values", async () => {
    const cases = [
      ["temperature 0 is kept, not defaulted", { temperature: 0 }, { temperature: 0, num_predict: 1024 }],
      ["temperature at max boundary", { temperature: 2 }, { temperature: 2, num_predict: 1024 }],
      ["maxTokens at min boundary", { maxTokens: 64 }, { temperature: 0.2, num_predict: 64 }],
      ["maxTokens at max boundary", { maxTokens: 8192 }, { temperature: 0.2, num_predict: 8192 }],
      ["non-integer maxTokens falls back to 1024", { maxTokens: 512.5 }, { temperature: 0.2, num_predict: 1024 }],
      ["string maxTokens falls back to 1024", { maxTokens: "500" }, { temperature: 0.2, num_predict: 1024 }],
      ["string temperature falls back to 0.2", { temperature: "hot" }, { temperature: 0.2, num_predict: 1024 }],
    ];
    let n = 0;
    for (const [name, extra, wantOptions] of cases) {
      const task = `sampling-task-${n++}`;
      const reply = await mcp.request("tools/call", {
        name: "local_model_run",
        arguments: { task, ...extra },
      });
      assert.equal(reply.result.isError, false, name);
      const chat = ollama.requests.find((r) => r.url === "/api/chat" && r.body.includes(task));
      assert.ok(chat, name);
      assert.deepEqual(JSON.parse(chat.body).options, wantOptions, name);
    }
  });

  await t.test("multiline and unicode tasks survive NDJSON transport", async () => {
    const task = 'line one\nline two — ünïcode 日本語 "quotes" \\backslash';
    const reply = await mcp.request("tools/call", {
      name: "local_model_run",
      arguments: { task },
    });
    assert.equal(reply.result.isError, false);
    const chat = ollama.requests.find(
      (r) => r.url === "/api/chat" && JSON.parse(r.body).messages[1].content === task,
    );
    assert.ok(chat, "task arrived byte-identical");
  });

  await t.test("local_model_run clamps out-of-range sampling params", async () => {
    const reply = await mcp.request("tools/call", {
      name: "local_model_run",
      arguments: { task: "t", temperature: 99, maxTokens: 1 },
    });
    assert.equal(reply.result.structuredContent.temperature, 2);
    assert.equal(reply.result.structuredContent.maxTokens, 64);
  });

  await t.test("local_model_run without a task is a tool error", async () => {
    const reply = await mcp.request("tools/call", {
      name: "local_model_run",
      arguments: { task: "   " },
    });
    assert.equal(reply.result.isError, true);
  });

  await t.test("oversized task is rejected before reaching ollama", async () => {
    const task = "x".repeat(200001);
    const reply = await mcp.request("tools/call", {
      name: "local_model_run",
      arguments: { task },
    });
    assert.equal(reply.result.isError, true);
    assert.match(reply.result.content[0].text, /exceeds 200000 characters/);
    assert.equal(reply.result.structuredContent.taskChars, 200001);
  });

  await t.test("tools/call without a name is a tool error", async () => {
    const reply = await mcp.request("tools/call", {});
    assert.equal(reply.result.isError, true);
  });

  await t.test("tools/call without arguments is a tool error per tool", async () => {
    for (const name of ["local_model_provision", "local_model_run"]) {
      const reply = await mcp.request("tools/call", { name });
      assert.equal(reply.result.isError, true, name);
    }
  });

  await t.test("local_model_provision rejects malformed model tags", async () => {
    const reply = await mcp.request("tools/call", {
      name: "local_model_provision",
      arguments: { model: "--insecure" },
    });
    assert.equal(reply.result.isError, true);
    const pulls = ollama.requests.filter((r) => r.url === "/api/pull");
    assert.equal(pulls.length, 0);
  });

  await t.test("local_model_provision rejects registry-host tags", async () => {
    const reply = await mcp.request("tools/call", {
      name: "local_model_provision",
      arguments: { model: "registry.example.com/user/model:v1.2" },
    });
    assert.equal(reply.result.isError, true);
    assert.match(reply.result.content[0].text, /official library tag/);
    const pulls = ollama.requests.filter((r) => r.url === "/api/pull");
    assert.equal(pulls.length, 0);
  });

  await t.test("local_model_provision pulls via the HTTP API", async () => {
    const reply = await mcp.request("tools/call", {
      name: "local_model_provision",
      arguments: { model: "qwen3:8b" },
    });
    assert.equal(reply.result.isError, false);
    const pull = ollama.requests.find((r) => r.url === "/api/pull");
    assert.ok(pull, "pull request reached ollama");
    assert.equal(JSON.parse(pull.body).model, "qwen3:8b");
  });

  await t.test("unknown tool is a tool error, not a crash", async () => {
    const reply = await mcp.request("tools/call", { name: "nope", arguments: {} });
    assert.equal(reply.result.isError, true);
  });

  await t.test("unknown method gets a JSON-RPC error", async () => {
    const reply = await mcp.request("no/such/method", {});
    assert.equal(reply.error.code, -32601);
  });

  await t.test("malformed line is ignored and the server keeps serving", async () => {
    mcp.writeRaw("this is not json\n\n");
    const reply = await mcp.request("ping", {});
    assert.deepEqual(reply.result, {});
  });

  await t.test("non-request JSON lines are ignored without output", async () => {
    const before = mcp.lines.length;
    const garbage = [
      "42",
      '"hi"',
      "null",
      "true",
      "[]",
      "{}",
      '[{"jsonrpc":"2.0","id":88,"method":"ping"}]',
      '{"jsonrpc":"1.0","id":77,"method":"ping"}',
    ];
    for (const raw of garbage) {
      mcp.writeRaw(`${raw}\n`);
    }
    const reply = await mcp.request("ping", {});
    assert.deepEqual(reply.result, {});
    assert.equal(mcp.lines.length, before + 1, "garbage lines must produce no responses");
  });

  await t.test("notifications produce no response and no side effects", async () => {
    const before = mcp.lines.length;
    const pullsBefore = ollama.requests.filter((r) => r.url === "/api/pull").length;
    mcp.writeRaw('{"jsonrpc":"2.0","method":"notifications/initialized"}\n');
    mcp.writeRaw('{"jsonrpc":"2.0","method":"ping"}\n');
    mcp.writeRaw('{"jsonrpc":"2.0","method":"tools/list"}\n');
    mcp.writeRaw(
      '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"local_model_provision","arguments":{"model":"sneaky:1b"}}}\n',
    );
    const reply = await mcp.request("ping", {});
    assert.deepEqual(reply.result, {});
    assert.equal(mcp.lines.length, before + 1, "id-less requests must not be answered");
    const pullsAfter = ollama.requests.filter((r) => r.url === "/api/pull").length;
    assert.equal(pullsAfter, pullsBefore, "id-less tools/call must not execute");
  });
});

test("ollama failure modes surface as tool errors and the server survives", async (t) => {
  const cases = [
    ["chat HTTP 500", { models: ["m1"], chatStatus: 500, chatRawBody: "boom" }, "local_model_run", { task: "t" }, /failed \(500\)/],
    ["chat returns empty content", { models: ["m1"], chatContent: "" }, "local_model_run", { task: "t" }, /empty response/],
    ["chat returns malformed JSON", { models: ["m1"], chatRawBody: "{not json" }, "local_model_run", { task: "t" }, /execution failed/],
    ["chat returns JSON without message", { models: ["m1"], chatRawBody: "{}" }, "local_model_run", { task: "t" }, /empty response/],
    ["tags returns malformed JSON", { tagsRawBody: "{not json" }, "local_model_status", {}, /status failed/],
    ["pull reports non-success status", { pullBody: { status: "pulling manifest" } }, "local_model_provision", { model: "m1:1b" }, /did not complete/],
    ["pull HTTP 500", { pullStatus: 500, pullBody: { error: "no space" } }, "local_model_provision", { model: "m1:1b" }, /failed \(500\)/],
  ];
  for (const [name, mockOpts, tool, args, wantText] of cases) {
    await t.test(name, async () => {
      const ollama = await startMockOllama(mockOpts);
      const mcp = startMcp({ OLLAMA_HOST: ollama.host, LOCAL_LLM_DEFAULT_MODEL: "m1" });
      try {
        const reply = await mcp.request("tools/call", { name: tool, arguments: args });
        assert.equal(reply.result.isError, true);
        assert.match(reply.result.content[0].text, wantText);
        const ping = await mcp.request("ping", {});
        assert.deepEqual(ping.result, {});
      } finally {
        await mcp.close();
        await ollama.close();
      }
    });
  }
});

test("tags payloads with missing or garbage model entries are filtered", async (t) => {
  const cases = [
    ["models key omitted", "{}", []],
    ["models null", '{"models":null}', []],
    [
      "garbage entries dropped",
      JSON.stringify({ models: [{ name: "" }, { name: 123 }, null, {}, { name: "ok-m" }] }),
      ["ok-m"],
    ],
  ];
  for (const [name, tagsRawBody, want] of cases) {
    await t.test(name, async () => {
      const ollama = await startMockOllama({ tagsRawBody });
      const mcp = startMcp({ OLLAMA_HOST: ollama.host });
      try {
        const reply = await mcp.request("tools/call", { name: "local_model_status", arguments: {} });
        assert.equal(reply.result.isError, false);
        assert.deepEqual(reply.result.structuredContent.localModels, want);
      } finally {
        await mcp.close();
        await ollama.close();
      }
    });
  }
});

test("a slow chat request does not block concurrent pings", async () => {
  const ollama = await startMockOllama({ models: ["m1"], chatDelayMs: 400 });
  const mcp = startMcp({ OLLAMA_HOST: ollama.host, LOCAL_LLM_DEFAULT_MODEL: "m1" });
  try {
    const order = [];
    const run = mcp
      .request("tools/call", { name: "local_model_run", arguments: { task: "slow" } })
      .then((r) => {
        order.push("run");
        return r;
      });
    const ping = mcp.request("ping", {}).then((r) => {
      order.push("ping");
      return r;
    });
    const [runReply] = await Promise.all([run, ping]);
    assert.equal(runReply.result.isError, false);
    assert.deepEqual(order, ["ping", "run"], "ping must not wait behind the chat call");
  } finally {
    await mcp.close();
    await ollama.close();
  }
});

test("server exits cleanly when stdin closes", async () => {
  const mcp = startMcp({ OLLAMA_HOST: "http://127.0.0.1:1" });
  const reply = await mcp.request("ping", {});
  assert.deepEqual(reply.result, {});
  mcp.endInput();
  assert.equal(await mcp.exited, 0);
});

test("stdin close drains an in-flight request before exiting", async () => {
  const ollama = await startMockOllama({ models: ["m1"], chatDelayMs: 200 });
  const mcp = startMcp({ OLLAMA_HOST: ollama.host, LOCAL_LLM_DEFAULT_MODEL: "m1" });
  try {
    const run = mcp.request("tools/call", { name: "local_model_run", arguments: { task: "t" } });
    mcp.endInput();
    const reply = await run;
    assert.equal(reply.result.isError, false);
    assert.equal(await mcp.exited, 0);
  } finally {
    await ollama.close();
  }
});

test("no models pulled is a tool error with guidance", async () => {
  const ollama = await startMockOllama({ models: [] });
  const mcp = startMcp({ OLLAMA_HOST: ollama.host });
  try {
    const reply = await mcp.request("tools/call", {
      name: "local_model_run",
      arguments: { task: "t" },
    });
    assert.equal(reply.result.isError, true);
    assert.match(reply.result.content[0].text, /local_model_provision/);
    assert.equal(reply.result.structuredContent.resolution, "none-available");
  } finally {
    await mcp.close();
    await ollama.close();
  }
});

test("ollama unreachable reports a status error instead of crashing", async () => {
  const ollama = await startMockOllama();
  await ollama.close();
  const mcp = startMcp({ OLLAMA_HOST: ollama.host });
  try {
    const reply = await mcp.request("tools/call", { name: "local_model_status", arguments: {} });
    assert.equal(reply.result.isError, true);
    const ping = await mcp.request("ping", {});
    assert.deepEqual(ping.result, {});
  } finally {
    await mcp.close();
  }
});
