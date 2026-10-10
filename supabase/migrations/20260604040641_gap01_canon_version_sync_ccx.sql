
-- GAP-01 Remediation: agent-codex-os
-- Update live configuration/registry rows to current Canon version v9.44.0
-- Audit trail rows (sfx_workflow_execution_log, ccx_governance_events,
-- ccx_ingestion_queue, sfx_canon_drafts) intentionally excluded — point-in-time records

UPDATE public.sfx_agent_registry
SET canon_version = 'v9.44.0'
WHERE canon_version != 'v9.44.0';

UPDATE public.sfx_workflow_templates
SET canon_version = 'v9.44.0'
WHERE canon_version != 'v9.44.0';

UPDATE public.sfx_agent_workflows
SET canon_version = 'v9.44.0'
WHERE canon_version != 'v9.44.0';

UPDATE public.agents
SET sfx_canon_version = 'v9.44.0'
WHERE sfx_canon_version != 'v9.44.0';

-- Strip stale documentation comments

COMMENT ON COLUMN public.sfx_agent_registry.canon_version
  IS 'Canon version at agent registration. Auto-populated via current_canon_version() — no manual sprint update required.';

COMMENT ON COLUMN public.sfx_agent_workflows.canon_version
  IS 'Canon version at workflow registration. Auto-populated via current_canon_version() — no manual sprint update required.';

COMMENT ON COLUMN public.sfx_workflow_templates.canon_version
  IS 'Canon version at template creation. Auto-populated via current_canon_version() — no manual sprint update required.';

COMMENT ON COLUMN public.sfx_workflow_execution_log.canon_version
  IS 'Canon version active at execution time. Immutable audit record — reflects Canon version when event was logged. Auto-populated via current_canon_version().';

COMMENT ON COLUMN public.sfx_canon_drafts.canon_version
  IS 'Canon version under which draft was proposed. Immutable lineage record. Auto-populated via current_canon_version().';

COMMENT ON COLUMN public.ccx_ingestion_queue.canon_version
  IS 'Canon version at ingestion time. Immutable intake record. Auto-populated via current_canon_version().';

COMMENT ON COLUMN public.ccx_knowledge_index.canon_version
  IS 'Canon version at indexing time. Immutable knowledge record. Auto-populated via current_canon_version().';

COMMENT ON COLUMN public.ccx_canon_candidates.canon_version
  IS 'Canon version when candidate was surfaced. Immutable synthesis record. Auto-populated via current_canon_version().';

COMMENT ON COLUMN public.ccx_governance_events.canon_version
  IS 'Canon version at governance event time. Immutable audit record. Auto-populated via current_canon_version().';

COMMENT ON COLUMN public.memory_embeddings.canon_version
  IS 'Canon version at embedding creation. Immutable memory record. Auto-populated via current_canon_version().';

COMMENT ON COLUMN public.agents.sfx_canon_version
  IS 'Canon version at agent record creation. Auto-populated via current_canon_version() — no manual sprint update required.';
