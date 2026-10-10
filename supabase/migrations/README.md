# supabase/migrations

Applied migration history for Supabase project **agent-codex-os**
(`oufyfdhjjvhrseythgrr`). There are 65 files, from `20260506040747` to `20261010162801`.
They were pulled 1:1 from `supabase_migrations.schema_migrations` on 2026-10-10 (the last four were applied that day under T0 GO-2a / GO-P / GO-2b):
each file is that row's `statements`, joined in order.

This directory mirrors what is already live. It is not a deploy source.

- Change the schema only through Supabase MCP `apply_migration`, then pull the
  new row back into this directory. Don't hand-edit a file that has already been applied.
- There is deliberately no `supabase/config.toml`. Linking this repo to the
  Supabase GitHub integration would deploy on merge, and agent-codex-os is GATED
  until T0 gives a GO.

## Redaction (one file is not byte-identical to the live row)

`20260611233223_fix_ccx_ingest_pipeline_blockers.sql`, line 22, originally set
`sfx_system_config.sync_key` to a plaintext shared secret: the
`x-sfx-sync-key` credential used by `fn_canon_sync_mirror_to_sfx()`. The value
is replaced with a placeholder. Replaying that file sets a placeholder, not the
real key, so the key has to be set separately by T0.

The secret scan (detect-secrets 1.x plus targeted patterns for JWTs, `sb_*`
keys, `sk-`, `AIza`, `gh*_`, bearer literals, credentialed URLs and quoted
key assignments) found nothing else. The `ccx_service_key` lines are comments
holding a `<…>` placeholder, not a value.

## Sync-key remediation (2026-10-10)

- `20261010162622`: anon/authenticated can no longer read `sfx_system_config.sync_key`.
  That value is burned and is not used anywhere.
- `20261010162642`: `canon-sync-pull` cron **paused** (Airtable 429 billing limit).
- `20261010162723`: fresh key generated in-DB into Vault (`sfx_sync_key`), plus
  `fn_sfx_sync_key_matches()` (service_role only).
- `20261010162801`: cron sends `x-sfx-sync-key` read from Vault at run time.
- Edge function source: `supabase/functions/fn-canon-sync/index.ts` (v7, fails closed).
