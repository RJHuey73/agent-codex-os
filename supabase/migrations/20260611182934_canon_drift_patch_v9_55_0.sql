
-- CCX Canon Version Drift Patch: v9.51.0 → v9.55.0, next_id 335 → 339
-- T0-authorized: SFX-SESSION-20260611 P1-B (CCX side)
-- Uses update_canon_version RPC (WHERE true safe singleton)

SELECT update_canon_version(
  'v9.55.0',
  339,
  'T1-DRIFT-PATCH-20260611',
  'Drift patch: v9.51.0 → v9.55.0, next_id 335 → 339. T0 sovereign declaration SFX-SESSION-20260611. CANON-337 confirmed last ACTIVE. Next clean ID: SFX-CANON-339. fn-canon-sync upgraded to v2 (RPC-based).'
);
