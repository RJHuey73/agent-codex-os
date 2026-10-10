# supabase/migrations

Applied migration history for Supabase project **agent-codex-os**
(`oufyfdhjjvhrseythgrr`). There are 70 files, from `20260506040747` to `20261010195916`.
They were pulled 1:1 from `supabase_migrations.schema_migrations` on 2026-10-10 (the last nine were applied that day under T0 GO-2a / GO-P / GO-2b / GO-4a / GO-K / GO-4b / GO-3):
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

## Edge function auth hardening (2026-10-10, GO-4a / GO-4c)

- `20261010172137`: separate Vault key `trdec_invoke_key` and verifier
  `fn_trdec_invoke_key_matches()` (service_role only). `fn_trdec_invoke_db` now
  sends `x-sfx-sync-key` from Vault and no longer sends `ccx_service_key` as a Bearer token.
- `supabase/functions/fn-trdec-invoke/index.ts` (v4, deployed as version 15): checks the
  key in the database and accepts it only from the `x-sfx-sync-key` header. 500
  responses no longer return error detail.
- `supabase/functions/run-agent/index.ts` (deployed as version 31): disabled; returns 410 Gone.

## Service key rotation (2026-10-10, GO-K)

The fn-ccx-ingest secret key was readable by anon until 2026-07-12 and had not
been rotated. T0 created a new secret key (`ccx_ingest_dispatch`) and set it in
Vault (`ccx_service_role_key`) through the dashboard, so it never passed through
an agent. The old `default` key was then deleted, and a probe now gets 401.
- `20261010190554`: `fn_ccx_dispatch_pending` reads the key from Vault.
- `20261010191919`: `sfx_system_config.ccx_service_key` set to NULL and marked deprecated.

## Governance caps on fn-trdec-invoke (2026-10-10, GO-4b)

T0 rulings: G1 authority cap = T2. G3 live agents = A01–A05, enforced by a code
allowlist (option a). The ratified `trdec_agents` rows are untouched, because an
immutability trigger keeps them write-once.
- `20261010193021`: `fn_trdec_invoke_db` sends fixed T2 / VALIDATED / PROD / TRUSTED
  values and `canon_id` NULL. Its old governance parameters are deprecated and ignored.
- `supabase/functions/fn-trdec-invoke/` v5 (deployed as version 18), with `policy.ts`
  unit-tested in `policy.test.ts`. A claim above T2, trust above VALIDATED, or an
  `agent_id` that differs from the router's choice returns 403 before any write.
  Outputs carry a server-side ProvenanceBinding (`sfx-t2`, `ratified=false`).

## Floor enforcement and sync_key retirement (2026-10-10, `enforce` / GO-3)

- `supabase/functions/fn-trdec-invoke/` v6 (deployed as version 19): the packet's
  trust must meet the routed agent's `trdec_agents.trust_state_floor`, compared by
  enum rank; below floor (or an unknown floor) returns 403 `BELOW_AGENT_FLOOR`
  before any write.
- `fn-trdec-invoke` v7 (deployed as version 20, T0 A05 ruling `code reject`): a
  code-level floor raises A05 (Liaison) to RATIFIED, matching its own runtime
  check, so it is refused before any write. At the T2 / VALIDATED cap only A03
  is reachable.
- GO-test (2026-10-10): one real A03 call, `regime=SANDBOX`, context
  `GO-TEST-20261010-A03`, payload tagged `test: true`. Wrote exactly the expected
  rows (2 packets, 1 invocation, 1 provenance event, 1 agent state, 0
  transitions): SUCCESS, VALIDATED → VALIDATED, `canon_id` NULL, provenance
  `sfx-t2` / `ratified=false` / `bound_by: fn-trdec-invoke v7`. The rows are
  append-only and permanent.
- `20261010195916`: nulls `sync_key` (the burned key) and `ccx_service_key`. The
  column DROPs and the removal of `fn_trdec_invoke_db`'s deprecated parameters
  are pending a separate confirmation of the destructive statements.
