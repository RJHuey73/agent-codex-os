-- GO-2a (T0, 2026-10-10): sync_key was SELECT-granted to anon/authenticated by
-- 20260712220231. Re-grant the same column set minus sync_key. Table-level revoke
-- first because a table grant would override column-level revokes.
-- The burned sync_key value must not be reused as SFX_SYNC_KEY.
REVOKE SELECT ON public.sfx_system_config FROM anon, authenticated;
GRANT SELECT (config_id, canon_version, canon_next_id, last_updated_at, updated_by, notes)
  ON public.sfx_system_config TO anon, authenticated;
