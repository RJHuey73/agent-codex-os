CREATE OR REPLACE FUNCTION public.fn_trdec_invoke_db(
  p_intent text,
  p_payload jsonb,
  p_agent_id text DEFAULT NULL,
  p_governance_trust text DEFAULT 'TRUSTED',
  p_authority_tier integer DEFAULT 1,
  p_regime text DEFAULT 'PROD',
  p_packet_trust_state text DEFAULT 'RATIFIED',
  p_context_id uuid DEFAULT NULL,
  p_binding_id text DEFAULT NULL,
  p_audit boolean DEFAULT false,
  p_metadata jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
  v_http_request_id bigint;
BEGIN
  -- Read Canon version + service key from sfx_system_config
  SELECT canon_version, canon_next_id, ccx_service_key
  INTO v_canon_version, v_canon_next_id, v_service_key
  FROM public.sfx_system_config LIMIT 1;

  v_canon_id   := 'SFX-CANON-' || v_canon_next_id::text;
  v_context_id := COALESCE(p_context_id::text, gen_random_uuid()::text);
  v_binding_id := COALESCE(p_binding_id, 'ccx-system-binding');

  -- Edge URL: hardcoded stable fallback (ALTER DATABASE path blocked on Supabase)
  v_edge_url := 'https://oufyfdhjjvhrseythgrr.supabase.co/functions/v1/fn-trdec-invoke';

  -- Guard: service key must be present
  IF v_service_key IS NULL OR v_service_key = '' THEN
    RETURN jsonb_build_object(
      'status', 'BLOCKED',
      'reason', 'SERVICE_KEY_NOT_CONFIGURED',
      'detail', 'Populate ccx_service_key column in sfx_system_config.',
      'intent', p_intent
    );
  END IF;

  -- Input validation
  IF p_governance_trust NOT IN ('TRUSTED', 'SANDBOXED', 'UNTRUSTED') THEN
    RETURN jsonb_build_object('status', 'ERROR', 'reason', 'governance_trust must be TRUSTED|SANDBOXED|UNTRUSTED');
  END IF;
  IF p_regime NOT IN ('PROD', 'SANDBOX', 'DEV') THEN
    RETURN jsonb_build_object('status', 'ERROR', 'reason', 'regime must be PROD|SANDBOX|DEV');
  END IF;
  IF p_authority_tier < 0 OR p_authority_tier > 5 THEN
    RETURN jsonb_build_object('status', 'ERROR', 'reason', 'authority_tier must be 0-5');
  END IF;

  -- Construct request body (jsonb — matches net.http_post signature)
  v_request_body := jsonb_build_object(
    'intent',             p_intent,
    'payload',            p_payload,
    'audit',              p_audit,
    'packet_trust_state', p_packet_trust_state,
    'governance', jsonb_build_object(
      'context_id',       v_context_id,
      'binding_id',       v_binding_id,
      'authority_tier',   p_authority_tier,
      'governance_trust', p_governance_trust,
      'regime',           p_regime,
      'canon_version',    v_canon_version,
      'canon_id',         v_canon_id
    )
  );

  IF p_agent_id IS NOT NULL THEN
    v_request_body := v_request_body || jsonb_build_object('agent_id', p_agent_id);
  END IF;
  IF p_metadata IS NOT NULL THEN
    v_request_body := v_request_body || jsonb_build_object('metadata', p_metadata);
  END IF;

  -- Fire via pg_net — correct signature: (url, body jsonb, params, headers, timeout)
  SELECT net.http_post(
    url     := v_edge_url,
    body    := v_request_body,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    )
  ) INTO v_http_request_id;

  RETURN jsonb_build_object(
    'status',          'DISPATCHED',
    'http_request_id', v_http_request_id,
    'intent',          p_intent,
    'agent_id',        p_agent_id,
    'governance', jsonb_build_object(
      'canon_version',    v_canon_version,
      'canon_id',         v_canon_id,
      'context_id',       v_context_id,
      'authority_tier',   p_authority_tier,
      'governance_trust', p_governance_trust,
      'regime',           p_regime
    ),
    'note', 'Dispatched async via pg_net. Monitor: SELECT * FROM sfx_v_trdec_status;'
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'status', 'ERROR',
    'error',  SQLERRM,
    'intent', p_intent
  );
END;
$$;
