
-- Sandbox execution audit
create table sandbox_audit (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references runs(id),
  template_id uuid references templates(id),
  violations jsonb,
  permissions_used jsonb,
  cost numeric,
  created_at timestamp default now()
);

-- Template reputation scores
create table template_reputation (
  id uuid primary key default gen_random_uuid(),
  template_id uuid unique references templates(id),
  score numeric default 0,
  installs int default 0,
  avg_run_score numeric default 0,
  failure_rate numeric default 0,
  avg_cost numeric default 0,
  last_updated timestamp default now()
);

-- Creator reputation scores
create table creator_reputation (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique,
  score numeric default 0,
  total_runs int default 0,
  avg_quality numeric default 0,
  avg_cost_efficiency numeric default 0,
  last_updated timestamp default now()
);
