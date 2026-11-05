
-- agent-codex-os Phase 1A + ERROR fixes
-- Canon: v9.41.0 | SFX-SESSION-20260601-B

-- ── 1. Revoke anon EXECUTE on all SECURITY DEFINER functions ──────────
REVOKE EXECUTE ON FUNCTION public.current_canon_version() FROM anon;
REVOKE EXECUTE ON FUNCTION public.current_canon_version() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_canon_version() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_canon_version() TO service_role;

REVOKE EXECUTE ON FUNCTION public.update_canon_version(text, integer, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_canon_version(text, integer, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_canon_version(text, integer, text, text) TO service_role;

REVOKE EXECUTE ON FUNCTION public.ccx_log_governance_event(text, text, uuid, uuid, text, numeric, integer, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.ccx_log_governance_event(text, text, uuid, uuid, text, numeric, integer, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ccx_log_governance_event(text, text, uuid, uuid, text, numeric, integer, jsonb) TO service_role;

REVOKE EXECUTE ON FUNCTION public.ccx_search_knowledge(vector, numeric, integer, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.ccx_search_knowledge(vector, numeric, integer, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ccx_search_knowledge(vector, numeric, integer, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ccx_search_knowledge(vector, numeric, integer, text, text) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_ccx_candidates_updated_at() FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_candidates_updated_at() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ccx_candidates_updated_at() TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_ccx_governance_event_dispatch() FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_governance_event_dispatch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ccx_governance_event_dispatch() TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_arbitrated_canon_link(uuid, text[], uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_arbitrated_canon_link(uuid, text[], uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ccx_mutate_arbitrated_canon_link(uuid, text[], uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_cluster_reinforcement(uuid, text[], uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_cluster_reinforcement(uuid, text[], uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ccx_mutate_cluster_reinforcement(uuid, text[], uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_cold_mark(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_cold_mark(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ccx_mutate_cold_mark(uuid, uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_conflict_resolution(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_conflict_resolution(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ccx_mutate_conflict_resolution(uuid, uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_high_conf_retrieval(uuid, text[], uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_high_conf_retrieval(uuid, text[], uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ccx_mutate_high_conf_retrieval(uuid, text[], uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_invalidation(uuid, text[], uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_mutate_invalidation(uuid, text[], uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ccx_mutate_invalidation(uuid, text[], uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM anon;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rls_auto_enable() TO service_role;

-- ── 2. Fix SECURITY DEFINER views → SECURITY INVOKER ─────────────────
-- Must DROP and recreate with exact original column definitions
DROP VIEW IF EXISTS public.sfx_p5_agent_messages;
CREATE VIEW public.sfx_p5_agent_messages
  WITH (security_invoker = true)
AS
  SELECT id, trace_id, created_at, payload,
         from_agent AS from_node,
         to_agent AS to_node,
         type AS message_type
  FROM agent_messages;

DROP VIEW IF EXISTS public.sfx_v_governed_runs;
CREATE VIEW public.sfx_v_governed_runs
  WITH (security_invoker = true)
AS
  SELECT id AS run_id, agent_id, status,
         sfx_governed, sfx_regime, sfx_authority_tier,
         sfx_authority_chain, sfx_context_id, sfx_binding_id,
         sfx_canon_version,
         CASE
           WHEN sfx_governed = false THEN 'UNGOVERNED — PROVISIONAL'
           WHEN sfx_regime IS NULL   THEN 'GOVERNED — REGIME UNSET'
           ELSE sfx_regime
         END AS effective_regime,
         created_at, completed_at
  FROM runs r;

-- ── 3. Fix mutable search_path on governance functions ─────────────────
ALTER FUNCTION public.fn_enforce_agent_class_authority() SET search_path = public;
ALTER FUNCTION public.fn_enforce_pse_governance() SET search_path = public;

-- ── 4. Bootstrap policies for RLS-enabled / no-policy tables ──────────
CREATE POLICY acx_service_write ON public.agent_messages
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY acx_authenticated_read ON public.agent_messages
  FOR SELECT TO authenticated USING (true);

CREATE POLICY acx_service_write ON public.audit_logs
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY acx_authenticated_read ON public.audit_logs
  FOR SELECT TO authenticated USING (true);

CREATE POLICY acx_service_write ON public.llm_cache
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY acx_authenticated_read ON public.llm_cache
  FOR SELECT TO authenticated USING (true);
