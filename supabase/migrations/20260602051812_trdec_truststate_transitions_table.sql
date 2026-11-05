create table trdec_truststate_transitions (
  id             bigserial primary key,
  agent_id       text not null references trdec_agents(agent_id),
  cluster_id     text not null references cluster_bindings(cluster_id),
  invocation_id  uuid not null references trdec_invocations(invocation_id),
  from_state     text not null check (from_state in ('STRUCTURED','VALIDATED','RATIFIED','SOVEREIGN')),
  to_state       text not null check (to_state   in ('STRUCTURED','VALIDATED','RATIFIED')),
  reason         text not null,
  created_at     timestamptz not null default now()
);

create index idx_trdec_truststate_agent_id on trdec_truststate_transitions(agent_id);
