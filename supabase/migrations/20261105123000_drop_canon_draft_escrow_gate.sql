-- Retire GAP-04 escrow gate, stage 2 of 2 (T0 GO 2026-11-05): drop.
-- Stage 1 (20261105113620) disabled the trigger. The function had no other users.
--
-- NOT IN supabase_migrations.schema_migrations: apply_migration timed out twice
-- waiting for an approval prompt, so T0 ran these two statements by hand in the
-- SQL editor on 2026-11-05. The version number here is assigned, not recorded.
-- Verified after: trigger and function both absent; sfx_canon_drafts rows unchanged (2).
DROP TRIGGER IF EXISTS trg_canon_draft_escrow_gate ON public.sfx_canon_drafts;
DROP FUNCTION IF EXISTS public.fn_canon_draft_escrow_gate();
