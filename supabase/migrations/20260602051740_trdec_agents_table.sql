create table trdec_agents (
  agent_id            text primary key,
  canonical_name      text not null,
  class               text not null check (class in ('CORE','HARMONIC','WITNESS')),
  cluster_id          text not null references cluster_bindings(cluster_id),
  trust_state_floor   text not null check (trust_state_floor in ('STRUCTURED','VALIDATED','RATIFIED','SOVEREIGN')),
  invocable           boolean not null,
  authority           jsonb not null default '[]',
  constraints         jsonb not null default '[]',
  invocation_surface  jsonb not null default '[]',
  provenance_req      jsonb not null default '[]',
  replay_req          text not null check (replay_req in ('deterministic','none')),
  t2_advisory_role    text,
  ratified_by         text not null default 'T0',
  ratified_in         text not null,
  created_at          timestamptz not null default now()
);

create or replace function trdec_prevent_agents_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'trdec_agents is immutable — retire and re-register to change identity';
  return null;
end;
$$;

create trigger trg_trdec_agents_immutable
before update or delete on trdec_agents
for each row execute function trdec_prevent_agents_mutation();
