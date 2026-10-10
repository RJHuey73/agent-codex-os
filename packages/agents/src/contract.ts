import { ErrorType, RuntimeError } from "./errors.ts";
import { type AgentNode, isNodeType, toolNameOf } from "./types.ts";

/**
 * Enum labels observed in the live agent-codex-os DB (pg_enum, 2026-10-10).
 * NOTE: `sfx_agent_class` has 5 labels here; Canon cites 9 agent classes
 * (CANON-206–211). That conflict is flagged, not resolved, by this package.
 */
export const SFX_AGENT_CLASSES = ["SOVEREIGN", "ARCHITECT", "ADVISORY", "EXECUTOR", "OBSERVER"] as const;
export type SfxAgentClass = (typeof SFX_AGENT_CLASSES)[number];

export const SFX_AGENT_STATUSES = ["STAGED", "ACTIVE", "SUSPENDED", "RETIRED"] as const;
export type SfxAgentStatus = (typeof SFX_AGENT_STATUSES)[number];

/**
 * Blueprint §24.A AgentContract, extended with the governance fields the live
 * schema already carries on `agents` / `sfx_agent_registry`.
 */
export interface AgentContract {
  id: string;
  version: number;
  persona: { role: string; tone: string; constraints: readonly string[] };
  /** e.g. "plan", "execute", "evaluate", "tool:http_fetch". */
  capabilities: readonly string[];
  memory_scope: { writable: boolean; domains: readonly string[] };
  execution_policy_id: string;
  governance: {
    sfx_class: SfxAgentClass;
    authority_tier: number; // 0..5, CHECK-constrained in DB
    status: SfxAgentStatus;
    can_execute: boolean;
    trust_ceiling: number; // 0..1
    governed: boolean;
  };
}

/** Capability a node requires. Tool nodes require `tool:<name>`. */
export function requiredCapability(node: AgentNode): string {
  const override = node.config?.["required_capability"];
  if (typeof override === "string") return override;
  switch (node.type) {
    case "planner":
      return "plan";
    case "worker":
      return "execute";
    case "evaluator":
      return "evaluate";
    case "tool": {
      const tool = toolNameOf(node);
      if (!tool) throw new RuntimeError(ErrorType.DAG_INVALID, "tool node has no config.tool", { nodeId: node.id });
      return `tool:${tool}`;
    }
    default:
      throw new RuntimeError(ErrorType.UNKNOWN_NODE_TYPE, `Unknown node type: ${node.type}`, { nodeId: node.id });
  }
}

/** Structural validation; a malformed contract must not reach the gate. */
export function validateContract(c: AgentContract): void {
  const bad = (msg: string): never => {
    throw new RuntimeError(ErrorType.CONTRACT_INVALID, msg, { details: { agent_id: c.id } });
  };
  if (!c.id) bad("contract.id is required");
  if (!Number.isInteger(c.version) || c.version < 1) bad("contract.version must be a positive integer");
  const g = c.governance;
  if (!(SFX_AGENT_CLASSES as readonly string[]).includes(g.sfx_class)) bad(`unknown sfx_class ${g.sfx_class}`);
  if (!(SFX_AGENT_STATUSES as readonly string[]).includes(g.status)) bad(`unknown status ${g.status}`);
  if (!Number.isInteger(g.authority_tier) || g.authority_tier < 0 || g.authority_tier > 5) bad("authority_tier must be an integer 0..5");
  if (!(g.trust_ceiling >= 0 && g.trust_ceiling <= 1)) bad("trust_ceiling must be within 0..1");
}

/**
 * Blueprint §24.B runtime enforcement. Fails closed:
 *  - only ACTIVE agents execute (STAGED ≠ ratified),
 *  - `can_execute` must be true,
 *  - the node's required capability must be declared.
 */
export function enforceAgentContract(contract: AgentContract, node: AgentNode): void {
  const g = contract.governance;
  if (g.status !== "ACTIVE") {
    throw new RuntimeError(ErrorType.CAPABILITY_DENIED, `agent ${contract.id} is ${g.status}, not ACTIVE`, {
      nodeId: node.id,
      details: { agent_id: contract.id, status: g.status },
    });
  }
  if (!g.can_execute) {
    throw new RuntimeError(ErrorType.CAPABILITY_DENIED, `agent ${contract.id} may not execute`, {
      nodeId: node.id,
      details: { agent_id: contract.id, sfx_class: g.sfx_class },
    });
  }
  if (!isNodeType(node.type)) {
    throw new RuntimeError(ErrorType.UNKNOWN_NODE_TYPE, `Unknown node type: ${node.type}`, { nodeId: node.id });
  }
  const cap = requiredCapability(node);
  if (!contract.capabilities.includes(cap)) {
    throw new RuntimeError(ErrorType.CAPABILITY_DENIED, `capability ${cap} not granted to agent ${contract.id}`, {
      nodeId: node.id,
      details: { agent_id: contract.id, required: cap },
    });
  }
}
