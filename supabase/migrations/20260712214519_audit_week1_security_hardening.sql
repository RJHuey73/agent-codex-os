-- Week-1 hardening (architecture audit 2026-07-12, ADR-005). All reversible.

-- 1. Tighten organizations_insert (was WITH CHECK (true) — unrestricted). Empty table.
--    Minimal safe tightening: require an authenticated identity. Tighten further to
--    owner = auth.uid() when the org model is activated (ADR-004).
ALTER POLICY organizations_insert ON public.organizations WITH CHECK (auth.uid() IS NOT NULL);

-- 2. Revoke public EXECUTE on sensitive SECURITY DEFINER functions.
--    CRITICAL: closes the unauthenticated fn_trdec_invoke_db RPC path (TD-01).
--    Legitimate callers use service_role (retains EXECUTE). Re-grant to reverse.
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
      'trdec_prevent_provenance_mutation')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon, authenticated', r.sig);
  END LOOP;
END $$;

-- 3. current_canon_version: revoke anon only (may back column DEFAULTs for authenticated).
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='current_canon_version'
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
  END LOOP;
END $$;

-- 4. Pin search_path on flagged function.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_block_memory_embeddings_insert'
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.sig);
  END LOOP;
END $$;
