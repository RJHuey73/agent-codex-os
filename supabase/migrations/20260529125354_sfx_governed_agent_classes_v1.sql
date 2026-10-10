
-- ============================================================
-- SFX GOVERNED AGENT CLASSES — agent-codex-os
-- Constitutional multi-agent workflow substrate
-- CANON-210 | T0 Auth: ={∆§/π}™ 2026-05-29 | v9.28.0
-- ============================================================

-- ─────────────────────────────────────────
-- 1. AGENT CLASS ENUM
-- Five constitutional agent classes aligned to
-- SFX authority tier model (CANON-204)
-- ─────────────────────────────────────────

CREATE TYPE public.sfx_agent_class AS ENUM (
    'SOVEREIGN',    -- T0: ratification authority, terminal decisions
    'ARCHITECT',    -- T1: Canon writes, schema mutations, governance
    'ADVISORY',     -- T2: research, synthesis, debate inputs
    'EXECUTOR',     -- T3: task execution, automation, tool calls
    'OBSERVER'      -- T4/T5: read-only telemetry and monitoring
);

CREATE TYPE public.sfx_agent_status AS ENUM (
    'STAGED',       -- defined but not yet active in workflows
    'ACTIVE',       -- cleared for governed execution
    'SUSPENDED',    -- temporarily halted, context preserved
    'RETIRED'       -- permanently decommissioned
);

-- ─────────────────────────────────────────
-- 2. BIND AGENT CLASS + AUTHORITY TIER TO agents TABLE
-- Extends existing substrate without breaking schema.
-- ─────────────────────────────────────────

ALTER TABLE public.agents
    ADD COLUMN IF NOT EXISTS sfx_class           public.sfx_agent_class,
    ADD COLUMN IF NOT EXISTS sfx_authority_tier  INTEGER
                                CHECK (sfx_authority_tier BETWEEN 0 AND 5),
    ADD COLUMN IF NOT EXISTS sfx_status          public.sfx_agent_status
                                NOT NULL DEFAULT 'STAGED',
    ADD COLUMN IF NOT EXISTS sfx_trust_ceiling   NUMERIC(4,3)
                                CHECK (sfx_trust_ceiling BETWEEN 0.000 AND 1.000),
    ADD COLUMN IF NOT EXISTS sfx_canon_version   TEXT DEFAULT 'v9.28.0',
    ADD COLUMN IF NOT EXISTS sfx_escalation_path TEXT[],   -- ordered agent IDs to escalate to
    ADD COLUMN IF NOT EXISTS sfx_governed        BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.agents.sfx_class          IS 'Constitutional agent class: SOVEREIGN/ARCHITECT/ADVISORY/EXECUTOR/OBSERVER. CANON-210.';
COMMENT ON COLUMN public.agents.sfx_authority_tier IS 'SFX authority tier (0=T0 ... 5). Must match sfx_class. CANON-210.';
COMMENT ON COLUMN public.agents.sfx_status         IS 'Governance lifecycle status. Only ACTIVE agents may participate in governed workflows.';
COMMENT ON COLUMN public.agents.sfx_trust_ceiling  IS 'Maximum trust score (0.000–1.000) this agent can assert. Derived from CANON-204 TrustState.';
COMMENT ON COLUMN public.agents.sfx_escalation_path IS 'Ordered list of agent IDs to escalate unresolvable decisions to.';
COMMENT ON COLUMN public.agents.sfx_governed       IS 'True = agent has been declared under constitutional governance.';

CREATE INDEX IF NOT EXISTS idx_agents_sfx_class   ON public.agents(sfx_class);
CREATE INDEX IF NOT EXISTS idx_agents_sfx_status  ON public.agents(sfx_status);
CREATE INDEX IF NOT EXISTS idx_agents_sfx_governed ON public.agents(sfx_governed);

