-- CRITICAL containment (architecture audit 2026-07-12): sfx_system_config.ccx_service_key
-- held a plaintext service-role secret while policy system_config_read_all (USING true)
-- let anon/authenticated SELECT it. Revoke column-level SELECT so the key is no longer
-- readable via the anon key. Non-breaking: other columns (canon_version, ...) stay readable;
-- service_role and SECURITY DEFINER readers are unaffected. Rotation still REQUIRED (dashboard).
REVOKE SELECT (ccx_service_key) ON public.sfx_system_config FROM anon, authenticated;
