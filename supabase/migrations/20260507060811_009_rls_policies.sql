
-- ============================================================
-- 009_rls_policies
-- Full RLS policy layer — all 37 tables + security hardening
-- T0 authorized · ={∆§/π}™
-- ============================================================

-- ─── SECURITY HARDENING ──────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM anon, authenticated;
ALTER FUNCTION public.log_table_updates() SET search_path = public, pg_catalog;

-- ─── AGENTS ──────────────────────────────────────────────────
CREATE POLICY "agents_select" ON public.agents
  FOR SELECT TO authenticated
  USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = agents.org_id AND om.user_id = auth.uid()
    )
  );

CREATE POLICY "agents_insert" ON public.agents
  FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid());

CREATE POLICY "agents_update" ON public.agents
  FOR UPDATE TO authenticated
  USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = agents.org_id AND om.user_id = auth.uid()
      AND om.role IN ('admin', 'owner')
    )
  );

CREATE POLICY "agents_delete" ON public.agents
  FOR DELETE TO authenticated
  USING (owner_id = auth.uid());

-- ─── NODES ───────────────────────────────────────────────────
CREATE POLICY "nodes_select" ON public.nodes
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      LEFT JOIN public.org_memberships om ON om.org_id = a.org_id
      WHERE a.id = nodes.agent_id
      AND (a.owner_id = auth.uid() OR om.user_id = auth.uid())
    )
  );

CREATE POLICY "nodes_insert" ON public.nodes
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = nodes.agent_id AND a.owner_id = auth.uid()
    )
  );

CREATE POLICY "nodes_update" ON public.nodes
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = nodes.agent_id AND a.owner_id = auth.uid()
    )
  );

CREATE POLICY "nodes_delete" ON public.nodes
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = nodes.agent_id AND a.owner_id = auth.uid()
    )
  );

-- ─── EDGES ───────────────────────────────────────────────────
CREATE POLICY "edges_select" ON public.edges
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      LEFT JOIN public.org_memberships om ON om.org_id = a.org_id
      WHERE a.id = edges.agent_id
      AND (a.owner_id = auth.uid() OR om.user_id = auth.uid())
    )
  );

CREATE POLICY "edges_insert" ON public.edges
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = edges.agent_id AND a.owner_id = auth.uid()
    )
  );

CREATE POLICY "edges_update" ON public.edges
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = edges.agent_id AND a.owner_id = auth.uid()
    )
  );

CREATE POLICY "edges_delete" ON public.edges
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = edges.agent_id AND a.owner_id = auth.uid()
    )
  );

-- ─── RUNS ────────────────────────────────────────────────────
CREATE POLICY "runs_select" ON public.runs
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = runs.org_id AND om.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = runs.agent_id AND a.owner_id = auth.uid()
    )
  );

CREATE POLICY "runs_insert" ON public.runs
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = runs.agent_id AND a.owner_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = runs.org_id AND om.user_id = auth.uid()
    )
  );

CREATE POLICY "runs_update" ON public.runs
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = runs.agent_id AND a.owner_id = auth.uid()
    )
  );

-- ─── EVENTS ──────────────────────────────────────────────────
CREATE POLICY "events_select" ON public.events
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.runs r
      LEFT JOIN public.org_memberships om ON om.org_id = r.org_id
      LEFT JOIN public.agents a ON a.id = r.agent_id
      WHERE r.id = events.run_id
      AND (om.user_id = auth.uid() OR a.owner_id = auth.uid())
    )
  );

CREATE POLICY "events_insert" ON public.events
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.runs r
      LEFT JOIN public.agents a ON a.id = r.agent_id
      WHERE r.id = events.run_id AND a.owner_id = auth.uid()
    )
  );

-- ─── TOOLS ───────────────────────────────────────────────────
-- Internal registry — authenticated read only
CREATE POLICY "tools_select" ON public.tools
  FOR SELECT TO authenticated
  USING (true);

-- ─── AGENT ASSIGNMENTS ───────────────────────────────────────
CREATE POLICY "agent_assignments_select" ON public.agent_assignments
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.runs r
      LEFT JOIN public.org_memberships om ON om.org_id = r.org_id
      LEFT JOIN public.agents a ON a.id = r.agent_id
      WHERE r.id = agent_assignments.run_id
      AND (om.user_id = auth.uid() OR a.owner_id = auth.uid())
    )
  );

-- ─── SCHEDULES ───────────────────────────────────────────────
CREATE POLICY "schedules_select" ON public.schedules
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      LEFT JOIN public.org_memberships om ON om.org_id = a.org_id
      WHERE a.id = schedules.agent_id
      AND (a.owner_id = auth.uid() OR om.user_id = auth.uid())
    )
  );

CREATE POLICY "schedules_insert" ON public.schedules
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = schedules.agent_id AND a.owner_id = auth.uid()
    )
  );

