
-- ============================================================
-- CCX Phase 1 — Core Substrate Tables
-- Migration: ccx_phase1_tables
-- Canon refs: CANON-250/251/259/269/270/273/274
-- Applied: 2026-06-01 | Canon v9.41.0
-- ============================================================

-- ── 1. ccx_ingestion_queue ────────────────────────────────────
-- External knowledge intake buffer. CANON-270: External Knowledge
-- Ingestion Protocol. Every external artifact enters here first.
-- Governed by Ingestion Boundary Law (CANON-276).

CREATE TABLE IF NOT EXISTS public.ccx_ingestion_queue (
  ingestion_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Source identification
  source_type         text NOT NULL
    CHECK (source_type IN (
      'WEB_ARTICLE', 'PDF', 'NOTION_PAGE', 'GITHUB_REPO',
      'TRANSCRIPT', 'MANUAL_INPUT', 'T2_SYNTHESIS', 'FEED'
    )),
  source_url          text,
  source_title        text,
  raw_content         text NOT NULL,
  raw_content_hash    text NOT NULL,        -- SHA256 dedup gate

  -- Governance envelope
  submitted_by        text NOT NULL DEFAULT 'T1',
  authority_tier      integer NOT NULL DEFAULT 2
    CHECK (authority_tier >= 0 AND authority_tier <= 5),
  canon_version       text NOT NULL DEFAULT current_canon_version(),

  -- Processing state
  ingestion_status    text NOT NULL DEFAULT 'PENDING'
    CHECK (ingestion_status IN (
      'PENDING', 'PROCESSING', 'INDEXED', 'REJECTED', 'DUPLICATE'
    )),
  rejection_reason    text,
  processed_at        timestamptz,

  -- CCX linkage
  knowledge_index_id  uuid,                 -- FK set after indexing
  workflow_id         uuid,                 -- originating run-agent workflow

  created_at          timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ccx_ingestion_queue_hash_unique UNIQUE (raw_content_hash)
);

ALTER TABLE public.ccx_ingestion_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ccx_ingestion_read_service"
  ON public.ccx_ingestion_queue FOR SELECT
  USING (true);

CREATE POLICY "ccx_ingestion_write_service"
  ON public.ccx_ingestion_queue FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE INDEX idx_ccx_ingestion_status
  ON public.ccx_ingestion_queue (ingestion_status, created_at DESC);
CREATE INDEX idx_ccx_ingestion_source_type
  ON public.ccx_ingestion_queue (source_type);

COMMENT ON TABLE public.ccx_ingestion_queue IS
  'External knowledge intake buffer. Every artifact entering CCX passes through here. '
  'SHA256 dedup gate enforces Ingestion Boundary Law (CANON-276). '
  'Governed by External Knowledge Ingestion Protocol (CANON-270).';

-- ── 2. ccx_knowledge_index ────────────────────────────────────
-- Processed, normalized knowledge units. CANON-269: CCX Self-Indexing.
-- CANON-259: Knowledge Synthesis Architecture.
-- Each row is a discrete knowledge atom: chunk, concept, or synthesis.

CREATE TABLE IF NOT EXISTS public.ccx_knowledge_index (
  knowledge_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Content
  title               text NOT NULL,
  summary             text NOT NULL,
  body                text NOT NULL,
  embedding           vector(1536),         -- text-embedding-3-small / claude dim

  -- Classification
  knowledge_type      text NOT NULL DEFAULT 'CHUNK'
    CHECK (knowledge_type IN (
      'CHUNK',          -- raw extracted segment
      'CONCEPT',        -- synthesized atomic concept
      'SYNTHESIS',      -- multi-source synthesis
      'CANON_REF',      -- direct Canon entry reference
      'PATTERN'         -- recurring structural pattern
    )),
  cluster_tags        text[] NOT NULL DEFAULT '{}',
  canon_refs          text[] NOT NULL DEFAULT '{}',  -- SFX-CANON-NNN refs

  -- Provenance
  ingestion_id        uuid REFERENCES public.ccx_ingestion_queue (ingestion_id),
  synthesized_by      text NOT NULL DEFAULT 'T1:claude',
  authority_tier      integer NOT NULL DEFAULT 2
    CHECK (authority_tier >= 0 AND authority_tier <= 5),
  trust_score         numeric(4,3) NOT NULL DEFAULT 0.500
    CHECK (trust_score >= 0.000 AND trust_score <= 1.000),
  canon_version       text NOT NULL DEFAULT current_canon_version(),

  -- Lifecycle
  index_status        text NOT NULL DEFAULT 'ACTIVE'
    CHECK (index_status IN ('ACTIVE', 'SUPERSEDED', 'QUARANTINED', 'ARCHIVED')),
  superseded_by       uuid,                 -- self-ref on supersession
  indexed_at          timestamptz NOT NULL DEFAULT now(),
  last_accessed_at    timestamptz,
  access_count        integer NOT NULL DEFAULT 0
);

