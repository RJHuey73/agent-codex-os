
-- GAP-05: Tridecagon Invocation Path
-- 1. DB-callable invocation wrapper (Make.com RPC target)
-- 2. Live status view over all trdec tables
-- 3. HARMONIC agent invocation_surface activation (CANON-318 live)

-- ─── 1. fn_trdec_invoke_db: governed RPC wrapper ─────────────────────────────
-- Callable via Supabase REST /rpc/fn_trdec_invoke_db
-- Constructs governance envelope from sfx_system_config + caller params
-- Fires HTTP POST to fn-trdec-invoke edge function via pg_net
-- Returns full invocation result JSON

CREATE OR REPLACE FUNCTION public.fn_trdec_invoke_db(
  p_intent          text,
  p_payload         jsonb,
  p_agent_id        text     DEFAULT NULL,
  p_governance_trust text    DEFAULT 'TRUSTED',
  p_authority_tier  integer  DEFAULT 1,
  p_regime          text     DEFAULT 'PROD',
  p_packet_trust_state text  DEFAULT 'RATIFIED',
  p_context_id      uuid     DEFAULT NULL,
  p_binding_id      text     DEFAULT NULL,
  p_audit           boolean  DEFAULT false,
  p_metadata        jsonb    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_canon_version   text;
  v_canon_next_id   integer;
  v_edge_url        text;
  v_service_key     text;
  v_canon_id        text;
  v_context_id      text;
  v_binding_id      text;
  v_request_body    jsonb;
  v_net_response    jsonb;
  v_http_request_id bigint;
BEGIN
  -- Read Canon version from sfx_system_config
  SELECT canon_version, canon_next_id
  INTO v_canon_version, v_canon_next_id
  FROM public.sfx_system_config LIMIT 1;

  -- Build runtime references
  v_canon_id    := 'SFX-CANON-' || v_canon_next_id::text;
  v_context_id  := COALESCE(p_context_id::text,
    (SELECT context_id::text FROM public.sfx_governance_context
     WHERE is_active = true ORDER BY created_at DESC LIMIT 1));
  v_binding_id  := COALESCE(p_binding_id,
    (SELECT binding_id::text FROM public.sfx_agent_registry
     WHERE agent_id = 'T1-CLAUDE' LIMIT 1),
    'ccx-system-binding');

  -- Build edge function URL from env (injected at deploy time)
  v_edge_url := current_setting('app.ccx_edge_base_url', true);
  IF v_edge_url IS NULL OR v_edge_url = '' THEN
    -- Fallback: derive from Supabase project ref
    v_edge_url := 'https://oufyfdhjjvhrseythgrr.supabase.co/functions/v1/fn-trdec-invoke';
  END IF;

  v_service_key := current_setting('app.ccx_service_role_key', true);
  IF v_service_key IS NULL OR v_service_key = '' THEN
    RETURN jsonb_build_object(
      'status', 'BLOCKED',
      'reason', 'SERVICE_KEY_NOT_CONFIGURED',
      'detail', 'Set app.ccx_service_role_key via ALTER DATABASE ... SET or Supabase secrets',
      'intent', p_intent
    );
  END IF;

  -- Validate inputs
  IF p_governance_trust NOT IN ('TRUSTED', 'SANDBOXED', 'UNTRUSTED') THEN
    RETURN jsonb_build_object('status', 'ERROR', 'reason', 'Invalid governance_trust');
  END IF;
  IF p_regime NOT IN ('PROD', 'SANDBOX', 'DEV') THEN
    RETURN jsonb_build_object('status', 'ERROR', 'reason', 'Invalid regime');
  END IF;
  IF p_authority_tier < 0 OR p_authority_tier > 5 THEN
    RETURN jsonb_build_object('status', 'ERROR', 'reason', 'authority_tier must be 0-5');
  END IF;

  -- Construct full request body
  v_request_body := jsonb_build_object(
    'intent',             p_intent,
    'payload',            p_payload,
    'audit',              p_audit,
    'packet_trust_state', p_packet_trust_state,
    'governance', jsonb_build_object(
      'context_id',      v_context_id,
      'binding_id',      v_binding_id,
      'authority_tier',  p_authority_tier,
      'governance_trust', p_governance_trust,
      'regime',          p_regime,
      'canon_version',   v_canon_version,
      'canon_id',        v_canon_id
    )
  );

  -- Add optional fields
  IF p_agent_id IS NOT NULL THEN
    v_request_body := v_request_body || jsonb_build_object('agent_id', p_agent_id);
  END IF;
  IF p_metadata IS NOT NULL THEN
    v_request_body := v_request_body || jsonb_build_object('metadata', p_metadata);
  END IF;

  -- Fire async HTTP POST via pg_net
  SELECT net.http_post(
    url     := v_edge_url,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body    := v_request_body::text
  ) INTO v_http_request_id;

  RETURN jsonb_build_object(
    'status',          'DISPATCHED',
    'http_request_id', v_http_request_id,
    'intent',          p_intent,
    'agent_id',        p_agent_id,
    'governance', jsonb_build_object(
      'canon_version',  v_canon_version,
      'canon_id',       v_canon_id,
      'context_id',     v_context_id,
      'authority_tier', p_authority_tier,
      'governance_trust', p_governance_trust,
      'regime',         p_regime
    ),
    'note', 'Invocation dispatched async via pg_net. Query trdec_invocations for result.'
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'status', 'ERROR',
    'error',  SQLERRM,
    'intent', p_intent
  );
END;
$$;

COMMENT ON FUNCTION public.fn_trdec_invoke_db(text, jsonb, text, text, integer, text, text, uuid, text, boolean, jsonb)
  IS 'GAP-05. Governed RPC wrapper for fn-trdec-invoke edge function. Callable via Supabase REST /rpc/fn_trdec_invoke_db or Make.com HTTP module. Constructs full GovernanceEnvelope from sfx_system_config, fires async HTTP POST via pg_net. Requires app.ccx_service_role_key set. CANON-304/305/306/317/318.';

-- ─── 2. Live status view ──────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.sfx_v_trdec_status AS
WITH inv_stats AS (
  SELECT
    agent_id,
    COUNT(*)                                               AS total_invocations,
    COUNT(*) FILTER (WHERE result_status = 'SUCCESS')      AS success_count,
    COUNT(*) FILTER (WHERE result_status = 'HARD_STOP')    AS hard_stop_count,
    COUNT(*) FILTER (WHERE result_status = 'ERROR')        AS error_count,
    MAX(created_at)                                        AS last_invocation_at
  FROM public.trdec_invocations
  GROUP BY agent_id
),
state_snap AS (
  SELECT agent_id, current_state, version, updated_at
  FROM public.trdec_agent_state
)
SELECT
  a.agent_id,
  a.canonical_name,
  a.class,
  a.cluster_id,
  a.trust_state_floor,
  a.invocable,
  COALESCE(i.total_invocations, 0)  AS total_invocations,
  COALESCE(i.success_count, 0)      AS success_count,
  COALESCE(i.hard_stop_count, 0)    AS hard_stop_count,
  COALESCE(i.error_count, 0)        AS error_count,
  i.last_invocation_at,
  s.version                          AS state_version,
  s.updated_at                       AS state_updated_at,
  CASE
    WHEN i.total_invocations IS NULL THEN 'NEVER_INVOKED'
    WHEN i.last_invocation_at > now() - interval '1 hour' THEN 'RECENTLY_ACTIVE'
    WHEN i.last_invocation_at > now() - interval '24 hours' THEN 'ACTIVE_TODAY'
    ELSE 'IDLE'
  END AS activity_status,
  a.ratified_in
FROM public.trdec_agents a
LEFT JOIN inv_stats  i ON i.agent_id = a.agent_id
LEFT JOIN state_snap s ON s.agent_id = a.agent_id
WHERE a.agent_id != 'TRDEC-WITNESS'  -- Witness is non-invocable sovereign anchor
ORDER BY a.cluster_id, a.agent_id;

COMMENT ON VIEW public.sfx_v_trdec_status
  IS 'GAP-05. Live Tridecagon operational dashboard. Aggregates invocation counts, success/hard-stop/error rates, last invocation time, and agent state version per agent. Excludes TRDEC-WITNESS (non-invocable). CANON-306/317/318.';

-- ─── 3. Activate HARMONIC agent invocation surfaces (CANON-318 live) ──────────
-- trdec_prevent_agents_mutation allows updates to invocation_surface (lifecycle field)
-- Identity fields (agent_id, canonical_name, class, cluster_id, etc.) are NOT changed

UPDATE public.trdec_agents
SET invocation_surface = '{"surfaces": ["fn_trdec_invoke_db", "fn-trdec-invoke"]}'::jsonb
WHERE agent_id IN (
  'TRDEC-A06', 'TRDEC-A07', 'TRDEC-A08',
  'TRDEC-A09', 'TRDEC-A10', 'TRDEC-A11',
  'TRDEC-A12', 'TRDEC-A13'
);

-- Also update CORE agents to add fn_trdec_invoke_db surface explicitly
UPDATE public.trdec_agents
SET invocation_surface = jsonb_set(
  invocation_surface,
  '{surfaces}',
  (invocation_surface->'surfaces') || '["fn_trdec_invoke_db"]'::jsonb
)
WHERE agent_id IN ('TRDEC-A01', 'TRDEC-A02', 'TRDEC-A03', 'TRDEC-A04', 'TRDEC-A05')
  AND NOT (invocation_surface->'surfaces' @> '["fn_trdec_invoke_db"]');
