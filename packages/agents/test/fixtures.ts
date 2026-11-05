import type { AgentContract, EventSink, ExecutionPolicy, RunEvent, ToolRegistry } from "../src/index.ts";
import { DEFAULT_POLICY } from "../src/index.ts";

export function contract(over: Partial<AgentContract["governance"]> = {}, capabilities = ["plan", "execute", "evaluate", "tool:log"]): AgentContract {
  return {
    id: "agent-1",
    version: 1,
    persona: { role: "worker", tone: "neutral", constraints: [] },
    capabilities,
    memory_scope: { writable: false, domains: [] },
    execution_policy_id: "default-sandbox",
    governance: {
      sfx_class: "EXECUTOR",
      authority_tier: 2,
      status: "ACTIVE",
      can_execute: true,
      trust_ceiling: 0.5,
      governed: true,
      ...over,
    },
  };
}

export function policy(over: { permissions?: Partial<ExecutionPolicy["permissions"]>; budget?: Partial<ExecutionPolicy["budget"]>; limits?: Partial<ExecutionPolicy["limits"]> } = {}): ExecutionPolicy {
  return {
    id: "test-policy",
    permissions: { ...DEFAULT_POLICY.permissions, allow_tools: ["log"], ...over.permissions },
    budget: { ...DEFAULT_POLICY.budget, ...over.budget },
    limits: { ...DEFAULT_POLICY.limits, ...over.limits },
  };
}

export const tools: ToolRegistry = new Map([
  ["log", { name: "log", network: false, storage: false }],
  ["http_fetch", { name: "http_fetch", network: true, storage: false }],
]);

export class MemorySink implements EventSink {
  events: RunEvent[] = [];
  failOn: string | undefined;
  async emit(e: RunEvent): Promise<void> {
    if (this.failOn === e.event_type) throw new Error("sink down");
    this.events.push(e);
  }
  types(): string[] {
    return this.events.map((e) => (e.node_id ? `${e.event_type}:${e.node_id}` : e.event_type));
  }
}