-- Back-fill FK from ingestion queue
ALTER TABLE public.ccx_ingestion_queue
  ADD CONSTRAINT ccx_ingestion_knowledge_fk
  FOREIGN KEY (knowledge_index_id)
  REFERENCES public.ccx_knowledge_index (knowledge_id)
  DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.ccx_knowledge_index ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ccx_knowledge_read_service"
  ON public.ccx_knowledge_index FOR SELECT
  USING (true);

CREATE POLICY "ccx_knowledge_write_service"
  ON public.ccx_knowledge_index FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Vector similarity index (ivfflat; lists=50 appropriate for <100k rows)
CREATE INDEX idx_ccx_knowledge_embedding
  ON public.ccx_knowledge_index
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 50);

CREATE INDEX idx_ccx_knowledge_type_status
  ON public.ccx_knowledge_index (knowledge_type, index_status);
CREATE INDEX idx_ccx_knowledge_cluster_tags
  ON public.ccx_knowledge_index USING gin (cluster_tags);
CREATE INDEX idx_ccx_knowledge_canon_refs
  ON public.ccx_knowledge_index USING gin (canon_refs);

COMMENT ON TABLE public.ccx_knowledge_index IS
  'Processed knowledge atoms with vector embeddings. '
  'Core substrate for CCX semantic search and synthesis. '
  'CANON-269 (Self-Indexing), CANON-259 (Knowledge Synthesis Architecture).';

-- ── 3. ccx_canon_candidates ───────────────────────────────────
-- Candidate Canon entries surfaced by CCX. CANON-274: Canon Candidate
-- Routing. CANON-273: CCX Arbitration Engine.
-- Bridge between autonomous synthesis and the ratification gate.

