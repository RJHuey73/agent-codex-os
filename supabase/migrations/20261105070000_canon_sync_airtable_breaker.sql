-- DRAFT — not applied. Apply with apply_migration only, after T0 GO.
-- Persistent Airtable 429 breaker for fn-canon-sync (cross-run backoff).
-- Also moves canon-sync-pull to hourly. The job stays INACTIVE; resume is a separate T0 action.

CREATE TABLE IF NOT EXISTS public.sfx_canon_sync_breaker (
  id            integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),  -- singleton
  blocked_until timestamptz,                                    -- NULL = closed
  last_429_at   timestamptz,
  updated_at    timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.sfx_canon_sync_breaker (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

-- Service role only. Edge function uses the service key.
ALTER TABLE public.sfx_canon_sync_breaker ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sfx_canon_sync_breaker FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE ON public.sfx_canon_sync_breaker TO service_role;

COMMENT ON TABLE public.sfx_canon_sync_breaker IS
  'Airtable 429 breaker state for fn-canon-sync. While blocked_until is in the future, the function does not call Airtable.';

-- Hourly cadence. The job stays inactive; resume is a separate T0 action.
SELECT cron.alter_job(
  (SELECT jobid FROM cron.job WHERE jobname = 'canon-sync-pull'),
  schedule := '0 * * * *'
);
