
-- Organizations
create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text,
  created_at timestamp default now()
);

-- Teams within orgs
create table teams (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references organizations(id),
  name text
);

-- Org membership + RBAC
create table org_memberships (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references organizations(id),
  user_id uuid,
  role text -- owner | admin | member | viewer
);

-- Org-level resource quotas
create table org_limits (
  org_id uuid primary key references organizations(id),
  max_monthly_cost numeric,
  max_rps int,
  max_runs int
);

-- Governance policies (security / cost / execution)
create table policies (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references organizations(id),
  type text, -- security | cost | execution
  config jsonb
);

-- Org-scoped audit log
create table org_audit_logs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references organizations(id),
  actor_id uuid,
  action text,
  payload jsonb,
  created_at timestamp default now()
);

-- External integrations (Slack, Salesforce, etc.)
create table integrations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references organizations(id),
  type text, -- slack | salesforce | webhook | warehouse
  config jsonb,
  enabled boolean default true
);
