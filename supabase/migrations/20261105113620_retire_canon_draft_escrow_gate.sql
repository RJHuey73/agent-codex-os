-- Retire GAP-04 escrow gate (T0 GO 2026-11-05). Stage 1 of 2: disable, keep objects.
-- Why: fn_canon_draft_escrow_gate reads sfx_service_role_key from sfx_system_config.notes
-- (a column anon/authenticated can SELECT) via notes::jsonb; notes is plain text today,
-- so the lookup cannot succeed. Stage 2 (DROP TRIGGER + DROP FUNCTION) needs a separate GO.
ALTER TABLE public.sfx_canon_drafts DISABLE TRIGGER trg_canon_draft_escrow_gate;

COMMENT ON FUNCTION public.fn_canon_draft_escrow_gate() IS
  'RETIRED 2026-11-05 (T0 GO): trigger trg_canon_draft_escrow_gate disabled. Read a service key from sfx_system_config.notes (anon-readable); never store keys there. Pending DROP. Was: GAP-04 CPPK bind -> shadowfox-os fn_submit_to_escrow via pg_net.';
