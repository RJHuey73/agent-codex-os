create table trdec_provenance_events (
  event_id           uuid primary key default gen_random_uuid(),
  agent_id           text not null references trdec_agents(agent_id),
  cluster_id         text not null references cluster_bindings(cluster_id),
  invocation_id      uuid not null references trdec_invocations(invocation_id),
  trust_state_before text not null check (trust_state_before in ('STRUCTURED','VALIDATED','RATIFIED','SOVEREIGN')),
  trust_state_after  text not null check (trust_state_after  in ('STRUCTURED','VALIDATED','RATIFIED','SOVEREIGN')),
  input_packet_id    uuid not null references trdec_packets(packet_id),
  output_packet_id   uuid references trdec_packets(packet_id),
  state_delta        jsonb not null default '{}',
  replay_signature   text not null,
  event_type         text not null check (event_type in (
                       'NORMAL_INVOCATION',
                       'WITNESS_INVOCATION_ATTEMPT',
                       'HARD_STOP',
                       'TRUST_VIOLATION',
                       'CLUSTER_VIOLATION',
                       'CONSTRAINT_VIOLATION'
                     )),
  created_at         timestamptz not null default now()
);

create index idx_trdec_prov_agent_id   on trdec_provenance_events(agent_id);
create index idx_trdec_prov_cluster_id on trdec_provenance_events(cluster_id);

create or replace function trdec_prevent_provenance_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'trdec_provenance_events is immutable — constitutional ledger cannot be modified';
  return null;
end;
$$;

create trigger trg_trdec_provenance_immutable
before update or delete on trdec_provenance_events
for each row execute function trdec_prevent_provenance_mutation();
