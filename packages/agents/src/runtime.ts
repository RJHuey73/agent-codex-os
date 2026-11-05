import { type AgentContract, enforceAgentContract, validateContract } from "./contract.ts";
import { topoSort } from "./dag.ts";
import { ErrorType, RuntimeError, classifyError } from "./errors.ts";
import { type ExecutionPolicy, type RunUsage, preExecute } from "./policy.ts";
import { type AgentNode, type NodeType, type ToolRegistry } from "./types.ts";

/** Row shape of live `public.events` (node_id is text since migration 008). */
export interface RunEvent {
  run_id: string;
  node_id: string | null;
  event_type: RunEventType;
  payload: Record<string, unknown>;
}

export type RunEventType = "run_start" | "start" | "blocked" | "success" | "error" | "run_completed" | "run_failed";

/** Persistence is injected; this package never talks to Supabase itself. */
export interface EventSink {
  emit(event: RunEvent): Promise<void>;
}

export interface NodeContext {
  readonly input: unknown;
  /** Outputs of already-completed nodes, keyed by node id. */
  readonly results: Readonly<Record<string, unknown>>;
  readonly signal: AbortSignal;
}

export interface NodeOutcome {
  output: unknown;
  cost_usd?: number;
  tokens?: number;
}

export type NodeHandler = (node: AgentNode, ctx: NodeContext) => Promise<NodeOutcome>;
export type NodeHandlers = Readonly<Partial<Record<NodeType, NodeHandler>>>;

export interface RunDagOptions {
  runId: string;
  nodes: readonly AgentNode[];
  input: unknown;
  contract: AgentContract;
  policy: ExecutionPolicy;
  tools: ToolRegistry;
  handlers: NodeHandlers;
  sink: EventSink;
  now?: () => number;
}

export interface RunResult {
  run_id: string;
  status: "completed" | "failed";
  results: Record<string, unknown>;
  usage: { cost_usd: number; tokens: number; duration_ms: number };
  error: ReturnType<RuntimeError["toJSON"]> | null;
}

function nodeFailureType(node: AgentNode): ErrorType {
  return node.type === "tool" ? ErrorType.TOOL_FAILURE : ErrorType.LLM_FAILURE;
}

async function withTimeout<T>(run: (signal: AbortSignal) => Promise<T>, ms: number, nodeId: string): Promise<T> {
  const ctrl = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      ctrl.abort();
      reject(new RuntimeError(ErrorType.TIMEOUT, `node ${nodeId} exceeded ${ms}ms`, { nodeId, details: { timeout_ms: ms } }));
    }, Math.max(0, ms));
  });
  try {
    return await Promise.race([run(ctrl.signal), timeout]);
  } finally {
    clearTimeout(timer);
  }
}

function checkMeter(value: number | undefined, field: string, nodeId: string): number {
  if (value === undefined) return 0;
  if (!Number.isFinite(value) || value < 0) {
    throw new RuntimeError(ErrorType.INTERNAL, `handler reported invalid ${field}: ${value}`, { nodeId });
  }
  return value;
}

/**
 * Governed DAG execution (blueprint §14/§19/§21/§42, closing the Appendix B
 * enforcement gaps). Sequential by design: "Do NOT parallelize until DAG is
 * stable" (§18). Fails fast on the first error; never throws — the outcome is
 * always returned as a RunResult so the caller can persist `runs` faithfully.
 */
