
-- GAP-04: P6 Escrow Pipeline — agent-codex-os
-- Wires sfx_canon_drafts CPPK bind event → escrow submission on shadowfox-os.
-- Uses pg_net HTTP POST to fn_submit_to_escrow via Supabase RPC endpoint.
-- Also adds draft_status transition guard and escrow_submitted flag.

-- 1. Add escrow tracking columns to sfx_canon_drafts
ALTER TABLE public.sfx_canon_drafts
  ADD COLUMN IF NOT EXISTS escrow_id       uuid        NULL,
  ADD COLUMN IF NOT EXISTS escrow_status   text        NULL
    CHECK (escrow_status IN ('PENDING', 'SUBMITTED', 'BLOCKED', 'RELEASED', 'REJECTED')),
  ADD COLUMN IF NOT EXISTS veritas_verdict text        NULL
    CHECK (veritas_verdict IN ('PASS', 'FAIL', 'ERROR', 'ALREADY_ESCROWED', 'ALREADY_RELEASED'));

COMMENT ON COLUMN public.sfx_canon_drafts.escrow_id
  IS 'UUID of the escrow row on shadowfox-os sfx_p6_escrow_payloads. Null until CPPK bind triggers escrow submission. GAP-04.';
COMMENT ON COLUMN public.sfx_canon_drafts.escrow_status
  IS 'Last known escrow pipeline status. Set by trg_canon_draft_escrow_gate on sfx_binding_id update. GAP-04.';
COMMENT ON COLUMN public.sfx_canon_drafts.veritas_verdict
  IS 'VERITAS evaluation verdict returned from fn_submit_to_escrow. GAP-04.';

-- 2. Trigger function: on sfx_binding_id attach, submit draft to P6 escrow via pg_net
--    Requires: pg_net extension (pre-installed on agent-codex-os)
--    Target: shadowfox-os Supabase RPC endpoint for fn_submit_to_escrow
CREATE OR REPLACE FUNCTION public.fn_canon_draft_escrow_gate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_sfx_url      text;
  v_sfx_key      text;
  v_payload      jsonb;
  v_draft_body   text;
BEGIN
  -- Only fire when sfx_binding_id transitions from NULL → non-NULL
  -- and draft is not already RATIFIED or PROVISIONAL
  IF NEW.sfx_binding_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF OLD.sfx_binding_id IS NOT NULL THEN
    RETURN NEW; -- already bound, don't re-submit
  END IF;
  IF NEW.draft_status IN ('RATIFIED', 'DEPRECATED') THEN
    RETURN NEW; -- terminal states, skip
  END IF;

  -- Read runtime config from sfx_system_config
  SELECT
    (notes::jsonb ->> 'sfx_supabase_url'),
    (notes::jsonb ->> 'sfx_service_role_key')
  INTO v_sfx_url, v_sfx_key
  FROM public.sfx_system_config
  LIMIT 1;

  -- Fallback: if config not present, log and pass through without blocking
  IF v_sfx_url IS NULL OR v_sfx_key IS NULL THEN
    NEW.escrow_status   := 'BLOCKED';
    NEW.veritas_verdict := 'ERROR';
    RETURN NEW;
  END IF;

  -- Build RPC payload for fn_submit_to_escrow
  v_payload := jsonb_build_object(
    'p_destination_canon_target', NEW.canon_candidate_id,
    'p_staged_payload_json',      jsonb_build_object(
      'draft_id',            NEW.draft_id,
      'canon_candidate_id',  NEW.canon_candidate_id,
      'title',               NEW.title,
      'cluster',             NEW.cluster,
      'body',                NEW.body,
      'synthesized_by',      NEW.synthesized_by,
      'canon_version',       NEW.canon_version,
      'dependency_refs',     NEW.dependency_refs,
      'conflict_flags',      NEW.conflict_flags,
      't1_synthesis_notes',  NEW.t1_synthesis_notes
    ),
    'p_binding_id',    NEW.sfx_binding_id,
    'p_context_id',    NEW.context_id,
    'p_regime',        NEW.synthesized_by,  -- resolved below
    'p_authority_tier', 1
  );

  -- Regime: T1 synthesis = DELEGATED; override if synthesized_by contains T2
  v_payload := v_payload || jsonb_build_object(
    'p_regime',
    CASE
      WHEN NEW.synthesized_by ILIKE '%T2%' THEN 'ADVISORY'
      WHEN NEW.synthesized_by ILIKE '%T0%' THEN 'SOVEREIGN'
      ELSE 'DELEGATED'
    END,
    'p_authority_tier',
    CASE
      WHEN NEW.synthesized_by ILIKE '%T2%' THEN 2
      WHEN NEW.synthesized_by ILIKE '%T0%' THEN 0
      ELSE 1
    END
  );

  -- Fire async HTTP POST via pg_net (non-blocking)
  PERFORM net.http_post(
    url     := v_sfx_url || '/rest/v1/rpc/fn_submit_to_escrow',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'apikey',        v_sfx_key,
      'Authorization', 'Bearer ' || v_sfx_key
    ),
    body    := v_payload::text
  );

  -- Mark draft as escrow submitted (escrow_id populated async via Make.com callback)
  NEW.escrow_status   := 'SUBMITTED';
  NEW.draft_status    := 'UNDER_REVIEW';

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking: log failure state but don't prevent the bind from completing
  NEW.escrow_status   := 'BLOCKED';
  NEW.veritas_verdict := 'ERROR';
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_canon_draft_escrow_gate()
  IS 'GAP-04. Fires on sfx_canon_drafts when sfx_binding_id is attached (CPPK bind event). Submits draft payload to shadowfox-os fn_submit_to_escrow via pg_net async HTTP POST. Sets escrow_status=SUBMITTED and draft_status=UNDER_REVIEW. Non-blocking on error. Requires sfx_supabase_url + sfx_service_role_key in sfx_system_config.notes. CANON-206/207/208.';