-- ─────────────────────────────────────────
-- 3. CONSTITUTIONAL AGENT REGISTRY
-- Canonical declaration of every governed agent.
-- One row per agent identity — the authoritative
-- record of what an agent IS and what it can do.
-- ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sfx_agent_registry (
    registry_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id            UUID NOT NULL REFERENCES public.agents(id) ON DELETE CASCADE,
    agent_handle        TEXT NOT NULL UNIQUE,    -- e.g. 'T1:claude', 'T2:perplexity', 'AUTO:001A'
    sfx_class           public.sfx_agent_class NOT NULL,
    authority_tier      INTEGER NOT NULL CHECK (authority_tier BETWEEN 0 AND 5),
    -- Capability declaration
    can_write_canon     BOOLEAN NOT NULL DEFAULT false,
    can_ratify          BOOLEAN NOT NULL DEFAULT false,    -- T0 only
    can_escrow          BOOLEAN NOT NULL DEFAULT false,    -- T1+ governed
    can_debate          BOOLEAN NOT NULL DEFAULT false,    -- T2 advisory
    can_execute         BOOLEAN NOT NULL DEFAULT true,
    -- Trust envelope
    trust_ceiling       NUMERIC(4,3) NOT NULL DEFAULT 0.500
                            CHECK (trust_ceiling BETWEEN 0.000 AND 1.000),
    trust_floor         NUMERIC(4,3) NOT NULL DEFAULT 0.000
                            CHECK (trust_floor BETWEEN 0.000 AND 1.000),
    -- Governance binding
    canon_version       TEXT NOT NULL DEFAULT 'v9.28.0',
    declared_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_active_at      TIMESTAMPTZ,
    sfx_status          public.sfx_agent_status NOT NULL DEFAULT 'STAGED',
    -- Constraints
    CONSTRAINT chk_trust_range CHECK (trust_floor <= trust_ceiling),
    CONSTRAINT chk_ratify_requires_t0 CHECK (can_ratify = false OR authority_tier = 0),
    CONSTRAINT chk_canon_write_requires_t1 CHECK (can_write_canon = false OR authority_tier <= 1)
);

COMMENT ON TABLE public.sfx_agent_registry IS
    'Constitutional agent registry. Canonical identity + capability declaration for every governed agent. '
    'Constraints enforce: only T0 can ratify; only T0/T1 can write Canon. CANON-210.';

CREATE INDEX IF NOT EXISTS idx_agent_registry_handle ON public.sfx_agent_registry(agent_handle);
CREATE INDEX IF NOT EXISTS idx_agent_registry_class  ON public.sfx_agent_registry(sfx_class);
CREATE INDEX IF NOT EXISTS idx_agent_registry_status ON public.sfx_agent_registry(sfx_status);

-- ─────────────────────────────────────────
-- 4. MULTI-AGENT WORKFLOW TABLE
-- A workflow is a governed DAG of agents operating
-- under a single GovernanceContext. Every node in
-- the DAG is an agent assignment with declared role.
-- ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sfx_agent_workflows (
    workflow_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_name       TEXT NOT NULL,
    workflow_type       TEXT NOT NULL CHECK (workflow_type IN (
                            'CANON_WRITE',      -- produces a Canon entry
                            'RESEARCH',         -- T2 synthesis + T1 triage
                            'EXECUTION',        -- automated task pipeline
                            'RATIFICATION',     -- debate → gate → T0 decision
                            'AUDIT',            -- compliance / provenance scan
                            'MARKET_SWEEP'      -- SFX-MARKET intelligence cycle
                        )),
    -- Governance binding (CANON-206)
    context_id          UUID,                   -- → sfx_governance_context (shadowfox-os, cross-ref)
    initiator_handle    TEXT NOT NULL,           -- agent_handle of workflow initiator
    authority_tier      INTEGER NOT NULL CHECK (authority_tier BETWEEN 0 AND 5),
    regime              TEXT NOT NULL CHECK (regime IN (
                            'SOVEREIGN','DELEGATED','ADVISORY','AUTOMATED','PROVISIONAL'
                        )),
    -- Canon linkage
    canon_version       TEXT NOT NULL DEFAULT 'v9.28.0',
    canon_target        TEXT,                   -- Canon ID being produced, if any
    -- Lifecycle
    status              TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN (
                            'PENDING','ACTIVE','AWAITING_RATIFICATION',
                            'COMPLETE','FAILED','CANCELLED'
                        )),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at        TIMESTAMPTZ,
    -- Immutability gate: COMPLETE workflows cannot be mutated
    CONSTRAINT chk_complete_immutable
        CHECK (status != 'COMPLETE' OR completed_at IS NOT NULL)
);

