
-- CANON-283: Cross-Project Provenance Protocol — schema additions
-- Adds binding_ref (CPPK) and sfx_binding_id to sfx_canon_drafts
-- Canon: v9.41.0 | SFX-SESSION-20260601-B

ALTER TABLE public.sfx_canon_drafts
  ADD COLUMN IF NOT EXISTS binding_ref UUID,
  ADD COLUMN IF NOT EXISTS sfx_binding_id UUID;

COMMENT ON COLUMN public.sfx_canon_drafts.binding_ref IS
  'Cross-Project Provenance Key (CPPK). Assigned by Make.com at draft creation. '
  'Mirrors artifact_ref in shadowfox-os sfx_provenance_bindings. CANON-283.';

COMMENT ON COLUMN public.sfx_canon_drafts.sfx_binding_id IS
  'binding_id returned from shadowfox-os sfx_provenance_bindings after CPPK write. '
  'Written back by Make.com SFX-CPPK-Bridge-v1. CANON-283.';
