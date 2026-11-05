import { test } from "node:test";
import assert from "node:assert/strict";
import { ErrorType, type NodeHandlers, runDAG } from "../src/index.ts";
import { MemorySink, contract, policy, tools } from "./fixtures.ts";

const nodes = [
  { id: "plan", type: "planner" },
  { id: "work", type: "worker", depends_on: ["plan"] },
  { id: "log", type: "tool", config: { tool: "log" }, depends_on: ["work"] },
  { id: "eval", type: "evaluator", depends_on: ["log"] },
];

const ok: NodeHandlers = {
  planner: async () => ({ output: ["t1"], cost_usd: 0.001, tokens: 100 }),
  worker: async (_n, ctx) => ({ output: `did ${JSON.stringify(ctx.results["plan"])}`, cost_usd: 0.001, tokens: 100 }),
  tool: async () => ({ output: { ok: true } }),
  evaluator: async () => ({ output: { score: 0.9, passed: true }, cost_usd: 0.001, tokens: 50 }),
};

const base = (sink: MemorySink, over: Partial<Parameters<typeof runDAG>[0]> = {}) => ({
  runId: "run-1",
  nodes,
  input: { task: "test" },
  contract: contract(),
  policy: policy(),
  tools,
  handlers: ok,
  sink,
  ...over,
});

test("happy path: every node gated, logged, and its output threaded forward", async () => {
  const sink = new MemorySink();
  const r = await runDAG(base(sink));
  assert.equal(r.status, "completed");
  assert.equal(r.error, null);
  assert.equal(r.results["work"], 'did ["t1"]');
  assert.equal(r.usage.tokens, 250);
  assert.deepEqual(sink.types(), [
    "run_start",
    "start:plan", "success:plan",
    "start:work", "success:work",
    "start:log", "success:log",
    "start:eval", "success:eval",
    "run_completed",
  ]);
});

test("a STAGED agent executes nothing", async () => {
  const sink = new MemorySink();
  let called = false;
  const r = await runDAG(base(sink, { contract: contract({ status: "STAGED" }), handlers: { ...ok, planner: async () => { called = true; return { output: null }; } } }));
  assert.equal(called, false);
  assert.equal(r.status, "failed");
  assert.equal(r.error?.type, ErrorType.CAPABILITY_DENIED);
  assert.deepEqual(sink.types(), ["run_start", "blocked:plan", "run_failed"]);
});

test("policy block stops the run before the offending node runs", async () => {
  const sink = new MemorySink();
  const r = await runDAG(base(sink, { policy: policy({ permissions: { allow_tools: [] } }) }));
  assert.equal(r.error?.type, ErrorType.POLICY_VIOLATION);
  assert.equal(r.error?.node_id, "log");
  assert.ok(!("log" in r.results));
  assert.ok(sink.types().includes("blocked:log"));
});

test("budget consumed by earlier nodes blocks later ones", async () => {
  const sink = new MemorySink();
  const pricey: NodeHandlers = { ...ok, planner: async () => ({ output: [], cost_usd: 0.06 }) };
  const r = await runDAG(base(sink, { handlers: pricey }));
  assert.equal(r.error?.type, ErrorType.BUDGET_EXCEEDED);
  assert.equal(r.error?.node_id, "plan");
});

test("node timeout is classified TIMEOUT and the signal is aborted", async () => {
  const sink = new MemorySink();
  let aborted = false;
  const slow: NodeHandlers = {
    ...ok,
    planner: (_n, ctx) => new Promise((res) => {
      ctx.signal.addEventListener("abort", () => { aborted = true; });
      setTimeout(() => res({ output: null }), 200);
    }),
  };
  const r = await runDAG(base(sink, { handlers: slow, policy: policy({ limits: { node_timeout_ms: 20 } }) }));
  assert.equal(r.error?.type, ErrorType.TIMEOUT);
  assert.equal(aborted, true);
});

test("handler errors are classified by node kind", async () => {
  const sink = new MemorySink();
  const r = await runDAG(base(sink, { handlers: { ...ok, tool: async () => { throw new Error("boom"); } } }));
  assert.equal(r.error?.type, ErrorType.TOOL_FAILURE);
  assert.equal(r.error?.retryable, true);
  assert.ok(sink.types().includes("error:log"));

  const r2 = await runDAG(base(new MemorySink(), { handlers: { ...ok, worker: async () => { throw new Error("rate limited"); } } }));
  assert.equal(r2.error?.type, ErrorType.LLM_FAILURE);
});

test("cycles and missing handlers fail closed", async () => {
  const cyc = await runDAG(base(new MemorySink(), { nodes: [{ id: "a", type: "worker", depends_on: ["b"] }, { id: "b", type: "worker", depends_on: ["a"] }] }));
  assert.equal(cyc.error?.type, ErrorType.DAG_CYCLE);

  const { evaluator: _drop, ...partial } = ok;
  const missing = await runDAG(base(new MemorySink(), { handlers: partial }));
  assert.equal(missing.error?.type, ErrorType.UNKNOWN_NODE_TYPE);
});

test("an unobservable run does not proceed", async () => {
  const sink = new MemorySink();
  sink.failOn = "start";
  let called = false;
  const r = await runDAG(base(sink, { handlers: { ...ok, planner: async () => { called = true; return { output: null }; } } }));
  assert.equal(called, false);
  assert.equal(r.error?.type, ErrorType.OBSERVABILITY_FAILURE);
});

test("invalid meter values from a handler fail the run", async () => {
  const r = await runDAG(base(new MemorySink(), { handlers: { ...ok, planner: async () => ({ output: null, cost_usd: -1 }) } }));
  assert.equal(r.error?.type, ErrorType.INTERNAL);
});
