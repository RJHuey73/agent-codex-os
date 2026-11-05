-- GO-K1 (T0, 2026-10-10): fn_ccx_dispatch_pending reads the fn-ccx-ingest service
-- key from Vault (ccx_service_role_key) instead of sfx_system_config.ccx_service_key,
-- so the key can be rotated in Vault and the column nulled. Logic otherwise unchanged.
CREATE OR REPLACE FUNCTION public.fn_ccx_dispatch_pending()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row          ccx_ingestion_queue%ROWTYPE;
  v_request_id   bigint;
  v_function_url text    := 'https://oufyfdhjjvhrseythgrr.supabase.co/functions/v1/fn-ccx-ingest';
  v_service_key  text;
  v_dispatched   integer := 0;
  v_reset_stuck  integer := 0;
  v_batch_limit  integer := 5;
BEGIN
  -- GO-K1: service key comes from Vault (no longer the config column)
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets WHERE name = 'ccx_service_role_key';

  -- Step 1: Reset stuck IN_FLIGHT rows (> 30 min)
  UPDATE ccx_ingestion_queue
  SET ingestion_status   = 'PENDING',
      last_dispatched_at = NULL
  WHERE ingestion_status   = 'IN_FLIGHT'
    AND last_dispatched_at < now() - interval '30 minutes';
  GET DIAGNOSTICS v_reset_stuck = ROW_COUNT;
  IF v_reset_stuck > 0 THEN
    RAISE LOG '[fn_ccx_dispatch_pending] Reset % stuck IN_FLIGHT rows', v_reset_stuck;
  END IF;

  -- Step 2: Dispatch PENDING rows up to batch_limit
  FOR v_row IN
    SELECT * FROM ccx_ingestion_queue
    WHERE ingestion_status = 'PENDING'
    ORDER BY created_at ASC
    LIMIT v_batch_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE ccx_ingestion_queue
    SET ingestion_status   = 'IN_FLIGHT',
        dispatch_count     = dispatch_count + 1,
        last_dispatched_at = now()
    WHERE ingestion_id = v_row.ingestion_id;

    -- net.http_post (pg_net — async, non-blocking)
    SELECT net.http_post(
      url     := v_function_url,
      body    := jsonb_build_object('ingestion_id', v_row.ingestion_id),
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || coalesce(v_service_key, '')
      )
    ) INTO v_request_id;

    UPDATE ccx_ingestion_queue
    SET dispatch_request_id = v_request_id::text
    WHERE ingestion_id = v_row.ingestion_id;

    v_dispatched := v_dispatched + 1;
    RAISE LOG '[fn_ccx_dispatch_pending] Dispatched ingestion_id=% request_id=%',
      v_row.ingestion_id, v_request_id;
  END LOOP;

  RETURN jsonb_build_object(
    'dispatched',    v_dispatched,
    'reset_stuck',   v_reset_stuck,
    'batch_limit',   v_batch_limit,
    'service_key_set', (v_service_key IS NOT NULL AND v_service_key <> ''),
    'executed_at',   now()
  );

EXCEPTION WHEN OTHERS THEN
  RAISE LOG '[fn_ccx_dispatch_pending] ERROR: %', SQLERRM;
  RETURN jsonb_build_object('status', 'error', 'detail', SQLERRM);
END;
$function$;
