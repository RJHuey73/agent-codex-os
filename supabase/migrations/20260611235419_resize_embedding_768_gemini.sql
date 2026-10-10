
-- ================================================================
-- MIGRATION: resize_embedding_768_gemini
-- Session: SFX-SESSION-20260611 Phase 3 | T0 confirmed Option A
-- ================================================================

-- Step 1: Drop existing embedding index
DROP INDEX IF EXISTS ccx_knowledge_index_embedding_idx;

-- Step 2: Drop existing ccx_search_knowledge (signature must change)
DROP FUNCTION IF EXISTS public.ccx_search_knowledge(vector, numeric, integer, text, text);

-- Step 3: Resize embedding column 1536 → 768
-- Safe: zero rows in ccx_knowledge_index
ALTER TABLE ccx_knowledge_index
  ALTER COLUMN embedding TYPE vector(768)
  USING NULL::vector(768);

-- Step 4: Rebuild ivfflat index for 768-dim cosine similarity
CREATE INDEX ccx_knowledge_index_embedding_idx
  ON ccx_knowledge_index
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 10);

-- Step 5: Recreate ccx_search_knowledge for vector(768)
CREATE FUNCTION public.ccx_search_knowledge(
  query_embedding   vector(768),
  match_threshold   numeric  DEFAULT 0.75,
  match_count       integer  DEFAULT 10,
  filter_cluster    text     DEFAULT NULL,
  filter_status     text     DEFAULT 'ACTIVE'
)
RETURNS TABLE (
  knowledge_id   uuid,
  title          text,
  summary        text,
  knowledge_type text,
  cluster_tags   text[],
  canon_refs     text[],
  trust_score    numeric,
  canon_version  text,
  similarity     float
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT
    ki.knowledge_id,
    ki.title,
    ki.summary,
    ki.knowledge_type,
    ki.cluster_tags,
    ki.canon_refs,
    ki.trust_score,
    ki.canon_version,
    1 - (ki.embedding <=> query_embedding) AS similarity
  FROM ccx_knowledge_index ki
  WHERE
    ki.index_status = COALESCE(filter_status, ki.index_status)
    AND (filter_cluster IS NULL OR ki.cluster_tags @> ARRAY[filter_cluster])
    AND 1 - (ki.embedding <=> query_embedding) >= match_threshold
  ORDER BY ki.embedding <=> query_embedding
  LIMIT match_count;
$$;