CREATE POLICY "schedules_update" ON public.schedules
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = schedules.agent_id AND a.owner_id = auth.uid()
    )
  );

CREATE POLICY "schedules_delete" ON public.schedules
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = schedules.agent_id AND a.owner_id = auth.uid()
    )
  );

-- ─── TRIGGERS ────────────────────────────────────────────────
CREATE POLICY "triggers_select" ON public.triggers
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      LEFT JOIN public.org_memberships om ON om.org_id = a.org_id
      WHERE a.id = triggers.agent_id
      AND (a.owner_id = auth.uid() OR om.user_id = auth.uid())
    )
  );

CREATE POLICY "triggers_insert" ON public.triggers
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = triggers.agent_id AND a.owner_id = auth.uid()
    )
  );

CREATE POLICY "triggers_update" ON public.triggers
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = triggers.agent_id AND a.owner_id = auth.uid()
    )
  );

CREATE POLICY "triggers_delete" ON public.triggers
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = triggers.agent_id AND a.owner_id = auth.uid()
    )
  );

-- ─── USAGE LOGS ──────────────────────────────────────────────
CREATE POLICY "usage_logs_select" ON public.usage_logs
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.runs r
      LEFT JOIN public.org_memberships om ON om.org_id = r.org_id
      LEFT JOIN public.agents a ON a.id = r.agent_id
      WHERE r.id = usage_logs.run_id
      AND (om.user_id = auth.uid() OR a.owner_id = auth.uid())
    )
  );

-- ─── PROMPTS ─────────────────────────────────────────────────
CREATE POLICY "prompts_select" ON public.prompts
  FOR SELECT TO authenticated
  USING (true);

-- ─── RUN PROMPTS ─────────────────────────────────────────────
CREATE POLICY "run_prompts_select" ON public.run_prompts
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.runs r
      LEFT JOIN public.agents a ON a.id = r.agent_id
      WHERE r.id = run_prompts.run_id AND a.owner_id = auth.uid()
    )
  );

-- ─── EXPERIMENTS ─────────────────────────────────────────────
CREATE POLICY "experiments_select" ON public.experiments
  FOR SELECT TO authenticated
  USING (true);

-- ─── EXPERIMENT VARIANTS ─────────────────────────────────────
CREATE POLICY "experiment_variants_select" ON public.experiment_variants
  FOR SELECT TO authenticated
  USING (true);

-- ─── API KEYS ────────────────────────────────────────────────
CREATE POLICY "api_keys_select" ON public.api_keys
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid());

CREATE POLICY "api_keys_insert" ON public.api_keys
  FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid());

CREATE POLICY "api_keys_delete" ON public.api_keys
  FOR DELETE TO authenticated
  USING (owner_id = auth.uid());

-- ─── USAGE ───────────────────────────────────────────────────
CREATE POLICY "usage_select" ON public.usage
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.api_keys ak
      WHERE ak.key = usage.api_key AND ak.owner_id = auth.uid()
    )
  );

-- ─── TEMPLATES ───────────────────────────────────────────────
CREATE POLICY "templates_select_anon" ON public.templates
  FOR SELECT TO anon
  USING (is_public = true);

CREATE POLICY "templates_select_auth" ON public.templates
  FOR SELECT TO authenticated
  USING (
    is_public = true
    OR owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = templates.org_id AND om.user_id = auth.uid()
    )
  );

CREATE POLICY "templates_insert" ON public.templates
  FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid());

CREATE POLICY "templates_update" ON public.templates
  FOR UPDATE TO authenticated
  USING (owner_id = auth.uid());

CREATE POLICY "templates_delete" ON public.templates
  FOR DELETE TO authenticated
  USING (owner_id = auth.uid());

-- ─── TEMPLATE VERSIONS ───────────────────────────────────────
CREATE POLICY "template_versions_select_anon" ON public.template_versions
  FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.templates t
      WHERE t.id = template_versions.template_id AND t.is_public = true
    )
  );

CREATE POLICY "template_versions_select_auth" ON public.template_versions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.templates t
      WHERE t.id = template_versions.template_id
      AND (t.is_public = true OR t.owner_id = auth.uid())
    )
  );

CREATE POLICY "template_versions_insert" ON public.template_versions
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.templates t
      WHERE t.id = template_versions.template_id AND t.owner_id = auth.uid()
    )
  );

-- ─── PURCHASES ───────────────────────────────────────────────
CREATE POLICY "purchases_select" ON public.purchases
  FOR SELECT TO authenticated
  USING (buyer_id = auth.uid());

CREATE POLICY "purchases_insert" ON public.purchases
  FOR INSERT TO authenticated
  WITH CHECK (buyer_id = auth.uid());

