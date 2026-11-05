
-- Drop and recreate sfx_v_trdec_status as SECURITY INVOKER
-- Eliminates SECURITY DEFINER bypass of RLS
DROP VIEW IF EXISTS public.sfx_v_trdec_status;

CREATE VIEW public.sfx_v_trdec_status
WITH (security_invoker = true)
AS
WITH inv_stats AS (
  SELECT
    agent_id,
    count(*) AS total_invocations,
    count(*) FILTER (WHERE result_status = 'SUCCESS') AS success_count,
    count(*) FILTER (WHERE result_status = 'HARD_STOP') AS hard_stop_count,
    count(*) FILTER (WHERE result_status = 'ERROR') AS error_count,
    max(created_at) AS last_invocation_at
  FROM trdec_invocations
  GROUP BY agent_id
),
state_snap AS (
  SELECT agent_id, current_state, version, updated_at
  FROM trdec_agent_state
)
SELECT
  a.agent_id,
  a.canonical_name,
  a.class,
  a.cluster_id,
  a.trust_state_floor,
  a.invocable,
  COALESCE(i.total_invocations, 0) AS total_invocations,
  COALESCE(i.success_count, 0)     AS success_count,
  COALESCE(i.hard_stop_count, 0)   AS hard_stop_count,
  COALESCE(i.error_count, 0)       AS error_count,
  i.last_invocation_at,
  s.version    AS state_version,
  s.updated_at AS state_updated_at,
  CASE
    WHEN i.total_invocations IS NULL                          THEN 'NEVER_INVOKED'
    WHEN i.last_invocation_at > now() - INTERVAL '1 hour'    THEN 'RECENTLY_ACTIVE'
    WHEN i.last_invocation_at > now() - INTERVAL '24 hours'  THEN 'ACTIVE_TODAY'
    ELSE 'IDLE'
  END AS activity_status,
  a.ratified_in
FROM trdec_agents a
LEFT JOIN inv_stats  i ON i.agent_id = a.agent_id
LEFT JOIN state_snap s ON s.agent_id = a.agent_id
WHERE a.agent_id <> 'TRDEC-WITNESS'
ORDER BY a.cluster_id, a.agent_id;

-- Grant read to authenticated role only
GRANT SELECT ON public.sfx_v_trdec_status TO authenticated;
REVOKE SELECT ON public.sfx_v_trdec_status FROM anon;
