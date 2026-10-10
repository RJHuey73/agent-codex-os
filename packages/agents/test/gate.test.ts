import { test } from "node:test";
import assert from "node:assert/strict";
import { ErrorType, RuntimeError, enforceAgentContract, evaluatePolicy, preExecute, validateContract } from "../src/index.ts";
import { contract, policy, tools } from "./fixtures.ts";

const fresh = { cost_usd: 0, tokens: 0, started_at_ms: 0 };
const isType = (t: string) => (e: unknown) => e instanceof RuntimeError && e.type === t;

test("contract: only ACTIVE, executable agents with the capability pass", () => {
  enforceAgentContract(contract(), { id: "n", type: "worker" });
  for (const status of ["STAGED", "SUSPENDED", "RETIRED"] as const) {
    assert.throws(() => enforceAgentContract(contract({ status }), { id: "n", type: "worker" }), isType(ErrorType.CAPABILITY_DENIED));
  }
  assert.throws(() => enforceAgentContract(contract({ can_execute: false }), { id: "n", type: "worker" }), isType(ErrorType.CAPABILITY_DENIED));
  assert.throws(() => enforceAgentContract(contract({}, ["plan"]), { id: "n", type: "worker" }), isType(ErrorType.CAPABILITY_DENIED));
  assert.throws(
    () => enforceAgentContract(contract(), { id: "n", type: "tool", config: { tool: "http_fetch" } }),
    isType(ErrorType.CAPABILITY_DENIED),
  );
  assert.throws(() => enforceAgentContract(contract(), { id: "n", type: "network" }), isType(ErrorType.UNKNOWN_NODE_TYPE));
});

test("contract: structural validation rejects out-of-domain governance values", () => {
  validateContract(contract());
  assert.throws(() => validateContract(contract({ authority_tier: 6 })), isType(ErrorType.CONTRACT_INVALID));
  assert.throws(() => validateContract(contract({ trust_ceiling: 1.5 })), isType(ErrorType.CONTRACT_INVALID));
  assert.throws(() => validateContract(contract({ sfx_class: "WIZARD" as never })), isType(ErrorType.CONTRACT_INVALID));
});

test("policy: deny-by-default tools, network and storage", () => {
  const net = { id: "t", type: "tool", config: { tool: "http_fetch" } };
  const d = evaluatePolicy(net, fresh, policy(), tools, 0);
  assert.equal(d.allowed, false);
  assert.deepEqual(d.violations.map((v) => v.rule).sort(), ["allow_network", "allow_tools"]);

  const allowed = evaluatePolicy(net, fresh, policy({ permissions: { allow_tools: ["http_fetch"], allow_network: true } }), tools, 0);
  assert.equal(allowed.allowed, true);

  const unregistered = evaluatePolicy({ id: "t", type: "tool", config: { tool: "rm_rf" } }, fresh, policy({ permissions: { allow_tools: ["rm_rf"] } }), tools, 0);
  assert.deepEqual(unregistered.violations.map((v) => v.rule), ["tool_registry"]);

  assert.equal(evaluatePolicy({ id: "w", type: "worker" }, fresh, policy({ permissions: { allow_llm: false } }), tools, 0).allowed, false);
});

test("preExecute enforces cost, token and runtime budgets", () => {
  const w = { id: "w", type: "worker" };
  assert.throws(() => preExecute(w, { ...fresh, cost_usd: 0.05 }, policy(), tools, 0), isType(ErrorType.BUDGET_EXCEEDED));
  assert.throws(() => preExecute(w, { ...fresh, tokens: 20_000 }, policy(), tools, 0), isType(ErrorType.BUDGET_EXCEEDED));
  assert.throws(() => preExecute(w, fresh, policy(), tools, 30_000), isType(ErrorType.TIMEOUT));
  preExecute(w, { ...fresh, cost_usd: 0.049 }, policy(), tools, 29_999);
});
