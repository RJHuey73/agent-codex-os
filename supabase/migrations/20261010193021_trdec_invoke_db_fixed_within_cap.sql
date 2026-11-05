-- GO-4b B1 (T0, 2026-10-10; rulings G1=T2, G3=A01–A05 option a, G4, G5; variant 2).
-- fn_trdec_invoke_db ignores caller-supplied governance and always sends fixed
-- values inside the caps fn-trdec-invoke v5 enforces: authority_tier=2 (T2),
-- packet_trust_state=VALIDATED, regime=PROD, governance_trust=TRUSTED.
-- canon_id is NULL (G5: the previous value, 'SFX-CANON-'||canon_next_id, named an
-- unassigned Canon ID). Same signature (no DROP). p_governance_trust,
-- p_authority_tier, p_regime and p_packet_trust_state are DEPRECATED and ignored,
-- to be removed with GO-3. dry_run is read from p_metadata->>'dry_run'.
CREATE OR REPLACE FUNCTION public.fn_trdec_invoke_db(p_intent text, p_payload jsonb, p_agent_id text DEFAULT NULL::text, p_governance_trust text DEFAULT 'TRUSTED'::text, p_authority_tier integer DEFAULT 1, p_regime text DEFAULT 'PROD'::text, p_packet_trust_state text DEFAULT 'RATIFIED'::text, p_context_id uuid DEFAULT NULL::uuid, p_binding_id text DEFAULT NULL::text, p_audit boolean DEFAULT false, p_metadata jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- Fixed, within-cap governance. The deprecated p_* governance params are ignored.
  c_authority_tier     CONSTANT integer := 2;
  c_governance_trust   CONSTANT text    := 'TRUSTED';
  c_regime             CONSTANT text    := 'PROD';
  c_packet_trust_state CONSTANT text    := 'VALIDATED';

  v_canon_version   text;
  v_edge_url        text := 'https://oufyfdhjjvhrseythgrr.supabase.co/functions/v1/fn-trdec-invoke';
  v_invoke_key      text;
  v_context_id      text;
  v_binding_id      text;
  v_dry_run         boolean := COALESCE((p_metadata->>'dry_run')::boolean, false);
  v_request_body    jsonb;
  v_http_request_id bigint;
BEGIN
  SELECT canon_version INTO v_canon_version FROM public.sfx_system_config LIMIT 1;

  SELECT decrypted_secret INTO v_invoke_key
  FROM vault.decrypted_secrets WHERE name = 'trdec_invoke_key';

  IF v_invoke_key IS NULL OR v_invoke_key = '' THEN
    RETURN jsonb_build_object('status', 'BLOCKED', 'reason', 'INVOKE_KEY_NOT_CONFIGURED',
                              'detail', 'Vault secret trdec_invoke_key is missing.', 'intent', p_intent);
  END IF;

  v_context_id := COALESCE(p_context_id::text, gen_random_uuid()::text);
  v_binding_id := COALESCE(p_binding_id, 'ccx-system-binding');

  v_request_body := jsonb_build_object(
    'intent',             p_intent,
    'payload',            p_payload,
    'audit',              p_audit,
    'dry_run',            v_dry_run,
    'packet_trust_state', c_packet_trust_state,
    'governance', jsonb_build_object(
      'context_id',       v_context_id,
      'binding_id',       v_binding_id,
      'authority_tier',   c_authority_tier,
      'governance_trust', c_governance_trust,
      'regime',           c_regime,
      'canon_version',    v_canon_version,
      'canon_id',         NULL
    )
  );
  IF p_agent_id IS NOT NULL THEN
    v_request_body := v_request_body || jsonb_build_object('agent_id', p_agent_id);
  END IF;
  IF p_metadata IS NOT NULL THEN
    v_request_body := v_request_body || jsonb_build_object('metadata', p_metadata);
  END IF;

  SELECT net.http_post(
    url     := v_edge_url,
    body    := v_request_body,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sfx-sync-key', v_invoke_key)
  ) INTO v_http_request_id;

  RETURN jsonb_build_object(
    'status',          'DISPATCHED',
    'http_request_id', v_http_request_id,
    'intent',          p_intent,
    'agent_id',        p_agent_id,
    'dry_run',         v_dry_run,
    'governance', jsonb_build_object(
      'canon_version',    v_canon_version,
      'canon_id',         NULL,
      'context_id',       v_context_id,
      'authority_tier',   c_authority_tier,
      'governance_trust', c_governance_trust,
      'regime',           c_regime
    ),
    'note', 'Dispatched async via pg_net. Monitor: SELECT * FROM sfx_v_trdec_status;'
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('status', 'ERROR', 'error', SQLERRM, 'intent', p_intent);
END;
$function$;

COMMENT ON FUNCTION public.fn_trdec_invoke_db(text, jsonb, text, text, integer, text, text, uuid, text, boolean, jsonb) IS
  'GO-4b: sends fixed T2/VALIDATED/PROD/TRUSTED, canon_id NULL. p_governance_trust, p_authority_tier, p_regime, p_packet_trust_state are DEPRECATED and ignored (remove with GO-3). dry_run via p_metadata->>''dry_run''.';
