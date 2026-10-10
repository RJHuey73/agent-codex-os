
-- ============================================================
-- PSE OVERLAY INTEGRATION — agent-codex-os
-- Binds GovernanceContext (CANON-206) + ProvenanceBinding (CANON-208)
-- to PSE execution substrate (runs, agent_messages)
-- T0 Auth: ={∆§/π}™ 2026-05-29 | Canon v9.28.0
-- ============================================================

-- ─────────────────────────────────────────
-- 1. RUNS — bind GovernanceContext + ProvenanceBinding
-- Primary PSE execution unit. Every run now carries full
-- authority envelope and regime classification.
-- ─────────────────────────────────────────

ALTER TABLE public.runs
    ADD COLUMN IF NOT EXISTS sfx_context_id       UUID,
    ADD COLUMN IF NOT EXISTS sfx_binding_id        UUID,
    ADD COLUMN IF NOT EXISTS sfx_authority_tier    INTEGER
                                CHECK (sfx_authority_tier BETWEEN 0 AND 5),
    ADD COLUMN IF NOT EXISTS sfx_regime            TEXT
                                CHECK (sfx_regime IN (
                                    'SOVEREIGN','DELEGATED','ADVISORY',
                                    'AUTOMATED','PROVISIONAL'
                                )),
    ADD COLUMN IF NOT EXISTS sfx_canon_version     TEXT,
    ADD COLUMN IF NOT EXISTS sfx_authority_chain   TEXT[],
    ADD COLUMN IF NOT EXISTS sfx_governed          BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.runs.sfx_context_id     IS 'FK → sfx_governance_context.context_id (shadowfox-os). GovernanceContext overlay (CANON-206).';
COMMENT ON COLUMN public.runs.sfx_binding_id     IS 'FK → sfx_provenance_bindings.binding_id (shadowfox-os). ProvenanceBinding overlay (CANON-208).';
COMMENT ON COLUMN public.runs.sfx_authority_tier IS 'Authority tier of run initiator: 0=T0, 1=T1, 2=T2, etc.';
COMMENT ON COLUMN public.runs.sfx_regime         IS 'Regime classification at run creation. Derived via deriveRegime() (CANON-208).';
COMMENT ON COLUMN public.runs.sfx_canon_version  IS 'Canon version active at run creation time.';
COMMENT ON COLUMN public.runs.sfx_authority_chain IS 'Ordered authority delegation chain e.g. [T0:russ, T1:claude, AUTO:001A].';
COMMENT ON COLUMN public.runs.sfx_governed       IS 'True when run was initiated with a bound GovernanceContext. Ungoverned runs are PROVISIONAL by default.';

-- Index for governed run queries
CREATE INDEX IF NOT EXISTS idx_runs_sfx_governed   ON public.runs(sfx_governed);
CREATE INDEX IF NOT EXISTS idx_runs_sfx_context    ON public.runs(sfx_context_id);
CREATE INDEX IF NOT EXISTS idx_runs_sfx_regime     ON public.runs(sfx_regime);

-- ─────────────────────────────────────────
-- 2. AGENT_MESSAGES — carry authority lineage
-- Inter-agent communications inherit regime from
-- their parent run's GovernanceContext.
-- ─────────────────────────────────────────

ALTER TABLE public.agent_messages
    ADD COLUMN IF NOT EXISTS sfx_context_id       UUID,
    ADD COLUMN IF NOT EXISTS sfx_authority_tier   INTEGER
                                CHECK (sfx_authority_tier BETWEEN 0 AND 5),
    ADD COLUMN IF NOT EXISTS sfx_regime           TEXT
                                CHECK (sfx_regime IN (
                                    'SOVEREIGN','DELEGATED','ADVISORY',
                                    'AUTOMATED','PROVISIONAL'
                                )),
    ADD COLUMN IF NOT EXISTS sfx_canon_version    TEXT,
    ADD COLUMN IF NOT EXISTS sfx_governed         BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.agent_messages.sfx_context_id     IS 'Inherited GovernanceContext from parent run. CANON-206.';
COMMENT ON COLUMN public.agent_messages.sfx_authority_tier IS 'Authority tier of message-emitting agent.';
COMMENT ON COLUMN public.agent_messages.sfx_regime         IS 'Regime inherited from run context. CANON-208.';
COMMENT ON COLUMN public.agent_messages.sfx_governed       IS 'True when message was emitted within a GovernanceContext envelope.';

CREATE INDEX IF NOT EXISTS idx_agent_messages_sfx_context  ON public.agent_messages(sfx_context_id);
CREATE INDEX IF NOT EXISTS idx_agent_messages_sfx_governed ON public.agent_messages(sfx_governed);

-- ─────────────────────────────────────────
-- 3. GOVERNANCE ENFORCEMENT VIEW
-- sfx_v_governed_runs: queryable surface showing all runs
-- with their full authority envelope. Ungoverned runs
-- surface as PROVISIONAL with NULL context.
-- ─────────────────────────────────────────

CREATE OR REPLACE VIEW public.sfx_v_governed_runs AS
SELECT
    r.id                    AS run_id,
    r.agent_id,
    r.status,
    r.sfx_governed,
    r.sfx_regime,
    r.sfx_authority_tier,
    r.sfx_authority_chain,
    r.sfx_context_id,
    r.sfx_binding_id,
    r.sfx_canon_version,
    CASE
        WHEN r.sfx_governed = false THEN 'UNGOVERNED — PROVISIONAL'
        WHEN r.sfx_regime IS NULL   THEN 'GOVERNED — REGIME UNSET'
        ELSE r.sfx_regime
    END                     AS effective_regime,
    r.created_at,
    r.completed_at
FROM public.runs r;

COMMENT ON VIEW public.sfx_v_governed_runs IS
    'PSE governance surface. All runs with authority envelope. '
    'Ungoverned runs surface as PROVISIONAL. CANON-206/208.';

-- ─────────────────────────────────────────
-- 4. CONSTITUTIONAL ENFORCEMENT TRIGGER
-- Runs that touch Canon targets must be governed.
-- PROVISIONAL regime blocked from Canon-bound outputs.
-- ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_enforce_pse_governance()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_canon_target TEXT;
BEGIN
    -- Extract canon_target from output if present
    v_canon_target := NEW.output->>'canon_target';

    -- If output declares a Canon target, run must be governed
    IF v_canon_target IS NOT NULL AND (NEW.sfx_governed = false OR NEW.sfx_governed IS NULL) THEN
        RAISE EXCEPTION
            'CONSTITUTIONAL_VIOLATION: Run % targets Canon [%] but has no GovernanceContext. '
            'Bind a context before executing Canon-bound runs.',
            NEW.id, v_canon_target
            USING ERRCODE = 'P0001';
    END IF;

    -- PROVISIONAL regime cannot write to Canon
    IF v_canon_target IS NOT NULL AND NEW.sfx_regime = 'PROVISIONAL' THEN
        RAISE EXCEPTION
            'CONSTITUTIONAL_VIOLATION: Run % is PROVISIONAL regime and cannot commit to Canon [%]. '
            'Advance regime via RatificationGate (CANON-207) before Canon writes.',
            NEW.id, v_canon_target
            USING ERRCODE = 'P0001';
    END IF;

    -- Default ungoverned runs to PROVISIONAL regime
    IF NEW.sfx_governed = false AND NEW.sfx_regime IS NULL THEN
        NEW.sfx_regime := 'PROVISIONAL';
        NEW.sfx_canon_version := 'v9.28.0';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_pse_governance_enforcement
    BEFORE INSERT OR UPDATE ON public.runs
    FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_pse_governance();
