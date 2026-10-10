/**
 * Node shape mirrors live `public.nodes` (agent-codex-os, observed 2026-10-10):
 * id uuid, type text, config jsonb, depends_on uuid[].
 * Node types are the blueprint §5 set; anything else is rejected at validation.
 */
export const NODE_TYPES = ["planner", "worker", "tool", "evaluator"] as const;
export type NodeType = (typeof NODE_TYPES)[number];

export interface AgentNode {
  id: string;
  type: string;
  config?: Record<string, unknown>;
  depends_on?: readonly string[];
}

/** Declared side effects of a registered tool (blueprint §15 + §35 threat model). */
export interface ToolSpec {
  name: string;
  network: boolean;
  storage: boolean;
}

export type ToolRegistry = ReadonlyMap<string, ToolSpec>;

export function isNodeType(t: string): t is NodeType {
  return (NODE_TYPES as readonly string[]).includes(t);
}

export function toolNameOf(node: AgentNode): string | undefined {
  const t = node.config?.["tool"];
  return typeof t === "string" ? t : undefined;
}
