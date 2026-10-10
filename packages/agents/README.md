# @agent-codex-os/agents

Runtime enforcement layer for Agent Codex OS — the gap named in the blueprint's
Appendix B ("structural OS without a semantic enforcement layer").

| Module | Closes | Behaviour |
|---|---|---|
| `errors.ts` | §41.C error taxonomy | `ErrorType` + `RuntimeError` (`type`, `node_id`, `retryable`, `details`). Governance denials are never retryable. |
| `dag.ts` | §14 DAG engine | Kahn topological sort, deterministic. **Fails closed** on cycles (`DAG_CYCLE`), unknown deps, duplicate ids, oversize DAGs — the blueprint's `topoSort` accepted all of these. |
| `contract.ts` | §24 AgentContract | Contract carries the live `agents`/`sfx_agent_registry` governance fields. Only `ACTIVE` + `can_execute` agents run; each node's capability must be declared. |
| `policy.ts` | §35 sandbox, §42 `preExecute()` | Deny-by-default sandbox. Gate runs **before every node**, so budget spent by earlier nodes is enforced. Collects all violations for audit. |
| `runtime.ts` | §19/§21 logging + errors | Sequential governed `runDAG`. Emits `events`-shaped rows via an injected `EventSink`; an unloggable run does not proceed. Never throws — always returns a `RunResult`. |

## Boundaries

- No Supabase, LLM, or network client in this package. Persistence (`EventSink`)
  and node execution (`NodeHandlers`) are injected by the caller.
- Sequential only (blueprint §18: no parallelism until the DAG is stable).
- Not yet built: the `AgentMessage` bus (Appendix B gap 3), prompt versioning,
  cost metering against `usage_logs`.

## Commands

```bash
npm install        # dev deps only (typescript, @types/node)
npm test           # node --test, type-stripped TS, no build step (Node >= 22.18)
npm run typecheck
```
