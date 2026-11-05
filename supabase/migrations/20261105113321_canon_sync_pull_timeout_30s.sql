-- canon-sync-pull: raise pg_net timeout 15s -> 30s (T0 GO 2026-11-05).
-- A cold start took ~15.3s at 10:00Z; the function returned 200 but pg_net recorded timed_out.
DO $$
DECLARE v_cmd text;
BEGIN
  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'canon-sync-pull';
  IF v_cmd IS NULL OR position('timeout_milliseconds := 15000' in v_cmd) = 0 THEN
    RAISE EXCEPTION 'canon-sync-pull command not in expected shape; aborting';
  END IF;
  PERFORM cron.alter_job(
    job_id  := (SELECT jobid FROM cron.job WHERE jobname = 'canon-sync-pull'),
    command := replace(v_cmd, 'timeout_milliseconds := 15000', 'timeout_milliseconds := 30000')
  );
END $$;
