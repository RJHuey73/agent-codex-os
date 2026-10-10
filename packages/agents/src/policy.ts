import { ErrorType, RuntimeError } from "./errors.ts";
import { type AgentNode, type ToolRegistry, toolNameOf } from "./types.ts";

/** Blueprint §35 sandbox descriptor + §37.D policy limits. */
export interface ExecutionPolicy {
  id: string;
  permissions: {
    allow_network: boolean;
    allow_tools: readonly string[];
    allow_llm: boolean;
    allow_storage: boolean;
  };
  budget: {
    max_cost_usd: number;
    max_tokens: number;
    max_runtime_ms: number;
  };
  limits: {
    max_nodes_per_dag: number;
    node_timeout_ms: number;
  };
}

/** Deny-by-default sandbox (blueprint §35.A), with conservative budgets. */
export const DEFAULT_POLICY: ExecutionPolicy = Object.freeze({
  id: "default-sandbox",
  permissions: Object.freeze({ allow_network: false, allow_tools: Object.freeze([]), allow_llm: true, allow_storage: false }),
  budget: Object.freeze({ max_cost_usd: 0.05, max_tokens: 20_000, max_runtime_ms: 30_000 }),
  limits: Object.freeze({ max_nodes_per_dag: 25, node_timeout_ms: 10_000 }),
});

export interface RunUsage {
  cost_usd: number;
  tokens: number;
  started_at_ms: number;
}

export interface Violation {
  type: ErrorType;
  rule: string;
  message: string;
}

export interface PolicyDecision {
  allowed: boolean;
  violations: Violation[];
}

const LLM_NODE_TYPES: ReadonlySet<string> = new Set(["planner", "worker", "evaluator"]);

/**
 * Pure evaluation of one node against the policy and the run's usage so far.
 * Collects every violation rather than stopping at the first, so audits see
 * the full picture (blueprint §35.D `violations jsonb`).
 */
export function evaluatePolicy(
  node: AgentNode,
  usage: RunUsage,
  policy: ExecutionPolicy,
  tools: ToolRegistry,
  nowMs: number,
): PolicyDecision {
  const v: Violation[] = [];
  const p = policy.permissions;

  if (LLM_NODE_TYPES.has(node.type) && !p.allow_llm) {
    v.push({ type: ErrorType.POLICY_VIOLATION, rule: "allow_llm", message: "LLM calls are not permitted" });
  }

  if (node.type === "tool") {
    const name = toolNameOf(node);
    const spec = name === undefined ? undefined : tools.get(name);
    if (name === undefined || spec === undefined) {
      // Unregistered tools are rejected: "Tool registry only" (§35 threat model).
      v.push({ type: ErrorType.POLICY_VIOLATION, rule: "tool_registry", message: `tool ${name ?? "<none>"} is not registered` });
    } else {
      if (!p.allow_tools.includes(name)) {
        v.push({ type: ErrorType.POLICY_VIOLATION, rule: "allow_tools", message: `tool ${name} not allowed by policy` });
      }
      if (spec.network && !p.allow_network) {
        v.push({ type: ErrorType.POLICY_VIOLATION, rule: "allow_network", message: `tool ${name} needs network access` });
      }
      if (spec.storage && !p.allow_storage) {
        v.push({ type: ErrorType.POLICY_VIOLATION, rule: "allow_storage", message: `tool ${name} needs storage access` });
      }
    }
  }

  const b = policy.budget;
  if (usage.cost_usd >= b.max_cost_usd) {
    v.push({ type: ErrorType.BUDGET_EXCEEDED, rule: "max_cost_usd", message: `cost ${usage.cost_usd} >= ${b.max_cost_usd}` });
  }
  if (usage.tokens >= b.max_tokens) {
    v.push({ type: ErrorType.BUDGET_EXCEEDED, rule: "max_tokens", message: `tokens ${usage.tokens} >= ${b.max_tokens}` });
  }
  if (nowMs - usage.started_at_ms >= b.max_runtime_ms) {
    v.push({ type: ErrorType.TIMEOUT, rule: "max_runtime_ms", message: `run exceeded ${b.max_runtime_ms}ms` });
  }

  return { allowed: v.length === 0, violations: v };
}

/**
 * Blueprint §42.B pre-execution gate, evaluated before EVERY node (not once
 * per run), so budget consumed by earlier nodes is enforced.
 */
export function preExecute(
  node: AgentNode,
  usage: RunUsage,
  policy: ExecutionPolicy,
  tools: ToolRegistry,
  nowMs: number,
): void {
  const decision = evaluatePolicy(node, usage, policy, tools, nowMs);
  const first = decision.violations[0];
  if (first) {
    throw new RuntimeError(first.type, `POLICY_BLOCKED: ${first.message}`, {
      nodeId: node.id,
      details: { policy_id: policy.id, violations: decision.violations },
    });
  }
}
