-- GO-K step 5 (T0, 2026-10-10): the secret key once stored here was readable by
-- anon until 2026-07-12. T0 rotated it on 2026-10-10 (new key in Vault
-- ccx_service_role_key; old key deleted, now rejected with 401). No function
-- reads this column since 20261010 ccx_dispatch_read_service_key_from_vault.
-- Null the dead copy. Dropping the column is left to a later migration.
UPDATE public.sfx_system_config SET ccx_service_key = NULL WHERE ccx_service_key IS NOT NULL;
COMMENT ON COLUMN public.sfx_system_config.ccx_service_key IS
  'DEPRECATED 2026-10-10: always NULL. The fn-ccx-ingest key lives in Vault (ccx_service_role_key). Do not store secrets here.';
