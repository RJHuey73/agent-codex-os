# Agent class mapping (CANON-210) — status and G6 draft

Status: draft for review. Not ratified. Nothing here writes to Canon or to the database.

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

## 2. G6 — TRDEC agents → `sfx_agent_registry`

Established rules (already ratified or recorded):

1. **Canonical agent id is `A01`–`A13`.** `TRDEC-A01` is a derived CCX view (ADR-0013, ruling 1). The `TRDEC-` prefix is applied only at the CCX persistence boundary.
2. **Trust ladder** is SOVEREIGN / RATIFIED / PROVISIONAL / UNTRUSTED (CANON-204). PROVISIONAL is the floor for A03 and A05 (ADR-0013, ruling 2).
3. **WITNESS is non-invocable** and has no executor.

Current facts from the manifests (`tridecagon-agents/agents/*/*.manifest.json`):

| Manifest class | Agents | Trust state | Invocable |
|---|---|---|---|
| CORE | A01–A05 | A01, A02, A04 RATIFIED; A03, A05 PROVISIONAL | yes |
| HARMONIC | A06–A12 | RATIFIED | yes |
| HARMONIC | A13 | SOVEREIGN | yes |
| WITNESS | TRDEC-WITNESS | SOVEREIGN | no |

**Not established:** which CANON-210 class each TRDEC agent takes. The manifests carry CORE / HARMONIC / WITNESS, which is a Tridecagon grouping, not a CANON-210 class. Mapping each agent to a class is a decision, not a derivation.

`sfx_agent_registry` has 0 rows in the agent-codex-os project. Its column list was not checked in this pass.

### Decision needed (per agent, pick one per row)

| Agent | Option A | Option B |
|---|---|---|
| TRDEC-WITNESS | SOVEREIGN (matches SOVEREIGN/T0 tier) | leave unregistered (non-invocable) |
| A13 (SOVEREIGN trust) | SOVEREIGN | ARCHITECT |
| A01–A12 | one class per CORE/HARMONIC group | per-agent |

Proposed default if no decision is given: register WITNESS as SOVEREIGN, leave all other agents unregistered until assigned. This does not invent a class for any agent.
