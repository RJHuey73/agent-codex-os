
-- Phase B Migration: Tridecagon Governance Columns + Fixes
-- agent-codex-os | Canon: v9.44.0 | CANON-306

-- 1. trdec_invocations — cluster_id + sfx_* governance columns
ALTER TABLE trdec_invocations
  ADD COLUMN IF NOT EXISTS cluster_id TEXT REFERENCES cluster_bindings(cluster_id),
  ADD COLUMN IF NOT EXISTS sfx_context_id UUID,
  ADD COLUMN IF NOT EXISTS sfx_binding_id TEXT,
  ADD COLUMN IF NOT EXISTS sfx_authority_tier INTEGER CHECK (sfx_authority_tier >= 0 AND sfx_authority_tier <= 5),
  ADD COLUMN IF NOT EXISTS sfx_regime TEXT CHECK (sfx_regime IN ('PROD', 'SANDBOX', 'DEV')),
  ADD COLUMN IF NOT EXISTS sfx_canon_version TEXT,
  ADD COLUMN IF NOT EXISTS sfx_canon_id TEXT;

UPDATE trdec_invocations i
SET cluster_id = a.cluster_id
FROM trdec_agents a
WHERE i.agent_id = a.agent_id
  AND i.cluster_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_trdec_inv_sfx_context
  ON trdec_invocations (sfx_context_id)
  WHERE sfx_context_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_trdec_inv_sfx_tier_regime
  ON trdec_invocations (sfx_authority_tier, sfx_regime)
  WHERE sfx_authority_tier IS NOT NULL;

-- 2. trdec_provenance_events — sfx_* columns
ALTER TABLE trdec_provenance_events
  ADD COLUMN IF NOT EXISTS sfx_context_id UUID,
  ADD COLUMN IF NOT EXISTS sfx_canon_version TEXT,
  ADD COLUMN IF NOT EXISTS sfx_canon_id TEXT;

-- 3. trdec_packets — optional governance context link
ALTER TABLE trdec_packets
  ADD COLUMN IF NOT EXISTS sfx_context_id UUID,
  ADD COLUMN IF NOT EXISTS sfx_canon_version TEXT;
