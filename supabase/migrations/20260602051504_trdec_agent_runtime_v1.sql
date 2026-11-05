-- 1) CLUSTER BINDINGS
create table cluster_bindings (
  cluster_id  text primary key,
  name        text not null,
  scope       text not null,
  created_at  timestamptz not null default now()
);

insert into cluster_bindings (cluster_id, name, scope) values
  ('TRDEC-C1',      'Tridecagon — Governance',          'Authority enforcement, constitutional compliance, mutation review'),
  ('TRDEC-C2',      'Tridecagon — Protection',          'Threat detection, anomaly flagging, adversarial simulation'),
  ('TRDEC-C3',      'Tridecagon — Evaluation',          'Hard-constraint veto, signature verification, audit'),
  ('TRDEC-C4',      'Tridecagon — Memory',              'State lineage, EventStore, deterministic replay'),
  ('TRDEC-C5',      'Tridecagon — Integration',         'Synthesis, dispatch, packet assembly'),
  ('TRDEC-WITNESS', 'Tridecagon — Witness (Sovereign)', 'Constitutional field layer. Non-operational. Sovereign anchor only.');
