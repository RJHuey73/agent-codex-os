-- GO-2b step 2 (T0, 2026-10-10): canon-sync-pull sends x-sfx-sync-key, read from
-- Vault at run time. The key never appears in cron.job.command. The job remains
-- PAUSED (GO-P) until the Airtable quota is restored and T0 re-enables it.
SELECT cron.alter_job(
  (SELECT jobid FROM cron.job WHERE jobname = 'canon-sync-pull'),
  command := $cmd$
  SELECT net.http_post(
    url := 'https://oufyfdhjjvhrseythgrr.supabase.co/functions/v1/fn-canon-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sfx-sync-key', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'sfx_sync_key')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 15000
  );
$cmd$
);