-- 3. Attach trigger BEFORE UPDATE on sfx_canon_drafts (BEFORE so we can mutate NEW)
DROP TRIGGER IF EXISTS trg_canon_draft_escrow_gate ON public.sfx_canon_drafts;

CREATE TRIGGER trg_canon_draft_escrow_gate
  BEFORE UPDATE OF sfx_binding_id ON public.sfx_canon_drafts
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_canon_draft_escrow_gate();

COMMENT ON TRIGGER trg_canon_draft_escrow_gate ON public.sfx_canon_drafts
  IS 'GAP-04. Fires when CPPK attaches sfx_binding_id to a canon draft. Routes to P6 escrow + VERITAS. CANON-206/207/208.';

-- 4. Draft status transition guard — block illegal status hops
CREATE OR REPLACE FUNCTION public.fn_enforce_draft_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Legal transitions matrix
  -- DRAFT → UNDER_REVIEW (escrow submitted)
  -- DRAFT → DEPRECATED
  -- UNDER_REVIEW → RATIFIED (T0 seal)
  -- UNDER_REVIEW → DRAFT (escrow rejected, returned)
  -- UNDER_REVIEW → DEPRECATED
  -- RATIFIED → (terminal, no transitions)
  IF OLD.draft_status = NEW.draft_status THEN
    RETURN NEW; -- no change
  END IF;

  IF OLD.draft_status = 'RATIFIED' THEN
    RAISE EXCEPTION
      'GOVERNANCE_VIOLATION: Cannot transition Canon draft % from RATIFIED to %. RATIFIED is a terminal state.',
      NEW.draft_id, NEW.draft_status
      USING ERRCODE = 'P0001';
  END IF;

  IF OLD.draft_status = 'UNDER_REVIEW' AND NEW.draft_status NOT IN ('RATIFIED', 'DRAFT', 'DEPRECATED') THEN
    RAISE EXCEPTION
      'GOVERNANCE_VIOLATION: Illegal draft status transition % → % on draft %. Allowed from UNDER_REVIEW: RATIFIED, DRAFT, DEPRECATED.',
      OLD.draft_status, NEW.draft_status, NEW.draft_id
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_enforce_draft_status_transition()
  IS 'GAP-04. Enforces legal Canon draft status transitions. Blocks re-opening RATIFIED drafts and invalid UNDER_REVIEW transitions. CANON-207/211.';

DROP TRIGGER IF EXISTS trg_draft_status_guard ON public.sfx_canon_drafts;

CREATE TRIGGER trg_draft_status_guard
  BEFORE UPDATE OF draft_status ON public.sfx_canon_drafts
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_enforce_draft_status_transition();

COMMENT ON TRIGGER trg_draft_status_guard ON public.sfx_canon_drafts
  IS 'GAP-04. Enforces legal draft_status state machine. RATIFIED is terminal. CANON-207/211.';
