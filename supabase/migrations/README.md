# supabase/migrations

Applied migration history for Supabase project **agent-codex-os**
(`oufyfdhjjvhrseythgrr`). There are 61 files, from `20260506040747` to `20260804145200`.
They were pulled 1:1 from `supabase_migrations.schema_migrations` on 2026-10-10:
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
