
-- Per-node usage tracking
create table usage_logs (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references runs(id),
  node_id uuid,
  model text,
  tokens_input int,
  tokens_output int,
  cost_usd numeric,
  created_at timestamp default now()
);

-- LLM response cache
create table llm_cache (
  id uuid primary key default gen_random_uuid(),
  hash text unique,
  prompt text,
  response text,
  created_at timestamp default now()
);

-- Prompt versioning
create table prompts (
  id uuid primary key default gen_random_uuid(),
  name text,
  version int,
  content text,
  metadata jsonb default '{}'::jsonb,
  is_active boolean default true,
  created_at timestamp default now()
);

-- Prompt snapshot per run (immutable record)
create table run_prompts (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references runs(id),
  node_id uuid,
  prompt_snapshot text
);

-- Experiments
create table experiments (
  id uuid primary key default gen_random_uuid(),
  name text,
  description text,
  created_at timestamp default now()
);

-- Experiment variants (A/B)
create table experiment_variants (
  id uuid primary key default gen_random_uuid(),
  experiment_id uuid references experiments(id),
  prompt_id uuid references prompts(id),
  weight float default 0.5
);

-- Audit trail
create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  entity text,
  entity_id uuid,
  action text,
  payload jsonb,
  created_at timestamp default now()
);
