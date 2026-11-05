
-- Extensions
create extension if not exists vector;
create extension if not exists pg_trgm;

-- Core agents table
create table agents (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  owner_id uuid,
  role text, -- supervisor | worker | critic | synthesizer
  org_id uuid,
  created_at timestamp default now()
);

-- Nodes (execution units)
create table nodes (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid references agents(id) on delete cascade,
  type text not null, -- planner | worker | tool | evaluator
  config jsonb default '{}'::jsonb,
  position jsonb default '{}'::jsonb,
  depends_on uuid[] default '{}',
  prompt_id uuid,
  created_at timestamp default now()
);

-- Edges (flow control)
create table edges (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid references agents(id) on delete cascade,
  from_node uuid,
  to_node uuid,
  condition jsonb default '{}'::jsonb
);

-- Runs (execution instances)
create table runs (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid references agents(id),
  org_id uuid,
  status text default 'pending', -- pending | running | completed | failed
  input jsonb,
  output jsonb,
  error text,
  logs jsonb default '[]'::jsonb,
  score float,
  passed boolean,
  cost_usd numeric default 0,
  tokens_input int default 0,
  tokens_output int default 0,
  experiment_id uuid,
  variant_id uuid,
  user_rating int,
  success boolean,
  execution_quality numeric,
  metadata jsonb default '{}'::jsonb,
  created_at timestamp default now(),
  completed_at timestamp
);

-- Events (real-time execution log)
create table events (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references runs(id) on delete cascade,
  node_id uuid,
  event_type text, -- start | success | error
  payload jsonb,
  created_at timestamp default now()
);

-- Memory / AI layer
create table memory_embeddings (
  id uuid primary key default gen_random_uuid(),
  content text,
  embedding vector(1536),
  metadata jsonb default '{}'::jsonb,
  created_at timestamp default now()
);
