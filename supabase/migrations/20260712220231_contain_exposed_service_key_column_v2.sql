-- Correct containment: a table-level SELECT grant overrides column-level REVOKE, so drop
-- the table grant and re-grant SELECT only on non-secret columns. ccx_service_key becomes
-- unreadable by anon/authenticated; service_role keeps full access. Rotation still REQUIRED.
REVOKE SELECT ON public.sfx_system_config FROM anon, authenticated;
GRANT SELECT (config_id, canon_version, canon_next_id, last_updated_at, updated_by, notes, sync_key)
  ON public.sfx_system_config TO anon, authenticated;
