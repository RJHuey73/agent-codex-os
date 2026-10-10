
-- ============================================================
-- CCX Phase 2 — Conditional Governance Write-Back
-- Migration: ccx_phase2_governance_writeback
-- Canon refs: CANON-204/250/251/259/269/273/274
-- Applied: 2026-06-01 | Canon v9.41.0
--
-- Implements conditional governance write-back model:
--   Retrieval/Synthesis → governance event INSERT
--   → trigger dispatch → controlled mutation function
--   → memory_embeddings annotated under governance authority
-- ============================================================

-- ── 1. Extend memory_embeddings with governance trust state ──
-- Distinct from index_status (lifecycle). governance_status = trust state.

ALTER TABLE public.memory_embeddings
  ADD COLUMN IF NOT EXISTS governance_status     text NOT NULL DEFAULT 'provisional'
    CHECK (governance_status IN ('provisional', 'stable', 'disputed', 'cold')),
  ADD COLUMN IF NOT EXISTS governance_version    integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS last_governance_event_id   uuid,
  ADD COLUMN IF NOT EXISTS last_governance_event_type text
    CHECK (last_governance_event_type IN (
      'high_conf_retrieval', 'arbitration', 'synthesis',
      'override', 'invalidation', 'drift_correction',
      'routing_correction', 'cold_mark', 'cluster_reinforcement',
      'conflict_resolution'
    )),
  ADD COLUMN IF NOT EXISTS last_governed_at      timestamptz;

COMMENT ON COLUMN public.memory_embeddings.governance_status IS
  'Trust state: provisional (unconfirmed) | stable (arbitrated) | disputed (conflict) | cold (inactive). '
  'Distinct from index_status (lifecycle). CANON-204 TrustState.';
COMMENT ON COLUMN public.memory_embeddings.governance_version IS
  'Monotonic counter incremented on every governance mutation. Used for optimistic concurrency.';
COMMENT ON COLUMN public.memory_embeddings.last_governance_event_id IS
  'FK to ccx_governance_events.id — the event that last mutated this row.';
COMMENT ON COLUMN public.memory_embeddings.last_governance_event_type IS
  'Denormalized event type for fast filtering without join.';
COMMENT ON COLUMN public.memory_embeddings.last_governed_at IS
  'Timestamp of last governance mutation. Used for cold_mark and TTL enforcement.';

-- ── 2. ccx_governance_events — event log driving mutations ───
-- Agents INSERT here. Trigger dispatches to mutation functions.
-- No agent writes directly to memory_embeddings.