CREATE TABLE IF NOT EXISTS public.ccx_canon_candidates (
  candidate_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Canon identity
  proposed_canon_id   text,                 -- e.g. SFX-CANON-284 (pre-assigned)
  title               text NOT NULL,
  cluster             text NOT NULL,
  body                text NOT NULL,
  depends_on          text[] NOT NULL DEFAULT '{}',

  -- Source knowledge
  knowledge_refs      uuid[] NOT NULL DEFAULT '{}',  -- ccx_knowledge_index.knowledge_id refs
  synthesis_rationale text,

  -- Routing state (CANON-274)
  routing_state       text NOT NULL DEFAULT 'SURFACED'
    CHECK (routing_state IN (
      'SURFACED',       -- CCX identified as candidate
      'T1_REVIEW',      -- awaiting T1 triage
      'T1_APPROVED',    -- T1 approved for ratification gate
      'T1_REJECTED',    -- T1 rejected, returned to index
      'GATE_OPEN',      -- ratification gate created (sfx_ratification_gate FK)
      'RATIFIED',       -- T0 ratified → Canon entry written
      'SUPERSEDED'      -- replaced by a later candidate
    )),
  t1_review_notes     text,
  t1_reviewed_at      timestamptz,

  -- Arbitration (CANON-273)
  conflict_flags      text[] NOT NULL DEFAULT '{}',
  arbitration_notes   text,
  arbitrated_at       timestamptz,

  -- Governance
  gate_id             uuid,                 -- sfx_ratification_gate.gate_id (agent-codex-os)
  draft_id            uuid REFERENCES public.sfx_canon_drafts (draft_id),
  surfaced_by         text NOT NULL DEFAULT 'CCX',
  authority_tier      integer NOT NULL DEFAULT 2
    CHECK (authority_tier >= 0 AND authority_tier <= 5),
  canon_version       text NOT NULL DEFAULT current_canon_version(),

  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ccx_canon_candidates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ccx_candidates_read_service"
  ON public.ccx_canon_candidates FOR SELECT
  USING (true);

CREATE POLICY "ccx_candidates_write_service"
  ON public.ccx_canon_candidates FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE INDEX idx_ccx_candidates_routing_state
  ON public.ccx_canon_candidates (routing_state, created_at DESC);
CREATE INDEX idx_ccx_candidates_cluster
  ON public.ccx_canon_candidates (cluster);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.fn_ccx_candidates_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_ccx_candidates_updated_at
  BEFORE UPDATE ON public.ccx_canon_candidates
  FOR EACH ROW EXECUTE FUNCTION public.fn_ccx_candidates_updated_at();

COMMENT ON TABLE public.ccx_canon_candidates IS
  'CCX-surfaced Canon candidates awaiting T1 triage and T0 ratification. '
  'Routing state machine bridges autonomous synthesis to the ratification gate. '
  'CANON-274 (Canon Candidate Routing), CANON-273 (CCX Arbitration Engine).';

-- ── 4. Upgrade memory_embeddings for CCX awareness ────────────
-- Existing table has generic schema. Add CCX governance columns
-- without breaking existing structure.

ALTER TABLE public.memory_embeddings
  ADD COLUMN IF NOT EXISTS knowledge_id      uuid
    REFERENCES public.ccx_knowledge_index (knowledge_id),
  ADD COLUMN IF NOT EXISTS source_type       text,
  ADD COLUMN IF NOT EXISTS cluster_tags      text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS canon_refs        text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS authority_tier    integer DEFAULT 2
    CHECK (authority_tier >= 0 AND authority_tier <= 5),
  ADD COLUMN IF NOT EXISTS canon_version     text DEFAULT current_canon_version(),
  ADD COLUMN IF NOT EXISTS index_status      text DEFAULT 'ACTIVE'
    CHECK (index_status IN ('ACTIVE', 'SUPERSEDED', 'QUARANTINED', 'ARCHIVED'));

-- Vector index on memory_embeddings if embedding column is typed
-- Check dimension first; skip if embedding is untyped
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'memory_embeddings'
      AND column_name = 'embedding'
      AND udt_name = 'vector'
  ) THEN
    -- Only create index if not exists
    IF NOT EXISTS (
      SELECT 1 FROM pg_indexes
      WHERE tablename = 'memory_embeddings'
        AND indexname = 'idx_memory_embeddings_vector'
    ) THEN
      EXECUTE 'CREATE INDEX idx_memory_embeddings_vector
               ON public.memory_embeddings
               USING ivfflat (embedding vector_cosine_ops)
               WITH (lists = 50)';
    END IF;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_memory_embeddings_knowledge_id
  ON public.memory_embeddings (knowledge_id);

COMMENT ON TABLE public.memory_embeddings IS
  'Vector memory store. Upgraded for CCX awareness: knowledge_id FK, '
  'cluster_tags, canon_refs, governance columns. '
  'CANON-250 (Semantic Layer), CANON-251 (Knowledge Routing Protocol).';

-- ── 5. Semantic search helper function ────────────────────────
-- Callable from run-agent (via Supabase REST RPC) for similarity search.

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

COMMENT ON FUNCTION public.ccx_search_knowledge IS
  'Vector similarity search over ccx_knowledge_index. '
  'Callable via Supabase REST RPC from run-agent or Make.com. '
  'CANON-251 (Knowledge Routing Protocol).';

-- ── 6. Comments on all canon_version defaults ─────────────────
COMMENT ON COLUMN public.ccx_ingestion_queue.canon_version IS
  'Canon version at ingestion time. Bound to current_canon_version().';
COMMENT ON COLUMN public.ccx_knowledge_index.canon_version IS
  'Canon version at indexing time. Bound to current_canon_version().';
COMMENT ON COLUMN public.ccx_canon_candidates.canon_version IS
  'Canon version when candidate was surfaced. Bound to current_canon_version().';
