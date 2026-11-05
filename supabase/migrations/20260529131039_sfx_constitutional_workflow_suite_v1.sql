
-- ============================================================
-- SFX CONSTITUTIONAL WORKFLOW SUITE v1.0
-- Defines the three canonical workflow types:
--   WF-001: CANON_WRITE  (T2 research → T1 synthesis → T0 ratify)
--   WF-002: RESEARCH     (multi-T2 → T1 triage)
--   WF-003: MARKET_SWEEP (AUTO:001A → T2 → T1 → T0 review)
-- CANON-211 | v9.28.0 | ={∆§/π}™
-- ============================================================

-- ─────────────────────────────────────────
-- WORKFLOW SUITE REGISTRY
-- Named, versioned workflow templates that
-- instantiate sfx_agent_workflows rows at runtime.
-- ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sfx_workflow_templates (
    template_id     TEXT PRIMARY KEY,           -- e.g. 'WF-001'
    template_name   TEXT NOT NULL UNIQUE,
    workflow_type   TEXT NOT NULL CHECK (workflow_type IN (
                        'CANON_WRITE','RESEARCH','EXECUTION',
                        'RATIFICATION','AUDIT','MARKET_SWEEP'
                    )),
    description     TEXT,
    step_schema     JSONB NOT NULL,             -- ordered step definitions
    initiator_class TEXT NOT NULL,              -- minimum initiator class required
    requires_t0     BOOLEAN NOT NULL DEFAULT false,
    canon_version   TEXT NOT NULL DEFAULT 'v9.28.0',
    status          TEXT NOT NULL DEFAULT 'ACTIVE'
                        CHECK (status IN ('STAGED','ACTIVE','DEPRECATED'))
);

COMMENT ON TABLE public.sfx_workflow_templates IS
    'Named constitutional workflow templates. step_schema defines the ordered '
    'agent steps, roles, and authority requirements. CANON-211.';

ALTER TABLE public.sfx_workflow_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_anon_workflow_templates ON public.sfx_workflow_templates FOR ALL TO anon USING (false);