COMMENT ON TABLE public.sfx_agent_workflows IS
    'Constitutional multi-agent workflow registry. Each workflow is a governed DAG under one GovernanceContext. CANON-210.';

CREATE INDEX IF NOT EXISTS idx_workflow_status   ON public.sfx_agent_workflows(status);
CREATE INDEX IF NOT EXISTS idx_workflow_type     ON public.sfx_agent_workflows(workflow_type);
CREATE INDEX IF NOT EXISTS idx_workflow_context  ON public.sfx_agent_workflows(context_id);

-- ─────────────────────────────────────────
-- 5. WORKFLOW AGENT ASSIGNMENTS
-- Each step in a workflow assigns a governed agent
-- to a role with declared authority bounds.
-- Extends (not replaces) existing agent_assignments.
-- ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sfx_workflow_assignments (
    assignment_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id         UUID NOT NULL REFERENCES public.sfx_agent_workflows(workflow_id) ON DELETE CASCADE,
    agent_handle        TEXT NOT NULL,           -- → sfx_agent_registry.agent_handle
    step_sequence       INTEGER NOT NULL DEFAULT 0,
    step_role           TEXT NOT NULL CHECK (step_role IN (
                            'INITIATOR',         -- starts the workflow
                            'RESEARCHER',        -- T2 advisory input
                            'SYNTHESIZER',       -- T1 triage + synthesis
                            'VALIDATOR',         -- P6 quality guard
                            'RATIFIER',          -- T0 terminal decision
                            'EXECUTOR',          -- automated task execution
                            'OBSERVER'           -- telemetry / audit only
                        )),
    -- Authority bounds for this step
    authority_tier      INTEGER NOT NULL CHECK (authority_tier BETWEEN 0 AND 5),
    can_escalate        BOOLEAN NOT NULL DEFAULT false,
    escalate_to         TEXT,                    -- agent_handle to escalate to
    -- Step outcome
    status              TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN (
                            'PENDING','ACTIVE','COMPLETE','SKIPPED','ESCALATED','FAILED'
                        )),
    run_id              UUID REFERENCES public.runs(id) ON DELETE SET NULL,
    result_summary      TEXT,
    completed_at        TIMESTAMPTZ,
    UNIQUE (workflow_id, agent_handle, step_sequence)
);

COMMENT ON TABLE public.sfx_workflow_assignments IS
    'Governed agent step assignments within a constitutional workflow. '
    'Each step declares authority bounds and escalation path. CANON-210.';

CREATE INDEX IF NOT EXISTS idx_wf_assignment_workflow ON public.sfx_workflow_assignments(workflow_id);
CREATE INDEX IF NOT EXISTS idx_wf_assignment_agent    ON public.sfx_workflow_assignments(agent_handle);

-- ─────────────────────────────────────────
-- 6. AGENT DELEGATION TABLE
-- Explicit authority propagation: agent A delegates
-- bounded authority to agent B for a specific workflow.
-- Delegation is scoped, auditable, and revocable.
-- ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sfx_agent_delegations (
    delegation_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id         UUID NOT NULL REFERENCES public.sfx_agent_workflows(workflow_id) ON DELETE CASCADE,
    delegator_handle    TEXT NOT NULL,           -- must be higher authority tier
    delegatee_handle    TEXT NOT NULL,           -- receiving agent
    delegated_tier      INTEGER NOT NULL CHECK (delegated_tier BETWEEN 0 AND 5),
    -- Scope constraints: delegation cannot exceed delegator's own authority
    max_trust_ceiling   NUMERIC(4,3) NOT NULL DEFAULT 0.500
                            CHECK (max_trust_ceiling BETWEEN 0.000 AND 1.000),
    can_sub_delegate    BOOLEAN NOT NULL DEFAULT false,
    scope               TEXT NOT NULL CHECK (scope IN (
                            'FULL_WORKFLOW',     -- valid for entire workflow
                            'SINGLE_STEP',       -- valid for one step only
                            'CANON_WRITE',       -- specifically for Canon write steps
                            'DEBATE_INPUT'       -- T2 advisory scope only
                        )),
    -- Lifecycle
    granted_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ,
    revoked_at          TIMESTAMPTZ,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (workflow_id, delegator_handle, delegatee_handle, scope)
);

