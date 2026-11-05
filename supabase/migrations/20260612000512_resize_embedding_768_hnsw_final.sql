
-- Final schema: vector(768) with HNSW index
-- gemini-embedding-001 will use output_dimensionality=768 (Matryoshka)
DROP INDEX IF EXISTS idx_ccx_knowledge_embedding;
DROP INDEX IF EXISTS ccx_knowledge_index_embedding_idx;
DROP FUNCTION IF EXISTS public.ccx_search_knowledge(vector, numeric, integer, text, text);

ALTER TABLE ccx_knowledge_index
  ALTER COLUMN embedding TYPE vector(768)
  USING NULL::vector(768);

CREATE INDEX ccx_knowledge_index_embedding_idx
  ON ccx_knowledge_index
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

CREATE FUNCTION public.ccx_search_knowledge(
  query_embedding   vector(768),
  match_threshold   numeric  DEFAULT 0.75,
  match_count       integer  DEFAULT 10,
  filter_cluster    text     DEFAULT NULL,
  filter_status     text     DEFAULT 'ACTIVE'
)
RETURNS TABLE (
  knowledge_id uuid, title text, summary text, knowledge_type text,
  cluster_tags text[], canon_refs text[], trust_score numeric,
  canon_version text, similarity float
)
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT ki.knowledge_id, ki.title, ki.summary, ki.knowledge_type,
         ki.cluster_tags, ki.canon_refs, ki.trust_score, ki.canon_version,
         1 - (ki.embedding <=> query_embedding) AS similarity
  FROM ccx_knowledge_index ki
  WHERE ki.index_status = COALESCE(filter_status, ki.index_status)
    AND (filter_cluster IS NULL OR ki.cluster_tags @> ARRAY[filter_cluster])
    AND 1 - (ki.embedding <=> query_embedding) >= match_threshold
  ORDER BY ki.embedding <=> query_embedding
  LIMIT match_count;
$$;
