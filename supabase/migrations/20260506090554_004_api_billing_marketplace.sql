
-- API key management
create table api_keys (
  id uuid primary key default gen_random_uuid(),
  key text unique,
  owner_id uuid,
  tier text default 'free', -- free | pro | enterprise
  created_at timestamp default now()
);

-- API usage per key
create table usage (
  id uuid primary key default gen_random_uuid(),
  api_key text,
  run_id uuid references runs(id),
  tokens int,
  cost_usd numeric,
  created_at timestamp default now()
);

-- Marketplace templates
create table templates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid,
  org_id uuid,
  name text,
  description text,
  category text,
  price_cents int default 0,
  is_public boolean default false,
  created_at timestamp default now()
);

-- Template versions (immutable snapshots)
create table template_versions (
  id uuid primary key default gen_random_uuid(),
  template_id uuid references templates(id),
  version int,
  nodes jsonb,
  edges jsonb,
  prompt_bundle jsonb,
  changelog text,
  created_at timestamp default now()
);

-- Purchase records
create table purchases (
  id uuid primary key default gen_random_uuid(),
  template_id uuid references templates(id),
  buyer_id uuid,
  version int,
  price_cents int,
  created_at timestamp default now()
);

-- Access entitlements
create table entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  template_id uuid references templates(id),
  active boolean default true,
  expires_at timestamp
);
