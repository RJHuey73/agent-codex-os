-- Correction: default EXECUTE grant is to PUBLIC (inherited by anon/authenticated).
-- Revoke from PUBLIC and re-grant service_role so edge-function/service paths keep working.
-- Includes the critical fn_trdec_invoke_db (TD-01): edge fn calls it with service_role.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname IN (
      'fn_canon_draft_escrow_gate','fn_ccx_dispatch_pending',
      'fn_enforce_draft_status_transition','fn_enforce_workflow_context_active',
      'fn_propagate_context_to_execution_log','fn_trdec_invoke_db',
      'trdec_enforce_agent_state_version','trdec_prevent_agents_mutation',
      'trdec_prevent_provenance_mutation','current_canon_version')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $$;
