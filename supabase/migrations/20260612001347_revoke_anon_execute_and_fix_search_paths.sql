
-- Revoke anon EXECUTE from all SECURITY DEFINER functions
REVOKE EXECUTE ON FUNCTION public.fn_canon_draft_escrow_gate()            FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_canon_sync_mirror_to_sfx()           FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_ccx_dispatch_pending()               FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_enforce_draft_status_transition()     FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_enforce_workflow_context_active()     FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_propagate_context_to_execution_log()  FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_trdec_invoke_db(
  text, jsonb, text, text, integer, text, text, uuid, text, boolean, jsonb
) FROM anon;

-- Fix mutable search_path on trigger functions (RETURNS trigger, drop/recreate required)
DROP FUNCTION IF EXISTS public.fn_canon_sync_mirror_to_sfx() CASCADE;
CREATE FUNCTION public.fn_canon_sync_mirror_to_sfx()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM net.http_post(
    url     := (SELECT sfx_supabase_url  FROM sfx_system_config LIMIT 1) || '/functions/v1/fn-canon-sync',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'Authorization',  'Bearer ' || (SELECT sfx_service_role_key FROM sfx_system_config LIMIT 1),
      'x-sfx-sync-key', (SELECT sync_key             FROM sfx_system_config LIMIT 1)
    ),
    body := jsonb_build_object(
      'version', (SELECT canon_version  FROM sfx_system_config LIMIT 1),
      'next_id',  (SELECT next_clean_id  FROM sfx_system_config LIMIT 1),
      'source',  'ccx-trigger'
    )
  );
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.fn_canon_sync_mirror_to_sfx() FROM anon;

DROP FUNCTION IF EXISTS public.trdec_prevent_provenance_mutation() CASCADE;
CREATE FUNCTION public.trdec_prevent_provenance_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.ratified_in IS DISTINCT FROM NEW.ratified_in OR
       OLD.agent_id    IS DISTINCT FROM NEW.agent_id THEN
      RAISE EXCEPTION 'PROVENANCE_IMMUTABLE: ratified_in and agent_id are write-once';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.trdec_prevent_provenance_mutation() FROM anon;

DROP FUNCTION IF EXISTS public.trdec_prevent_agents_mutation() CASCADE;
CREATE FUNCTION public.trdec_prevent_agents_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    RAISE EXCEPTION 'AGENTS_IMMUTABLE: trdec_agents rows are write-once after ratification';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.trdec_prevent_agents_mutation() FROM anon;

DROP FUNCTION IF EXISTS public.trdec_enforce_agent_state_version() CASCADE;
CREATE FUNCTION public.trdec_enforce_agent_state_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.version <= OLD.version THEN
      RAISE EXCEPTION 'STATE_VERSION_REGRESSION: new version (%) must exceed current (%)',
        NEW.version, OLD.version;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.trdec_enforce_agent_state_version() FROM anon;
