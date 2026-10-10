
DO $$
DECLARE
  t text;
  select_only_tables text[] := ARRAY[
    'audit_logs','org_audit_logs',
    'sandbox_audit','purchases','entitlements',
    'org_memberships','org_limits',
    'memory_embeddings','llm_cache'
  ];
BEGIN
  -- api_keys: full revoke, zero anon access
  EXECUTE 'REVOKE ALL ON public.api_keys FROM anon';

  -- Remaining sensitive tables: SELECT-only
  FOREACH t IN ARRAY select_only_tables LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon', t);
    EXECUTE format('GRANT SELECT ON public.%I TO anon', t);
  END LOOP;
END $$;
