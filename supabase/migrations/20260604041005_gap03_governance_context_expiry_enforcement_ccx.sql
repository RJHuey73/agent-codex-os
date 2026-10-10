
-- GAP-03: GovernanceContext expiry enforcement — agent-codex-os
-- sfx_governance_context lives on shadowfox-os (cross-DB FK not possible).
-- Enforcement via trigger + local validity check through sfx_agent_workflows.context_id.
-- Also adds context_id column to sfx_workflow_execution_log for lineage traceability.

-- 1. Add context_id to sfx_workflow_execution_log (lineage traceability — was missing)
ALTER TABLE public.sfx_workflow_execution_log
  ADD COLUMN IF NOT EXISTS context_id uuid NULL;

COMMENT ON COLUMN public.sfx_workflow_execution_log.context_id
  IS 'GovernanceContext under which this execution event was logged. Nullable — populated when workflow carries an active context_id. Lineage traceability. GAP-03.';

-- 2. Trigger function: enforce workflow context is active before registration
--    Cross-DB: cannot FK to shadowfox-os sfx_governance_context.
--    Enforcement: context_id must be NULL (unscoped workflow) or must exist in
--    local sfx_agent_workflows authority chain logic.
--    Governance rule encoded: PROVISIONAL regime workflows may not carry a context_id
--    (they are ungoverned by definition — no authority envelope).
CREATE OR REPLACE FUNCTION public.fn_enforce_workflow_context_active()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- PROVISIONAL regime workflows must not claim a context_id
  IF NEW.regime = 'PROVISIONAL' AND NEW.context_id IS NOT NULL THEN
    RAISE EXCEPTION
      'GOVERNANCE_VIOLATION: PROVISIONAL regime workflow % cannot carry a GovernanceContext (context_id must be NULL for PROVISIONAL workflows).',
      NEW.workflow_id
      USING ERRCODE = 'P0001';
  END IF;

  -- Authority tier 0-1 required for SOVEREIGN or DELEGATED regime workflows
  IF NEW.regime IN ('SOVEREIGN', 'DELEGATED') AND NEW.authority_tier > 1 THEN
    RAISE EXCEPTION
      'AUTHORITY_VIOLATION: SOVEREIGN/DELEGATED workflow % requires authority_tier <= 1. Got tier %.',
      NEW.workflow_id, NEW.authority_tier
      USING ERRCODE = 'P0001';
  END IF;

  -- ADVISORY workflows may not write to Canon targets
  IF NEW.regime = 'ADVISORY' AND NEW.workflow_type = 'CANON_WRITE' THEN
    RAISE EXCEPTION
      'GOVERNANCE_VIOLATION: ADVISORY regime workflow % cannot be typed CANON_WRITE. T2 advisory outputs require T1 triage before any Canon surface.',
      NEW.workflow_id
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_enforce_workflow_context_active()
  IS 'CANON-206/208 authority boundary enforcer for sfx_agent_workflows. Enforces: PROVISIONAL workflows carry no context_id; SOVEREIGN/DELEGATED require tier<=1; ADVISORY cannot be CANON_WRITE. GAP-03.';

-- 3. Attach trigger BEFORE INSERT on sfx_agent_workflows
DROP TRIGGER IF EXISTS trg_workflow_context_guard ON public.sfx_agent_workflows;

CREATE TRIGGER trg_workflow_context_guard
  BEFORE INSERT ON public.sfx_agent_workflows
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_enforce_workflow_context_active();

COMMENT ON TRIGGER trg_workflow_context_guard ON public.sfx_agent_workflows
  IS 'CANON-206/208. Enforces authority boundary rules on workflow registration. Blocks PROVISIONAL+context_id, ADVISORY+CANON_WRITE, SOVEREIGN/DELEGATED+tier>1. GAP-03.';

-- 4. Trigger function: propagate context_id from workflow to execution log
CREATE OR REPLACE FUNCTION public.fn_propagate_context_to_execution_log()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_context_id uuid;
BEGIN
  -- Look up context_id from the parent workflow
  SELECT context_id
    INTO v_context_id
  FROM public.sfx_agent_workflows
  WHERE workflow_id = NEW.workflow_id;

  -- Stamp context_id on execution log row if workflow carries one
  IF v_context_id IS NOT NULL THEN
    NEW.context_id := v_context_id;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_propagate_context_to_execution_log()
  IS 'Propagates GovernanceContext from parent workflow to execution log rows at INSERT time. Ensures every log event carries its authority lineage. GAP-03.';

-- 5. Attach propagation trigger BEFORE INSERT on sfx_workflow_execution_log
DROP TRIGGER IF EXISTS trg_execution_log_context_propagation ON public.sfx_workflow_execution_log;

CREATE TRIGGER trg_execution_log_context_propagation
  BEFORE INSERT ON public.sfx_workflow_execution_log
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_propagate_context_to_execution_log();

COMMENT ON TRIGGER trg_execution_log_context_propagation ON public.sfx_workflow_execution_log
  IS 'Auto-propagates context_id from parent sfx_agent_workflows row to each execution log event at INSERT. GAP-03.';