CREATE TABLE IF NOT EXISTS public.ccx_governance_events (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type            text NOT NULL
    CHECK (event_type IN (
      'high_conf_retrieval', 'arbitration', 'synthesis',
      'override', 'invalidation', 'drift_correction',
      'routing_correction', 'cold_mark', 'cluster_reinforcement',
      'conflict_resolution'
    )),
  source_agent          text NOT NULL,   -- e.g. 'identity_steward', 'canon_guardian'
  related_embedding_id  uuid REFERENCES public.memory_embeddings (id) ON DELETE SET NULL,
  related_candidate_id  uuid REFERENCES public.ccx_canon_candidates (candidate_id) ON DELETE SET NULL,
  related_canon_id      text,            -- e.g. 'SFX-CANON-250'
  similarity_score      numeric(6,5),    -- originating retrieval score if applicable
  authority_tier        integer NOT NULL DEFAULT 2
    CHECK (authority_tier >= 0 AND authority_tier <= 5),
  payload               jsonb NOT NULL DEFAULT '{}',
  canon_version         text NOT NULL DEFAULT current_canon_version(),
  created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_ccx_gov_events_embedding
  ON public.ccx_governance_events (related_embedding_id, created_at DESC);
CREATE INDEX idx_ccx_gov_events_type
  ON public.ccx_governance_events (event_type, created_at DESC);
CREATE INDEX idx_ccx_gov_events_agent
  ON public.ccx_governance_events (source_agent);

ALTER TABLE public.ccx_governance_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ccx_gov_events_write_service"
  ON public.ccx_governance_events FOR INSERT
  TO service_role
  WITH CHECK (true);

CREATE POLICY "ccx_gov_events_read_service"
  ON public.ccx_governance_events FOR SELECT
  USING (auth.role() = 'service_role');

-- Backfill FK on memory_embeddings → governance event log
ALTER TABLE public.memory_embeddings
  ADD CONSTRAINT mem_emb_last_gov_event_fk
  FOREIGN KEY (last_governance_event_id)
  REFERENCES public.ccx_governance_events (id)
  ON DELETE SET NULL
  DEFERRABLE INITIALLY DEFERRED;

COMMENT ON TABLE public.ccx_governance_events IS
  'Governance event log. Agents INSERT here; trigger dispatches to mutation functions. '
  'No agent writes directly to memory_embeddings. '
  'CANON-204 (TrustState), CANON-273 (Arbitration Engine), CANON-274 (Canon Candidate Routing).';

-- ── 3. Mutation functions ────────────────────────────────────
-- Each function is called only by the dispatch trigger.
-- All search_path pinned. All revoked from anon/authenticated.

-- 3a. high_conf_retrieval → provisional cluster_tags
CREATE OR REPLACE FUNCTION public.fn_ccx_mutate_high_conf_retrieval(
  p_embedding_id  uuid,
  p_tags          text[],
  p_event_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.memory_embeddings
  SET
    cluster_tags               = (
      SELECT ARRAY(SELECT DISTINCT unnest(cluster_tags || COALESCE(p_tags, '{}')))
    ),
    governance_status          = CASE
                                   WHEN governance_status = 'cold' THEN 'provisional'
                                   ELSE COALESCE(governance_status, 'provisional')
                                 END,
    governance_version         = governance_version + 1,
    last_governance_event_id   = p_event_id,
    last_governance_event_type = 'high_conf_retrieval',
    last_governed_at           = now()
  WHERE id = p_embedding_id;
END;
$$;

-- 3b. arbitration → stable canon_refs (permanent)
CREATE OR REPLACE FUNCTION public.fn_ccx_mutate_arbitrated_canon_link(
  p_embedding_id  uuid,
  p_canon_refs    text[],
  p_event_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.memory_embeddings
  SET
    canon_refs                 = (
      SELECT ARRAY(SELECT DISTINCT unnest(canon_refs || COALESCE(p_canon_refs, '{}')))
    ),
    governance_status          = 'stable',
    governance_version         = governance_version + 1,
    last_governance_event_id   = p_event_id,
    last_governance_event_type = 'arbitration',
    last_governed_at           = now()
  WHERE id = p_embedding_id;
END;
$$;

-- 3c. invalidation → remove specific canon_refs, mark stable
CREATE OR REPLACE FUNCTION public.fn_ccx_mutate_invalidation(
  p_embedding_id       uuid,
  p_canon_refs_remove  text[],
  p_event_id           uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.memory_embeddings
  SET
    canon_refs                 = (
      SELECT ARRAY(
        SELECT DISTINCT x
        FROM unnest(canon_refs) AS x
        WHERE x <> ALL (COALESCE(p_canon_refs_remove, '{}'))
      )
    ),
    governance_status          = 'stable',
    governance_version         = governance_version + 1,
    last_governance_event_id   = p_event_id,
    last_governance_event_type = 'invalidation',
    last_governed_at           = now()
  WHERE id = p_embedding_id;
END;
$$;

-- 3d. conflict_resolution → mark disputed (additive, non-destructive)
CREATE OR REPLACE FUNCTION public.fn_ccx_mutate_conflict_resolution(
  p_embedding_id  uuid,
  p_event_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.memory_embeddings
  SET
    governance_status          = 'disputed',
    governance_version         = governance_version + 1,
    last_governance_event_id   = p_event_id,
    last_governance_event_type = 'conflict_resolution',
    last_governed_at           = now()
  WHERE id = p_embedding_id
    AND governance_status != 'stable';  -- stable cannot be disputed without arbitration
END;
$$;

-- 3e. cold_mark → mark cold (no deletion)
CREATE OR REPLACE FUNCTION public.fn_ccx_mutate_cold_mark(
  p_embedding_id  uuid,
  p_event_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.memory_embeddings
  SET
    governance_status          = 'cold',
    index_status               = 'ARCHIVED',
    governance_version         = governance_version + 1,
    last_governance_event_id   = p_event_id,
    last_governance_event_type = 'cold_mark',
    last_governed_at           = now()
  WHERE id = p_embedding_id
    AND governance_status != 'stable';  -- stable memory never cold-marked without override
END;
$$;

-- 3f. cluster_reinforcement → promote provisional → stable tags
CREATE OR REPLACE FUNCTION public.fn_ccx_mutate_cluster_reinforcement(
  p_embedding_id  uuid,
  p_tags          text[],
  p_event_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.memory_embeddings
  SET
    cluster_tags               = (
      SELECT ARRAY(SELECT DISTINCT unnest(cluster_tags || COALESCE(p_tags, '{}')))
    ),
    governance_status          = CASE
                                   WHEN governance_status = 'provisional' THEN 'stable'
                                   ELSE governance_status
                                 END,
    governance_version         = governance_version + 1,
    last_governance_event_id   = p_event_id,
    last_governance_event_type = 'cluster_reinforcement',
    last_governed_at           = now()
  WHERE id = p_embedding_id;
END;
$$;

-- ── 4. Dispatch trigger ───────────────────────────────────────
-- Reads event_type from new row; routes to mutation function.
-- Payload extraction uses jsonb_array_elements_text() — safe cast.

CREATE OR REPLACE FUNCTION public.fn_ccx_governance_event_dispatch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tags          text[];
  v_canon_refs    text[];
  v_remove_refs   text[];
BEGIN
  -- Only act if related_embedding_id is set
  IF NEW.related_embedding_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.event_type = 'high_conf_retrieval' THEN
    SELECT ARRAY(SELECT jsonb_array_elements_text(NEW.payload->'cluster_tags'))
      INTO v_tags;
    PERFORM public.fn_ccx_mutate_high_conf_retrieval(
      NEW.related_embedding_id, v_tags, NEW.id
    );

  ELSIF NEW.event_type = 'arbitration' THEN
    SELECT ARRAY(SELECT jsonb_array_elements_text(NEW.payload->'canon_refs'))
      INTO v_canon_refs;
    PERFORM public.fn_ccx_mutate_arbitrated_canon_link(
      NEW.related_embedding_id, v_canon_refs, NEW.id
    );

  ELSIF NEW.event_type = 'invalidation' THEN
    SELECT ARRAY(SELECT jsonb_array_elements_text(NEW.payload->'canon_refs_to_remove'))
      INTO v_remove_refs;
    PERFORM public.fn_ccx_mutate_invalidation(
      NEW.related_embedding_id, v_remove_refs, NEW.id
    );

  ELSIF NEW.event_type = 'conflict_resolution' THEN
    PERFORM public.fn_ccx_mutate_conflict_resolution(
      NEW.related_embedding_id, NEW.id
    );

  ELSIF NEW.event_type = 'cold_mark' THEN
    PERFORM public.fn_ccx_mutate_cold_mark(
      NEW.related_embedding_id, NEW.id
    );

  ELSIF NEW.event_type = 'cluster_reinforcement' THEN
    SELECT ARRAY(SELECT jsonb_array_elements_text(NEW.payload->'cluster_tags'))
      INTO v_tags;
    PERFORM public.fn_ccx_mutate_cluster_reinforcement(
      NEW.related_embedding_id, v_tags, NEW.id
    );

  -- drift_correction, routing_correction, synthesis, override:
  -- payload-only events — no memory_embeddings mutation at dispatch time.
  -- Handled by dedicated agents reading the event log.
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ccx_governance_event_dispatch
  ON public.ccx_governance_events;

CREATE TRIGGER trg_ccx_governance_event_dispatch
  AFTER INSERT ON public.ccx_governance_events
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_ccx_governance_event_dispatch();

-- ── 5. RPC surface — ccx_log_governance_event ────────────────
-- Single ingress point for agents. Returns event ID.
-- Trigger fires automatically after INSERT.

CREATE OR REPLACE FUNCTION public.ccx_log_governance_event(
  p_event_type            text,
  p_source_agent          text,
  p_related_embedding_id  uuid    DEFAULT NULL,
  p_related_candidate_id  uuid    DEFAULT NULL,
  p_related_canon_id      text    DEFAULT NULL,
  p_similarity_score      numeric DEFAULT NULL,
  p_authority_tier        integer DEFAULT 2,
  p_payload               jsonb   DEFAULT '{}'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.ccx_governance_events (
    event_type, source_agent, related_embedding_id,
    related_candidate_id, related_canon_id,
    similarity_score, authority_tier, payload
  ) VALUES (
    p_event_type, p_source_agent, p_related_embedding_id,
    p_related_candidate_id, p_related_canon_id,
    p_similarity_score, p_authority_tier,
    COALESCE(p_payload, '{}')
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ── 6. Security: revoke all sprint functions from anon/authenticated ──
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_high_conf_retrieval(uuid, text[], uuid)
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_arbitrated_canon_link(uuid, text[], uuid)
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_invalidation(uuid, text[], uuid)
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_conflict_resolution(uuid, uuid)
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_cold_mark(uuid, uuid)
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_cluster_reinforcement(uuid, text[], uuid)
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_governance_event_dispatch()
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.ccx_log_governance_event(text, text, uuid, uuid, text, numeric, integer, jsonb)
  FROM anon, authenticated;

COMMENT ON FUNCTION public.ccx_log_governance_event IS
  'Single agent ingress point. INSERT into ccx_governance_events → '
  'trigger dispatches to mutation function. '
  'Never call fn_ccx_mutate_* directly. '
  'CANON-204 TrustState, CANON-273 Arbitration Engine.';
