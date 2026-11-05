# Agent class mapping (CANON-210) — status and G6 draft

Status: decisions recorded and registry rows written as STAGED. Not ratified. Ratification to ACTIVE needs a T0 action.

## 1. The "5→9 class map" is closed, not mapped

CANON-210 (Governed Agent Classes) defines **5** classes, not 9:

| Class | Tier | Source |
|---|---|---|
| SOVEREIGN | T0 | CANON-210 |
| ARCHITECT | T1 | CANON-210 |
| ADVISORY | T2 | CANON-210 |
| EXECUTOR | T3 | CANON-210 |
| OBSERVER | T4+ | CANON-210 |

The "9" came from conflating the class count with the **9-agent** `SFX_AGENT_REGISTRY`. The CANON-378 resolution log records this as the "agent-class-range conflation (9 classes → 5 classes / 9 agents)". This repo already matches the 5-class set (`packages/agents/src/contract.ts`, `SFX_AGENT_CLASSES`). There is no 5→9 mapping to draft.

Canon references in this doc, as cited by CANON-378 and the registry (read from the Airtable Canon ID Registry, not re-verified line by line):

- CANON-206 GovernanceContext
- CANON-207 Ratification Gate
- CANON-208 ProvenanceBinding
- CANON-209 PSE Overlay Integration
- CANON-210 Governed Agent Classes
- CANON-211 Constitutional Workflow Suite (`sfx_workflow_templates`, `sfx_canon_drafts`)

## 2. G6 — TRDEC agents → `sfx_agent_registry` (decided)

Established rules:

1. Canonical agent id is `A01`–`A13`. `TRDEC-` is applied only at the CCX boundary (ADR-0013, ruling 1).
2. Trust ladder: SOVEREIGN / RATIFIED / PROVISIONAL / UNTRUSTED (CANON-204). PROVISIONAL floor for A03 and A05 (ADR-0013, ruling 2).
3. WITNESS is non-invocable and has no executor.

Decisions (T0, 2026-11-05):

| Agent(s) | CANON-210 class | Tier | Basis |
|---|---|---|---|
| TRDEC-WITNESS | SOVEREIGN | 0 | T0 decision; `can_execute = false` (non-invocable) |
| A13 | ARCHITECT | 1 | T0 decision (overrides its SOVEREIGN trust state) |
| A01–A05 (CORE) | EXECUTOR | 3 | Group decision |
| A06–A12 (HARMONIC) | ADVISORY | 2 | Group decision; advisory output needs T1 triage |

Registration (written to `public.sfx_agent_registry` plus linked rows in `public.agents`):
- 14 rows, all `sfx_status = STAGED`. None can write Canon or ratify.
- `trust_ceiling` 0.500 and `trust_floor` 0.000 (table defaults; no per-tier values are established).
- `escalation_path` and `sfx_governed` left at defaults. Not decided.
- 9 pre-existing ACTIVE rows (T0:russ, T1:claude, four T2 agents, AUTO:001A, SYS:p5, SYS:p6) were not changed.

Open:
- Moving the 14 rows to ACTIVE needs a T0 action.
- Escalation paths and trust ceilings per agent need decisions before ratification.
- CANON-207 and CANON-209 full text was not verified.
