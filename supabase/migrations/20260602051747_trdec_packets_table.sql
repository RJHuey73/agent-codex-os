create table trdec_packets (
  packet_id   uuid primary key default gen_random_uuid(),
  direction   text not null check (direction in ('IN','OUT')),
  agent_id    text references trdec_agents(agent_id),
  cluster_id  text references cluster_bindings(cluster_id),
  trust_state text not null check (trust_state in ('STRUCTURED','VALIDATED','RATIFIED','SOVEREIGN')),
  payload     jsonb not null,
  action      text,
  replay_id   text,
  signature   text,
  created_at  timestamptz not null default now()
);

create index idx_trdec_packets_agent_id   on trdec_packets(agent_id);
create index idx_trdec_packets_cluster_id on trdec_packets(cluster_id);
