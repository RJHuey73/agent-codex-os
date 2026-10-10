
-- ============================================================
-- SFX CPPK BRIDGE — CANON DRAFTS SCHEMA EXTENSION
-- Canon: v9.41.0 | CANON-283 | Session: 2026-06-01 | T0={∆§/π}™
--
-- Adds two fields to sfx_canon_drafts (agent-codex-os):
--   binding_ref   — the Cross-Project Provenance Key (CPPK)
--   sfx_binding_id — binding_id echoed back from shadowfox-os
--
-- These fields enable machine-verifiable cross-DB provenance
-- without FKs or FDW. Make.com orchestrates the write.
-- ============================================================

ALTER TABLE public.sfx_canon_drafts
  ADD COLUMN IF NOT EXISTS binding_ref UUID,
  ADD COLUMN IF NOT EXISTS sfx_binding_id UUID;

COMMENT ON COLUMN public.sfx_canon_drafts.binding_ref IS
  'Cross-Project Provenance Key (CPPK). UUID assigned by Make.com at draft creation. '
  'Mirrors artifact_ref in shadowfox-os.sfx_provenance_bindings. '
  'Required for ratification gate advancement past PRE_RATIFIED. CANON-283.';

COMMENT ON COLUMN public.sfx_canon_drafts.sfx_binding_id IS
  'binding_id returned from shadowfox-os sfx_provenance_bindings after CPPK write. '
  'Written back by Make.com scenario SFX-CPPK-Bridge-v1. '
  'Null = bridge not yet executed. CANON-283.';