-- ─────────────────────────────────────────
-- WORKFLOW EXECUTION LOG
-- Immutable record of every workflow execution event.
-- Written by the workflow engine as steps complete.
-- ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sfx_workflow_execution_log (
    log_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id     UUID NOT NULL REFERENCES public.sfx_agent_workflows(workflow_id) ON DELETE CASCADE,
    step_sequence   INTEGER NOT NULL,
    agent_handle    TEXT NOT NULL,
    event_type      TEXT NOT NULL CHECK (event_type IN (
                        'STEP_STARTED','STEP_COMPLETED','STEP_FAILED',
                        'STEP_ESCALATED','STEP_SKIPPED',
                        'WORKFLOW_CREATED','WORKFLOW_COMPLETED',
                        'WORKFLOW_FAILED','WORKFLOW_CANCELLED',
                        'DEBATE_INPUT_RECEIVED','SYNTHESIS_COMPLETE',
                        'CANON_DRAFT_READY','RATIFICATION_REQUESTED',
                        'RATIFICATION_GRANTED','RATIFICATION_REJECTED'
                    )),
    payload         JSONB,
    canon_version   TEXT NOT NULL DEFAULT 'v9.28.0',
    logged_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.sfx_workflow_execution_log IS
    'Immutable execution event log for all constitutional workflows. CANON-211.';

CREATE INDEX IF NOT EXISTS idx_wf_exec_log_workflow ON public.sfx_workflow_execution_log(workflow_id);
CREATE INDEX IF NOT EXISTS idx_wf_exec_log_event    ON public.sfx_workflow_execution_log(event_type);

ALTER TABLE public.sfx_workflow_execution_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_anon_wf_exec_log ON public.sfx_workflow_execution_log FOR ALL TO anon USING (false);

-- ─────────────────────────────────────────
-- GOVERNED CANON DRAFTS
-- Output surface for CANON_WRITE workflows.
-- A draft is a Canon entry candidate that has
-- passed T1 synthesis and is awaiting T0 ratification.
-- ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sfx_canon_drafts (
    draft_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id         UUID NOT NULL REFERENCES public.sfx_agent_workflows(workflow_id) ON DELETE RESTRICT,
    canon_candidate_id  TEXT NOT NULL,              -- e.g. 'SFX-CANON-212'
    title               TEXT NOT NULL,
    cluster             TEXT NOT NULL,
    body                TEXT NOT NULL,              -- full Canon entry text
    -- Evidence trail from debate inputs
    research_inputs     JSONB,                      -- T2 agent outputs (triaged)
    t1_synthesis_notes  TEXT,                       -- T1 triage annotation
    dependency_refs     TEXT[],                     -- Canon IDs this depends on
    conflict_flags      TEXT[],                     -- any identified conflicts
    -- Governance provenance
    context_id          UUID,                       -- → sfx_governance_context
    gate_id             UUID,                       -- → sfx_ratification_gate (shadowfox-os)
    synthesized_by      TEXT NOT NULL DEFAULT 'T1:claude',
    canon_version       TEXT NOT NULL DEFAULT 'v9.28.0',
    -- Lifecycle
    draft_status        TEXT NOT NULL DEFAULT 'DRAFT' CHECK (draft_status IN (
                            'DRAFT',                -- T1 assembling
                            'READY_FOR_RATIFICATION', -- T1 complete, awaiting T0
                            'RATIFIED',             -- T0 approved
                            'REJECTED',             -- T0 rejected
                            'SUPERSEDED'            -- replaced by later draft
                        )),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    ratified_at         TIMESTAMPTZ,
    UNIQUE (canon_candidate_id)
);

COMMENT ON TABLE public.sfx_canon_drafts IS
    'Governed Canon draft surface. Output of CANON_WRITE workflows. '
    'Bridges T1 synthesis to T0 ratification. CANON-211.';

CREATE INDEX IF NOT EXISTS idx_canon_drafts_status   ON public.sfx_canon_drafts(draft_status);
CREATE INDEX IF NOT EXISTS idx_canon_drafts_workflow  ON public.sfx_canon_drafts(workflow_id);

ALTER TABLE public.sfx_canon_drafts ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_anon_canon_drafts ON public.sfx_canon_drafts FOR ALL TO anon USING (false);

-- ─────────────────────────────────────────
-- SEED: THREE CANONICAL WORKFLOW TEMPLATES
-- ─────────────────────────────────────────

INSERT INTO public.sfx_workflow_templates
    (template_id, template_name, workflow_type, description,
     initiator_class, requires_t0, step_schema)
VALUES
(
  'WF-001',
  'Canon Write — Standard (T2→T1→P6→T0)',
  'CANON_WRITE',
  'Standard Canon write workflow. T2 agents research the topic, T1 triages and synthesizes a Canon draft, P6 validates, T0 ratifies.',
  'ARCHITECT',
  true,
  '[
    {"sequence": 0, "agent_handle": "T1:claude",     "step_role": "INITIATOR",   "can_escalate": false},
    {"sequence": 1, "agent_handle": "T2:perplexity", "step_role": "RESEARCHER",  "can_escalate": true, "escalate_to": "T1:claude"},
    {"sequence": 2, "agent_handle": "T2:gemini",     "step_role": "RESEARCHER",  "can_escalate": true, "escalate_to": "T1:claude"},
    {"sequence": 3, "agent_handle": "T1:claude",     "step_role": "SYNTHESIZER", "can_escalate": true, "escalate_to": "T0:russ"},
    {"sequence": 4, "agent_handle": "SYS:p6",        "step_role": "VALIDATOR",   "can_escalate": true, "escalate_to": "T1:claude"},
    {"sequence": 5, "agent_handle": "T0:russ",       "step_role": "RATIFIER",    "can_escalate": false}
  ]'::jsonb
),
(
  'WF-002',
  'Research — Multi-T2 Synthesis',
  'RESEARCH',
  'Research-only workflow. Multiple T2 agents gather evidence, T1 synthesizes. No Canon write. Output is a research summary.',
  'ARCHITECT',
  false,
  '[
    {"sequence": 0, "agent_handle": "T1:claude",     "step_role": "INITIATOR",   "can_escalate": false},
    {"sequence": 1, "agent_handle": "T2:perplexity", "step_role": "RESEARCHER",  "can_escalate": true, "escalate_to": "T1:claude"},
    {"sequence": 2, "agent_handle": "T2:gemini",     "step_role": "RESEARCHER",  "can_escalate": true, "escalate_to": "T1:claude"},
    {"sequence": 3, "agent_handle": "T2:chatgpt",    "step_role": "RESEARCHER",  "can_escalate": true, "escalate_to": "T1:claude"},
    {"sequence": 4, "agent_handle": "T1:claude",     "step_role": "SYNTHESIZER", "can_escalate": true, "escalate_to": "T0:russ"}
  ]'::jsonb
),
(
  'WF-003',
  'Market Sweep — Weekly Intelligence',
  'MARKET_SWEEP',
  'Weekly market intelligence cycle. AUTO:001A triggers, T2:perplexity researches live market data, T1 synthesizes, T0 reviews output.',
  'EXECUTOR',
  false,
  '[
    {"sequence": 0, "agent_handle": "AUTO:001A",     "step_role": "INITIATOR",   "can_escalate": false},
    {"sequence": 1, "agent_handle": "T2:perplexity", "step_role": "RESEARCHER",  "can_escalate": true, "escalate_to": "T1:claude"},
    {"sequence": 2, "agent_handle": "T1:claude",     "step_role": "SYNTHESIZER", "can_escalate": true, "escalate_to": "T0:russ"},
    {"sequence": 3, "agent_handle": "T0:russ",       "step_role": "OBSERVER",    "can_escalate": false}
  ]'::jsonb
)
ON CONFLICT (template_id) DO NOTHING;
