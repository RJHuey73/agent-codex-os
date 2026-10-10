create table trdec_invocations (
  invocation_id      uuid primary key default gen_random_uuid(),
  agent_id           text not null references trdec_agents(agent_id),
  cluster_id         text not null references cluster_bindings(cluster_id),
  input_packet_id    uuid not null references trdec_packets(packet_id),
  output_packet_id   uuid references trdec_packets(packet_id),
  trust_state_before text not null check (trust_state_before in ('STRUCTURED','VALIDATED','RATIFIED','SOVEREIGN')),
  trust_state_after  text not null check (trust_state_after  in ('STRUCTURED','VALIDATED','RATIFIED','SOVEREIGN')),
  replay_signature   text not null,
  result_status      text not null check (result_status in ('SUCCESS','HARD_STOP','ERROR')),
  hard_stop_reason   text,
  created_at         timestamptz not null default now()
);

create index idx_trdec_invocations_agent_id   on trdec_invocations(agent_id);
create index idx_trdec_invocations_cluster_id on trdec_invocations(cluster_id);
