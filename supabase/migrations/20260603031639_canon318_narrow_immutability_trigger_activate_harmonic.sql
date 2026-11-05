
-- ══════════════════════════════════════════════════════════════════════════
-- CANON-318: Narrow trdec_agents immutability trigger
-- Immutability applies to IDENTITY fields only, not lifecycle state.
-- Identity: agent_id, canonical_name, class, cluster_id, trust_state_floor,
--           ratified_by (original ratifier), created_at
-- Lifecycle (mutable): invocable, ratified_in (updated on activation)
-- T0 ratified | CANON-318 authority
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trdec_prevent_agents_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Block changes to identity fields only
  IF (
    OLD.agent_id          IS DISTINCT FROM NEW.agent_id          OR
    OLD.canonical_name    IS DISTINCT FROM NEW.canonical_name    OR
    OLD.class             IS DISTINCT FROM NEW.class             OR
    OLD.cluster_id        IS DISTINCT FROM NEW.cluster_id        OR
    OLD.trust_state_floor IS DISTINCT FROM NEW.trust_state_floor OR
    OLD.ratified_by       IS DISTINCT FROM NEW.ratified_by       OR
    OLD.created_at        IS DISTINCT FROM NEW.created_at
  ) THEN
    RAISE EXCEPTION
      'trdec_agents identity fields are immutable (agent_id, canonical_name, class, cluster_id, trust_state_floor, ratified_by, created_at). To change identity, retire and re-register. CANON-318.';
  END IF;
  -- Allow lifecycle field updates: invocable, ratified_in, authority, constraints,
  -- invocation_surface, provenance_req, replay_req, t2_advisory_role
  RETURN NEW;
END;
$$;

-- ── CANON-318: Activate Harmonic agents ─────────────────────────────────────

UPDATE trdec_agents
SET
  invocable   = true,
  ratified_in = 'SFX-CANON-318'
WHERE agent_id IN (
  'TRDEC-A06', 'TRDEC-A07', 'TRDEC-A08', 'TRDEC-A09',
  'TRDEC-A10', 'TRDEC-A11', 'TRDEC-A12', 'TRDEC-A13'
);

-- Verify
SELECT agent_id, canonical_name, class, trust_state_floor, invocable, ratified_in
FROM trdec_agents
ORDER BY agent_id;
