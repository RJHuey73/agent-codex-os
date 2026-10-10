-- GO-2b step 1 (T0, 2026-10-10): fresh x-sfx-sync-key generated inside the DB and
-- stored in Vault. The value is never written to a migration, git, or an env var,
-- and never returned to callers: fn-canon-sync verifies via fn_sfx_sync_key_matches().
-- The burned sfx_system_config.sync_key value is NOT reused.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'sfx_sync_key') THEN
    PERFORM vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'sfx_sync_key',
      'x-sfx-sync-key for fn-canon-sync (GO-2b 2026-10-10)'
    );
  END IF;
END $$;

-- Compares hashes so the comparison time does not depend on how many
-- leading characters match. Returns false (fail closed) if either side is missing.
CREATE OR REPLACE FUNCTION public.fn_sfx_sync_key_matches(p_key text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_expected text;
BEGIN
  SELECT decrypted_secret INTO v_expected
  FROM vault.decrypted_secrets
  WHERE name = 'sfx_sync_key';

  IF v_expected IS NULL OR v_expected = '' OR p_key IS NULL OR p_key = '' THEN
    RETURN false;
  END IF;

  RETURN extensions.digest(p_key, 'sha256') = extensions.digest(v_expected, 'sha256');
END;
$$;

REVOKE ALL ON FUNCTION public.fn_sfx_sync_key_matches(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_sfx_sync_key_matches(text) TO service_role;