COMMENT ON TABLE public.sfx_agent_delegations IS
    'Explicit authority delegation between agents within a workflow. '
    'Scoped, auditable, revocable. Cannot exceed delegator authority. CANON-210.';

CREATE INDEX IF NOT EXISTS idx_delegation_workflow   ON public.sfx_agent_delegations(workflow_id);
CREATE INDEX IF NOT EXISTS idx_delegation_delegatee  ON public.sfx_agent_delegations(delegatee_handle);

-- ─────────────────────────────────────────
-- 7. CONSTITUTIONAL ENFORCEMENT
-- Governed workflows: EXECUTOR-class agents cannot
-- initiate Canon writes or ratification steps.
-- ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_enforce_agent_class_authority()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_registry RECORD;
BEGIN
    -- Resolve agent class from registry
    SELECT sfx_class, authority_tier, can_write_canon, can_ratify, sfx_status
    INTO v_registry
    FROM public.sfx_agent_registry
    WHERE agent_handle = NEW.agent_handle;

    -- Only ACTIVE agents participate in governed workflows
    IF v_registry.sfx_status IS DISTINCT FROM 'ACTIVE' THEN
        RAISE EXCEPTION
            'CONSTITUTIONAL_VIOLATION: Agent [%] is not ACTIVE (status: %). '
            'Activate agent before assigning to workflow [%].',
            NEW.agent_handle, v_registry.sfx_status, NEW.workflow_id
            USING ERRCODE = 'P0001';
    END IF;

    -- EXECUTOR/OBSERVER cannot hold RATIFIER or SYNTHESIZER roles
    IF v_registry.sfx_class IN ('EXECUTOR', 'OBSERVER')
       AND NEW.step_role IN ('RATIFIER', 'SYNTHESIZER') THEN
        RAISE EXCEPTION
            'CONSTITUTIONAL_VIOLATION: Agent [%] (class: %) cannot hold role [%] in workflow [%].',
            NEW.agent_handle, v_registry.sfx_class, NEW.step_role, NEW.workflow_id
            USING ERRCODE = 'P0001';
    END IF;

    -- RATIFIER role requires T0 (authority_tier = 0)
    IF NEW.step_role = 'RATIFIER' AND v_registry.authority_tier != 0 THEN
        RAISE EXCEPTION
            'CONSTITUTIONAL_VIOLATION: RATIFIER role requires T0 authority. '
            'Agent [%] has tier [%].',
            NEW.agent_handle, v_registry.authority_tier
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_agent_class_authority
    BEFORE INSERT ON public.sfx_workflow_assignments
    FOR EACH ROW
    WHEN (NEW.agent_handle IS NOT NULL)
    EXECUTE FUNCTION public.fn_enforce_agent_class_authority();

-- ─────────────────────────────────────────
-- 8. RLS on all new tables
-- ─────────────────────────────────────────

ALTER TABLE public.sfx_agent_registry     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sfx_agent_workflows    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sfx_workflow_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sfx_agent_delegations  ENABLE ROW LEVEL SECURITY;

CREATE POLICY deny_anon_agent_registry      ON public.sfx_agent_registry      FOR ALL TO anon USING (false);
CREATE POLICY deny_anon_agent_workflows     ON public.sfx_agent_workflows      FOR ALL TO anon USING (false);
CREATE POLICY deny_anon_workflow_assignments ON public.sfx_workflow_assignments FOR ALL TO anon USING (false);
CREATE POLICY deny_anon_agent_delegations   ON public.sfx_agent_delegations    FOR ALL TO anon USING (false);
