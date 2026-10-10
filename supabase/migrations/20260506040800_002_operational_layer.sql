
-- Tool registry
create table tools (
  id uuid primary key default gen_random_uuid(),
  name text unique,
  type text, -- http | function | internal
  config jsonb
);

-- Multi-agent task assignments
create table agent_assignments (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references runs(id),
  agent_id uuid references agents(id),
  task jsonb,
  result jsonb,
  status text
);

-- Inter-agent message bus
create table agent_messages (
  id uuid primary key default gen_random_uuid(),
  from_agent text,
  to_agent text,
  type text, -- task | result | request | critique
  payload jsonb,
  trace_id uuid,
  created_at timestamp default now()
);

-- Scheduled execution
create table schedules (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid references agents(id),
  cron text,
  enabled boolean default true,
  last_run timestamp,
  next_run timestamp,
  config jsonb default '{}'::jsonb
);

-- Event-based triggers
create table triggers (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid references agents(id),
  type text, -- webhook | db | external
  config jsonb,
  enabled boolean default true
);
