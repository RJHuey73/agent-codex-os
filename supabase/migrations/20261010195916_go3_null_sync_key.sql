-- GO-3 (T0 2026-10-10), agent-codex-os.
-- The burned sync_key is read by nothing: fn-canon-sync and the canon-sync
-- cron use Vault `sfx_sync_key`; fn-trdec-invoke uses Vault `trdec_invoke_key`.
-- ccx_service_key was nulled in 20261010191919. Column drops follow separately.
UPDATE public.sfx_system_config SET sync_key = NULL WHERE sync_key IS NOT NULL;
UPDATE public.sfx_system_config SET ccx_service_key = NULL WHERE ccx_service_key IS NOT NULL;

COMMENT ON COLUMN public.sfx_system_config.sync_key IS
  'DEPRECATED (GO-3, 2026-10-10): burned shared key, nulled. Superseded by Vault sfx_sync_key / trdec_invoke_key. Pending DROP.';
