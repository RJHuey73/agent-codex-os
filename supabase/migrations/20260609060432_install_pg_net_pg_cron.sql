
-- Install pg_net (HTTP from SQL) and pg_cron (scheduled jobs)
-- Required for: CCX ingestion trigger (pg_cron → pg_net → fn-ccx-ingest)
-- and AUTO-002A fallback path

CREATE EXTENSION IF NOT EXISTS pg_net SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Verify
SELECT extname, extversion 
FROM pg_extension 
WHERE extname IN ('pg_net', 'pg_cron');
