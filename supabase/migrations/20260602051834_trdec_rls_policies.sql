alter table trdec_agents                 enable row level security;
alter table trdec_packets                enable row level security;
alter table trdec_agent_state            enable row level security;
alter table trdec_agent_state_snapshots  enable row level security;
alter table trdec_invocations            enable row level security;
alter table trdec_truststate_transitions enable row level security;
alter table trdec_provenance_events      enable row level security;

create policy "svc_trdec_agents"       on trdec_agents                 for all    to service_role using (true) with check (true);
create policy "read_trdec_agents"      on trdec_agents                 for select to authenticated using (true);

create policy "svc_trdec_packets"      on trdec_packets                for all    to service_role using (true) with check (true);

create policy "svc_trdec_agent_state"  on trdec_agent_state            for all    to service_role using (true) with check (true);

create policy "svc_trdec_snapshots"    on trdec_agent_state_snapshots  for all    to service_role using (true) with check (true);

create policy "svc_trdec_invocations"  on trdec_invocations            for all    to service_role using (true) with check (true);
create policy "read_trdec_invocations" on trdec_invocations            for select to authenticated using (true);

create policy "svc_trdec_truststate"   on trdec_truststate_transitions for all    to service_role using (true) with check (true);
create policy "read_trdec_truststate"  on trdec_truststate_transitions for select to authenticated using (true);

create policy "svc_trdec_provenance"   on trdec_provenance_events      for all    to service_role using (true) with check (true);
create policy "read_trdec_provenance"  on trdec_provenance_events      for select to authenticated using (true);
