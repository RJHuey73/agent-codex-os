
-- ============================================================
-- CCX Phase 1 Security Hardening
-- Migration: ccx_phase1_security_hardening
-- Fixes advisors introduced this sprint:
--   1. memory_embeddings — RLS policy missing
--   2. fn_ccx_candidates_updated_at — mutable search_path
--   3. ccx_search_knowledge — mutable search_path + anon execute
--   4. current_canon_version + update_canon_version — revoke anon
-- ============================================================

-- ── 1. memory_embeddings RLS policy ─────────────────────────
CREATE POLICY "memory_embeddings_read_service"
  ON public.memory_embeddings FOR SELECT
  USING (true);

CREATE POLICY "memory_embeddings_write_service"
  ON public.memory_embeddings FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- ── 2. fn_ccx_candidates_updated_at — fix search_path ────────
CREATE OR REPLACE FUNCTION public.fn_ccx_candidates_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ── 3. ccx_search_knowledge — fix search_path + revoke anon ──
CREATE OR REPLACE FUNCTION public.ccx_search_knowledge(
  query_embedding   vector(1536),
  match_threshold   numeric DEFAULT 0.75,
  match_count       integer DEFAULT 10,
  filter_cluster    text    DEFAULT NULL,
  filter_status     text    DEFAULT 'ACTIVE'
)
RETURNS TABLE (
  knowledge_id    uuid,
  title           text,
  summary         text,
  knowledge_type  text,
  cluster_tags    text[],
  canon_refs      text[],
  trust_score     numeric,
  similarity      float
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    k.knowledge_id,
    k.title,
    k.summary,
    k.knowledge_type,
    k.cluster_tags,
    k.canon_refs,
    k.trust_score,
    1 - (k.embedding <=> query_embedding) AS similarity
  FROM public.ccx_knowledge_index k
  WHERE
    k.index_status = filter_status
    AND (filter_cluster IS NULL OR filter_cluster = ANY(k.cluster_tags))
    AND k.embedding IS NOT NULL
    AND 1 - (k.embedding <=> query_embedding) >= match_threshold
  ORDER BY k.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- Revoke anon + authenticated execute; service_role retains implicit access
REVOKE EXECUTE ON FUNCTION public.ccx_search_knowledge(
  vector, numeric, integer, text, text
) FROM anon, authenticated;

-- ── 4. current_canon_version + update_canon_version — fix search_path + revoke anon ──
CREATE OR REPLACE FUNCTION public.current_canon_version()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT canon_version FROM public.sfx_system_config LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.update_canon_version(
  p_version     text,
  p_next_id     integer,
  p_actor       text DEFAULT 'T1',
  p_notes       text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.sfx_system_config
  SET
    canon_version   = p_version,
    canon_next_id   = p_next_id,
    last_updated_at = now(),
    updated_by      = p_actor,
    notes           = COALESCE(p_notes, notes)
  WHERE true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'sfx_system_config row not found — seed the table first.';
  END IF;

  RETURN 'Canon version updated to ' || p_version || ' (next ID: ' || p_next_id || ')';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.current_canon_version()
  FROM anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.update_canon_version(text, integer, text, text)
  FROM anon, authenticated;
