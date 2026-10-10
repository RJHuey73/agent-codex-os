
-- ============================================================
-- AUTO-002A: Canon sync trigger — agent-codex-os side
-- When fn-canon-sync updates agent-codex-os sfx_system_config,
-- push the same values back to shadowfox-os via pg_net.
-- This closes the loop without requiring SFX_SERVICE_ROLE_KEY
-- in fn-canon-sync's environment.
--
-- Canon: v9.51.0 | AUTO-002A-CCX | 2026-06-09
-- ============================================================

CREATE OR REPLACE FUNCTION fn_canon_sync_mirror_to_sfx()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sfx_url    text := 'https://mksmwqmphdkwwiyfesad.supabase.co/rest/v1/sfx_system_config';
  v_request_id bigint;
BEGIN
  IF NEW.canon_version IS DISTINCT FROM OLD.canon_version
     OR NEW.canon_next_id IS DISTINCT FROM OLD.canon_next_id
  THEN
    -- PATCH shadowfox-os sfx_system_config via REST API
    -- Uses service role key from env (standard SUPABASE_SERVICE_ROLE_KEY on this project
    -- points to agent-codex-os — we need the shadowfox-os key here)
    -- Stored as SFX_SERVICE_ROLE_KEY secret (pending manual set)
    -- Falls back gracefully: if key absent, logs and skips
    DECLARE
      v_sfx_key text := current_setting('app.sfx_service_role_key', true);
    BEGIN
      IF v_sfx_key IS NULL OR v_sfx_key = '' THEN
        RAISE LOG '[fn_canon_sync_mirror] SFX service key not set — shadowfox-os mirror skipped. Set app.sfx_service_role_key via: ALTER DATABASE postgres SET app.sfx_service_role_key = ''<key>'';';
        RETURN NEW;
      END IF;

      SELECT extensions.http_post(
        url     := 'https://mksmwqmphdkwwiyfesad.supabase.co/functions/v1/fn-canon-sync',
        body    := jsonb_build_object(
                     'canon_id',      'SFX-CANON-' || (NEW.canon_next_id - 1)::text,
                     'canon_version', NEW.canon_version,
                     'next_id',       NEW.canon_next_id,
                     'updated_by',    'AUTO-002A-CCX-MIRROR'
                   )::text,
        headers := jsonb_build_object('Content-Type', 'application/json')
      ) INTO v_request_id;

      RAISE LOG '[fn_canon_sync_mirror] Mirrored to shadowfox-os: version=% next_id=% request_id=%',
        NEW.canon_version, NEW.canon_next_id, v_request_id;
    END;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_canon_sync_mirror_to_sfx
AFTER UPDATE ON sfx_system_config
FOR EACH ROW
EXECUTE FUNCTION fn_canon_sync_mirror_to_sfx();

COMMENT ON TRIGGER trg_canon_sync_mirror_to_sfx ON sfx_system_config IS
  'Mirrors canon_version/next_id changes back to shadowfox-os via fn-canon-sync. '
  'Requires app.sfx_service_role_key DB setting. '
  'When key is set: ALTER DATABASE postgres SET app.sfx_service_role_key = ''<shadowfox-os service_role key>''; '
  'Canon: v9.51.0 | AUTO-002A-CCX';

-- ── 30-min cron on CCX side as belt-and-suspenders ───────────
-- Ensures alignment even if triggers miss edge cases
SELECT cron.schedule(
  'canon-sync-ccx-heartbeat',
  '15 */1 * * *',   -- offset from SFX side (fires at :15 past each hour)
  $$
    SELECT extensions.http_post(
      url     := 'https://mksmwqmphdkwwiyfesad.supabase.co/functions/v1/fn-canon-sync',
      body    := (SELECT jsonb_build_object(
                    'canon_id',      'SFX-CANON-' || (canon_next_id - 1)::text,
                    'canon_version', canon_version,
                    'next_id',       canon_next_id,
                    'updated_by',    'AUTO-002A-CCX-HEARTBEAT'
                  )::text FROM sfx_system_config LIMIT 1),
      headers := jsonb_build_object('Content-Type','application/json')
    );
  $$
);
