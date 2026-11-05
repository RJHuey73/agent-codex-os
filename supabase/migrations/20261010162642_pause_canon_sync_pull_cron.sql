-- GO-P (T0, 2026-10-10): pause canon-sync-pull. Every run since >=2026-10-09 fails
-- with Airtable 429 PUBLIC_API_BILLING_LIMIT_EXCEEDED and burns quota.
-- Reverse with: select cron.alter_job((select jobid from cron.job where jobname='canon-sync-pull'), active := true);
SELECT cron.alter_job(
  (SELECT jobid FROM cron.job WHERE jobname = 'canon-sync-pull'),
  active := false
);
