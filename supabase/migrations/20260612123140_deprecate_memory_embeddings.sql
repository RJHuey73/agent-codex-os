
-- P6: Deprecate memory_embeddings
-- Rationale: ccx_knowledge_index is the live vector store (10 rows, fn-ccx-ingest writes here).
-- memory_embeddings has 0 rows and is the legacy store. Cannot drop — ccx_governance_events
-- holds a FK on related_embedding_id → memory_embeddings.id.
-- Strategy: block all future inserts via trigger, comment table as DEPRECATED.
-- Session: SFX-SESSION-20260612-B | Canon: v9.55.0

-- 1. Block inserts
CREATE OR REPLACE FUNCTION public.fn_block_memory_embeddings_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'memory_embeddings is DEPRECATED. Write to ccx_knowledge_index instead. '
    'See Canon v9.55.0 / SFX-SESSION-20260612-B.';
END;
$$;

DROP TRIGGER IF EXISTS trg_block_memory_embeddings_insert ON public.memory_embeddings;

CREATE TRIGGER trg_block_memory_embeddings_insert
  BEFORE INSERT ON public.memory_embeddings
  FOR EACH ROW EXECUTE FUNCTION public.fn_block_memory_embeddings_insert();

-- 2. Mark table deprecated via comment
COMMENT ON TABLE public.memory_embeddings IS
  'DEPRECATED — v9.55.0 / SFX-SESSION-20260612-B. '
  'Zero rows. Superseded by ccx_knowledge_index (live vector store). '
  'Cannot drop: ccx_governance_events.related_embedding_id FK preserved for audit lineage. '
  'Inserts blocked by trg_block_memory_embeddings_insert.';

-- 3. Mark the blocking function
COMMENT ON FUNCTION public.fn_block_memory_embeddings_insert() IS
  'Deprecation guard for memory_embeddings. Blocks all future inserts. '
  'Canon v9.55.0.';
