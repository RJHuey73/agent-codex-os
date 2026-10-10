
-- ============================================================
-- CCX Ingestion Cron Pipeline
-- Dispatches PENDING ccx_ingestion_queue rows to fn-ccx-ingest
-- via pg_net HTTP POST.
--
-- Architecture:
--   pg_cron (every 10 min) → fn_ccx_dispatch_pending()
--   → pg_net HTTP POST per PENDING row → fn-ccx-ingest
--
-- fn-ccx-ingest handles idempotency: skips non-PENDING rows.
-- Dispatch marks rows IN_FLIGHT to prevent double-dispatch.
-- Stuck IN_FLIGHT rows (>30 min) are reset to PENDING.
--
-- Canon: v9.51.0 | AUTO-CCX-001 | 2026-06-09
-- ============================================================

-- ── 1. Add IN_FLIGHT status to ingestion_status CHECK ────────
-- Current check: PENDING | PROCESSING | INDEXED | REJECTED
-- Add: IN_FLIGHT (dispatch lock), FAILED (permanent failure)
ALTER TABLE ccx_ingestion_queue
  DROP CONSTRAINT IF EXISTS ccx_ingestion_queue_ingestion_status_check;

ALTER TABLE ccx_ingestion_queue
  ADD CONSTRAINT ccx_ingestion_queue_ingestion_status_check
  CHECK (ingestion_status IN (
    'PENDING', 'IN_FLIGHT', 'PROCESSING', 'INDEXED', 'REJECTED', 'FAILED'
  ));

-- ── 2. Add dispatch tracking columns ─────────────────────────
ALTER TABLE ccx_ingestion_queue
  ADD COLUMN IF NOT EXISTS dispatch_count   integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_dispatched_at timestamptz,
  ADD COLUMN IF NOT EXISTS dispatch_request_id text;  -- pg_net request_id for correlation

-- ── 3. Core dispatch function ─────────────────────────────────
CREATE OR REPLACE FUNCTION fn_ccx_dispatch_pending()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_row             ccx_ingestion_queue%ROWTYPE;
  v_request_id      bigint;
  v_function_url    text;
  v_service_key     text;
  v_dispatched      integer := 0;
  v_reset_stuck     integer := 0;
  v_batch_limit     integer := 5;  -- max per cron tick to avoid overload
BEGIN
  -- Resolve Edge Function URL and service key from app config
  -- These are stored in a config table to avoid hardcoding
  SELECT
    current_setting('app.ccx_ingest_url',  true),
    current_setting('app.supabase_service_key', true)
  INTO v_function_url, v_service_key;

  -- Fallback: construct from known project ref
  IF v_function_url IS NULL OR v_function_url = '' THEN
    v_function_url := 'https://oufyfdhjjvhrseythgrr.supabase.co/functions/v1/fn-ccx-ingest';
  END IF;

  -- ── Step 1: Reset stuck IN_FLIGHT rows (>30 min) ────────────
  UPDATE ccx_ingestion_queue
  SET
    ingestion_status  = 'PENDING',
    last_dispatched_at = NULL
  WHERE
    ingestion_status = 'IN_FLIGHT'
    AND last_dispatched_at < now() - interval '30 minutes';

  GET DIAGNOSTICS v_reset_stuck = ROW_COUNT;
  IF v_reset_stuck > 0 THEN
    RAISE LOG '[fn_ccx_dispatch_pending] Reset % stuck IN_FLIGHT rows to PENDING', v_reset_stuck;
  END IF;

  -- ── Step 2: Dispatch PENDING rows (up to batch_limit) ────────
  FOR v_row IN
    SELECT * FROM ccx_ingestion_queue
    WHERE ingestion_status = 'PENDING'
    ORDER BY created_at ASC
    LIMIT v_batch_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Lock row as IN_FLIGHT before dispatching
    UPDATE ccx_ingestion_queue
    SET
      ingestion_status   = 'IN_FLIGHT',
      dispatch_count     = dispatch_count + 1,
      last_dispatched_at = now()
    WHERE ingestion_id = v_row.ingestion_id;

    -- HTTP POST to fn-ccx-ingest
    -- fn-ccx-ingest expects: { "ingestion_id": "uuid" }
    -- It re-reads the row and handles all processing
    SELECT extensions.http_post(
      url     := v_function_url,
      body    := jsonb_build_object('ingestion_id', v_row.ingestion_id)::text,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || coalesce(v_service_key, '')
      )
    ) INTO v_request_id;

    -- Store request ID for correlation / debugging
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
    'executed_at',   now()
  );
END;
$$;

COMMENT ON FUNCTION fn_ccx_dispatch_pending() IS
  'CCX ingestion dispatcher. Called by pg_cron every 10 min. '
  'Dispatches PENDING rows to fn-ccx-ingest via pg_net HTTP POST. '
  'IN_FLIGHT lock prevents double-dispatch. Stuck rows reset after 30 min. '
  'Canon: v9.51.0 | AUTO-CCX-001 | 2026-06-09';

-- ── 4. Schedule the cron job ──────────────────────────────────
-- Run every 10 minutes
SELECT cron.schedule(
  'ccx-ingest-dispatch',       -- job name
  '*/10 * * * *',             -- every 10 minutes
  $$SELECT fn_ccx_dispatch_pending();$$
);

-- ── 5. One-time immediate backfill job ─────────────────────────
-- Runs once at next minute boundary to process the 10 existing PENDING items
-- Will self-deactivate after first run via cron.unschedule
SELECT cron.schedule(
  'ccx-ingest-backfill-once',
  '* * * * *',                -- every minute (will be unscheduled after first run)
  $$
    SELECT fn_ccx_dispatch_pending();
    SELECT cron.unschedule('ccx-ingest-backfill-once');
  $$
);
