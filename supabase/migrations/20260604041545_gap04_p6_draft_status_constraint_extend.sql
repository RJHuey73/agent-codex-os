
-- GAP-04 follow-up: extend draft_status CHECK constraint to include
-- UNDER_REVIEW (set by escrow gate trigger) and DEPRECATED
-- Existing values: DRAFT, READY_FOR_RATIFICATION, RATIFIED, REJECTED, SUPERSEDED

ALTER TABLE public.sfx_canon_drafts
  DROP CONSTRAINT IF EXISTS sfx_canon_drafts_draft_status_check;

ALTER TABLE public.sfx_canon_drafts
  ADD CONSTRAINT sfx_canon_drafts_draft_status_check
  CHECK (draft_status IN (
    'DRAFT',
    'UNDER_REVIEW',
    'READY_FOR_RATIFICATION',
    'RATIFIED',
    'REJECTED',
    'SUPERSEDED',
    'DEPRECATED'
  ));

COMMENT ON CONSTRAINT sfx_canon_drafts_draft_status_check ON public.sfx_canon_drafts
  IS 'Extended GAP-04: added UNDER_REVIEW (set by P6 escrow gate on sfx_binding_id attach) and DEPRECATED. CANON-207/211.';