-- ─── ENTITLEMENTS ────────────────────────────────────────────
CREATE POLICY "entitlements_select" ON public.entitlements
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ─── SANDBOX AUDIT ───────────────────────────────────────────
CREATE POLICY "sandbox_audit_select" ON public.sandbox_audit
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.runs r
      LEFT JOIN public.agents a ON a.id = r.agent_id
      WHERE r.id = sandbox_audit.run_id AND a.owner_id = auth.uid()
    )
  );

-- ─── TEMPLATE REPUTATION ─────────────────────────────────────
CREATE POLICY "template_reputation_select_anon" ON public.template_reputation
  FOR SELECT TO anon USING (true);

CREATE POLICY "template_reputation_select_auth" ON public.template_reputation
  FOR SELECT TO authenticated USING (true);

-- ─── CREATOR REPUTATION ──────────────────────────────────────
CREATE POLICY "creator_reputation_select_anon" ON public.creator_reputation
  FOR SELECT TO anon USING (true);

CREATE POLICY "creator_reputation_select_auth" ON public.creator_reputation
  FOR SELECT TO authenticated USING (true);

-- ─── ORGANIZATIONS ───────────────────────────────────────────
CREATE POLICY "organizations_select" ON public.organizations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = organizations.id AND om.user_id = auth.uid()
    )
  );

CREATE POLICY "organizations_insert" ON public.organizations
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- ─── TEAMS ───────────────────────────────────────────────────
CREATE POLICY "teams_select" ON public.teams
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = teams.org_id AND om.user_id = auth.uid()
    )
  );

CREATE POLICY "teams_insert" ON public.teams
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = teams.org_id AND om.user_id = auth.uid()
      AND om.role IN ('admin', 'owner')
    )
  );

-- ─── ORG MEMBERSHIPS ─────────────────────────────────────────
CREATE POLICY "org_memberships_select" ON public.org_memberships
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.org_memberships om2
      WHERE om2.org_id = org_memberships.org_id
      AND om2.user_id = auth.uid()
      AND om2.role IN ('admin', 'owner')
    )
  );

CREATE POLICY "org_memberships_insert" ON public.org_memberships
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = org_memberships.org_id
      AND om.user_id = auth.uid()
      AND om.role IN ('admin', 'owner')
    )
  );

CREATE POLICY "org_memberships_delete" ON public.org_memberships
  FOR DELETE TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = org_memberships.org_id
      AND om.user_id = auth.uid()
      AND om.role IN ('admin', 'owner')
    )
  );

-- ─── ORG LIMITS ──────────────────────────────────────────────
CREATE POLICY "org_limits_select" ON public.org_limits
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = org_limits.org_id AND om.user_id = auth.uid()
    )
  );

-- ─── POLICIES ────────────────────────────────────────────────
CREATE POLICY "policies_select" ON public.policies
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = policies.org_id AND om.user_id = auth.uid()
      AND om.role IN ('admin', 'owner')
    )
  );

CREATE POLICY "policies_insert" ON public.policies
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = policies.org_id AND om.user_id = auth.uid()
      AND om.role IN ('admin', 'owner')
    )
  );

CREATE POLICY "policies_update" ON public.policies
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = policies.org_id AND om.user_id = auth.uid()
      AND om.role IN ('admin', 'owner')
    )
  );

-- ─── ORG AUDIT LOGS ──────────────────────────────────────────
CREATE POLICY "org_audit_logs_select" ON public.org_audit_logs
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = org_audit_logs.org_id AND om.user_id = auth.uid()
      AND om.role IN ('admin', 'owner')
    )
  );

-- ─── INTEGRATIONS ────────────────────────────────────────────
CREATE POLICY "integrations_select" ON public.integrations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = integrations.org_id AND om.user_id = auth.uid()
    )
  );

CREATE POLICY "integrations_insert" ON public.integrations
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = integrations.org_id AND om.user_id = auth.uid()
      AND om.role IN ('admin', 'owner')
    )
  );

CREATE POLICY "integrations_update" ON public.integrations
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = integrations.org_id AND om.user_id = auth.uid()
      AND om.role IN ('admin', 'owner')
    )
  );

-- ─── JOB QUEUE ───────────────────────────────────────────────
CREATE POLICY "job_queue_select" ON public.job_queue
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = job_queue.org_id AND om.user_id = auth.uid()
    )
  );

-- ─── FAILED JOBS ─────────────────────────────────────────────
CREATE POLICY "failed_jobs_select" ON public.failed_jobs
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.job_queue jq
      JOIN public.org_memberships om ON om.org_id = jq.org_id
      WHERE jq.id = failed_jobs.job_id AND om.user_id = auth.uid()
      AND om.role IN ('admin', 'owner')
    )
  );

-- ─── TELEMETRY EVENTS ────────────────────────────────────────
CREATE POLICY "telemetry_events_select" ON public.telemetry_events
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_memberships om
      WHERE om.org_id = telemetry_events.org_id AND om.user_id = auth.uid()
    )
  );
