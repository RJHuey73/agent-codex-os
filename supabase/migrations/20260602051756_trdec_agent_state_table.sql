create table trdec_agent_state (
  agent_id         text primary key references trdec_agents(agent_id),
  current_state    jsonb not null default '{}',
  last_snapshot_id uuid,
  version          bigint not null default 0,
  updated_at       timestamptz not null default now()
);

create or replace function trdec_enforce_agent_state_version()
returns trigger language plpgsql as $$
begin
  if new.version <> old.version + 1 then
    raise exception 'trdec_agent_state version conflict: agent_id=%, expected %, got %',
      old.agent_id, old.version + 1, new.version;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_trdec_agent_state_version
before update on trdec_agent_state
for each row execute function trdec_enforce_agent_state_version();

create table trdec_agent_state_snapshots (
  snapshot_id      uuid primary key default gen_random_uuid(),
  agent_id         text not null references trdec_agents(agent_id),
  state            jsonb not null,
  replay_signature text not null,
  created_at       timestamptz not null default now()
);

create index idx_trdec_snapshots_agent_id on trdec_agent_state_snapshots(agent_id);
