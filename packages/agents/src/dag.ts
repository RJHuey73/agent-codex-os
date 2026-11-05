import { ErrorType, RuntimeError } from "./errors.ts";
import type { AgentNode } from "./types.ts";

/**
 * Validate a DAG and return a deterministic topological order (Kahn's
 * algorithm, ties broken by input order).
 *
 * Replaces blueprint §14.B `topoSort`, which silently accepted cycles and
 * dangling dependencies. Here both fail closed.
 */
export function topoSort(nodes: readonly AgentNode[], maxNodes = Infinity): AgentNode[] {
  if (nodes.length > maxNodes) {
    throw new RuntimeError(ErrorType.DAG_INVALID, `DAG has ${nodes.length} nodes; limit is ${maxNodes}`, {
      details: { node_count: nodes.length, max_nodes: maxNodes },
    });
  }

  const index = new Map<string, number>();
  nodes.forEach((n, i) => {
    if (!n.id) throw new RuntimeError(ErrorType.DAG_INVALID, `node at position ${i} has no id`);
    if (index.has(n.id)) throw new RuntimeError(ErrorType.DAG_INVALID, `duplicate node id ${n.id}`, { nodeId: n.id });
    index.set(n.id, i);
  });

  const indegree = new Array<number>(nodes.length).fill(0);
  const dependents: number[][] = nodes.map(() => []);
  nodes.forEach((n, i) => {
    for (const dep of new Set(n.depends_on ?? [])) {
      const j = index.get(dep);
      if (j === undefined) {
        throw new RuntimeError(ErrorType.DAG_INVALID, `node ${n.id} depends on unknown node ${dep}`, {
          nodeId: n.id,
          details: { missing: dep },
        });
      }
      dependents[j]!.push(i);
      indegree[i]!++;
    }
  });

  // Ready set kept sorted by input position for determinism.
  const ready: number[] = [];
  indegree.forEach((d, i) => {
    if (d === 0) ready.push(i);
  });
  const order: AgentNode[] = [];
  while (ready.length > 0) {
    ready.sort((a, b) => a - b);
    const i = ready.shift()!;
    order.push(nodes[i]!);
    for (const k of dependents[i]!) {
      if (--indegree[k]! === 0) ready.push(k);
    }
  }

  if (order.length !== nodes.length) {
    const cycle = nodes.filter((_, i) => indegree[i]! > 0).map((n) => n.id);
    throw new RuntimeError(ErrorType.DAG_CYCLE, `DAG contains a cycle among: ${cycle.join(", ")}`, {
      details: { nodes: cycle },
    });
  }
  return order;
}
