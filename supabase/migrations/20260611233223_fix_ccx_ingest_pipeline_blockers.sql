
-- ================================================================
-- MIGRATION: fix_ccx_ingest_pipeline_blockers
-- Session: SFX-SESSION-20260611 Phase 3
-- Authority: T0 sovereign | Executor: T1
-- Fixes:
--   1. fn_ccx_dispatch_pending: extensions.http_post → net.http_post
--      + read service key from sfx_system_config (not blocked GUC)
--      + send Authorization: Bearer <service_key> correctly
--   2. sfx_system_config (CCX): add sync_key + ccx_service_key columns
--   3. canon-sync-ccx-heartbeat cron: extensions.http_post → net.http_post
--      + add x-sfx-sync-key header
-- ================================================================

-- FIX 2a: Add sync_key and ccx_service_key to CCX sfx_system_config
ALTER TABLE sfx_system_config
  ADD COLUMN IF NOT EXISTS sync_key        text,
  ADD COLUMN IF NOT EXISTS ccx_service_key text;

-- FIX 2b: Store sync_key on CCX (same value as SFX-OS)
UPDATE sfx_system_config
SET sync_key = '<REDACTED: set out-of-band by T0, see supabase/migrations/README.md>';

-- NOTE: ccx_service_key must be set separately by T0 — it is the
-- agent-codex-os service role key, used by fn_ccx_dispatch_pending
-- to authenticate calls to fn-ccx-ingest (verify_jwt=true).
-- Run after migration:
--   UPDATE sfx_system_config SET ccx_service_key = '<CCX_SERVICE_ROLE_KEY>';

-- FIX 1: Rewrite fn_ccx_dispatch_pending
--   - extensions.http_post → net.http_post (pg_net, async)
--   - Read ccx_service_key from sfx_system_config (not blocked GUC)
--   - Authorization header uses that key (valid Supabase JWT for verify_jwt=true)
CREATE OR REPLACE FUNCTION public.fn_ccx_dispatch_pending()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row          ccx_ingestion_queue%ROWTYPE;
  v_request_id   bigint;
  v_function_url text    := 'https://oufyfdhjjvhrseythgrr.supabase.co/functions/v1/fn-ccx-ingest';
  v_service_key  text;
  v_dispatched   integer := 0;
  v_reset_stuck  integer := 0;
  v_batch_limit  integer := 5;
BEGIN
  -- Read service key from config table (avoids blocked GUC on free tier)
  SELECT ccx_service_key INTO v_service_key
  FROM sfx_system_config LIMIT 1;

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
$$;

-- FIX 3: Rebuild canon-sync-ccx-heartbeat cron job
-- Old version used extensions.http_post (wrong) + missing auth header
-- New version uses net.http_post + x-sfx-sync-key from sfx_system_config
SELECT cron.unschedule('canon-sync-ccx-heartbeat');

SELECT cron.schedule(
  'canon-sync-ccx-heartbeat',
  '15 */1 * * *',
  $$
  SELECT net.http_post(
    url     := 'https://mksmwqmphdkwwiyfesad.supabase.co/functions/v1/fn-canon-sync',
    body    := (
      SELECT jsonb_build_object(
        'canon_id',      'SFX-CANON-' || (canon_next_id - 1)::text,
        'canon_version', canon_version,
        'next_id',       canon_next_id,
        'updated_by',    'AUTO-002A-CCX-HEARTBEAT'
      )
      FROM sfx_system_config LIMIT 1
    ),
    headers := (
      SELECT jsonb_build_object(
        'Content-Type',  'application/json',
        'x-sfx-sync-key', sync_key
      )
      FROM sfx_system_config LIMIT 1
    )
  );
  $$
);
