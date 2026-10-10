
-- Distributed job queue
create table job_queue (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references runs(id),
  org_id uuid references organizations(id),
  status text default 'queued', -- queued | running | completed | failed
  payload jsonb,
  priority int default 5,
  retries int default 0,
  created_at timestamp default now(),
  locked_at timestamp
);

-- Dead letter queue
create table failed_jobs (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references job_queue(id),
  error text,
  created_at timestamp default now()
);

-- Distributed trace telemetry
create table telemetry_events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid,
  run_id uuid references runs(id),
  trace_id uuid,
  span_id uuid,
  event_type text,
  payload jsonb,
  severity text, -- info | warning | error | fatal
  created_at timestamp default now()
);

-- Performance indexes
create index idx_runs_agent_id        on runs(agent_id);
create index idx_runs_status          on runs(status);
create index idx_runs_org_id          on runs(org_id);
create index idx_events_run_id        on events(run_id);
create index idx_events_created_at    on events(created_at);
create index idx_job_queue_status     on job_queue(status, priority desc, created_at);
create index idx_usage_logs_run_id    on usage_logs(run_id);
create index idx_telemetry_run_id     on telemetry_events(run_id);
create index idx_nodes_agent_id       on nodes(agent_id);
create index idx_edges_agent_id       on edges(agent_id);
create index idx_audit_entity         on audit_logs(entity, entity_id);

-- Audit trigger function (auto-logs all table mutations)
create or replace function log_table_updates()
returns trigger as $$
begin
  insert into audit_logs(entity, entity_id, action, payload)
  values (TG_TABLE_NAME, NEW.id, TG_OP, row_to_json(NEW)::jsonb);
  return NEW;
end;
$$ language plpgsql;

-- Attach audit trigger to core tables
create trigger audit_agents
  after insert or update on agents
  for each row execute function log_table_updates();

create trigger audit_runs
  after insert or update on runs
  for each row execute function log_table_updates();

create trigger audit_templates
  after insert or update on templates
  for each row execute function log_table_updates();

create trigger audit_prompts
  after insert or update on prompts
  for each row execute function log_table_updates();

-- RLS: enable on all core tables (no policies yet — dev mode)
alter table agents              enable row level security;
alter table nodes               enable row level security;
alter table edges               enable row level security;
alter table runs                enable row level security;
alter table events              enable row level security;
alter table memory_embeddings   enable row level security;
alter table templates           enable row level security;
alter table usage_logs          enable row level security;
alter table api_keys            enable row level security;