export async function runDAG(opts: RunDagOptions): Promise<RunResult> {
  const now = opts.now ?? Date.now;
  const usage: RunUsage = { cost_usd: 0, tokens: 0, started_at_ms: now() };
  const results: Record<string, unknown> = {};
  const { runId, sink, policy } = opts;

  const finish = async (error: RuntimeError | null): Promise<RunResult> => {
    const result: RunResult = {
      run_id: runId,
      status: error ? "failed" : "completed",
      results,
      usage: { cost_usd: usage.cost_usd, tokens: usage.tokens, duration_ms: now() - usage.started_at_ms },
      error: error ? error.toJSON() : null,
    };
    try {
      await sink.emit({
        run_id: runId,
        node_id: null,
        event_type: error ? "run_failed" : "run_completed",
        payload: { usage: result.usage, error: result.error },
      });
    } catch (e) {
      if (!error) {
        const obs = classifyError(e, ErrorType.OBSERVABILITY_FAILURE);
        return { ...result, status: "failed", error: obs.toJSON() };
      }
      // Already failing: the original error is the one worth reporting.
    }
    return result;
  };

  const emit = async (event: RunEvent): Promise<void> => {
    try {
      await sink.emit(event);
    } catch (e) {
      // Execution must be observable (§12): an unloggable run does not proceed.
      throw new RuntimeError(ErrorType.OBSERVABILITY_FAILURE, `event sink failed: ${e instanceof Error ? e.message : String(e)}`, {
        ...(event.node_id === null ? {} : { nodeId: event.node_id }),
        cause: e,
      });
    }
  };

  let ordered: AgentNode[];
  try {
    validateContract(opts.contract);
    ordered = topoSort(opts.nodes, policy.limits.max_nodes_per_dag);
    await emit({
      run_id: runId,
      node_id: null,
      event_type: "run_start",
      payload: { agent_id: opts.contract.id, contract_version: opts.contract.version, policy_id: policy.id, order: ordered.map((n) => n.id) },
    });
  } catch (e) {
    return finish(classifyError(e, ErrorType.INTERNAL));
  }

  for (const node of ordered) {
    // Gate: identity contract, then policy/budget. Nothing runs ungated.
    try {
      enforceAgentContract(opts.contract, node);
      preExecute(node, usage, policy, opts.tools, now());
    } catch (e) {
      const err = classifyError(e, ErrorType.POLICY_VIOLATION, node.id);
      try {
        await emit({ run_id: runId, node_id: node.id, event_type: "blocked", payload: err.toJSON() });
      } catch (obs) {
        return finish(classifyError(obs, ErrorType.OBSERVABILITY_FAILURE, node.id));
      }
      return finish(err);
    }

    const handler = opts.handlers[node.type as NodeType];
    const started = now();
    try {
      if (!handler) {
        throw new RuntimeError(ErrorType.UNKNOWN_NODE_TYPE, `no handler registered for node type ${node.type}`, { nodeId: node.id });
      }
      await emit({ run_id: runId, node_id: node.id, event_type: "start", payload: { type: node.type } });

      const remainingRun = policy.budget.max_runtime_ms - (started - usage.started_at_ms);
      const timeoutMs = Math.min(policy.limits.node_timeout_ms, remainingRun);
      const ctxResults = Object.freeze({ ...results });
      const outcome = await withTimeout((signal) => handler(node, { input: opts.input, results: ctxResults, signal }), timeoutMs, node.id);

      const cost = checkMeter(outcome.cost_usd, "cost_usd", node.id);
      const tokens = checkMeter(outcome.tokens, "tokens", node.id);
      usage.cost_usd += cost;
      usage.tokens += tokens;
      results[node.id] = outcome.output;

      await emit({
        run_id: runId,
        node_id: node.id,
        event_type: "success",
        payload: { duration_ms: now() - started, cost_usd: cost, tokens },
      });

      // Post-check: the last node can also blow the budget.
      if (usage.cost_usd > policy.budget.max_cost_usd || usage.tokens > policy.budget.max_tokens) {
        throw new RuntimeError(ErrorType.BUDGET_EXCEEDED, "run budget exceeded", {
          nodeId: node.id,
          details: { cost_usd: usage.cost_usd, tokens: usage.tokens, budget: policy.budget },
        });
      }
    } catch (e) {
      const err = classifyError(e, nodeFailureType(node), node.id);
      if (err.type !== ErrorType.OBSERVABILITY_FAILURE) {
        try {
          await emit({ run_id: runId, node_id: node.id, event_type: "error", payload: { ...err.toJSON(), duration_ms: now() - started } });
        } catch (obs) {
          return finish(classifyError(obs, ErrorType.OBSERVABILITY_FAILURE, node.id));
        }
      }
      return finish(err);
    }
  }

  return finish(null);
}
