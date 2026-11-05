
-- Fix ccx_governance_events.event_type CHECK — add CANDIDATE_SURFACED
-- CRIT-05 from T1 triage — live bug in fn-ccx-ingest

ALTER TABLE ccx_governance_events
  DROP CONSTRAINT ccx_governance_events_event_type_check;

ALTER TABLE ccx_governance_events
  ADD CONSTRAINT ccx_governance_events_event_type_check
  CHECK (event_type IN (
    'high_conf_retrieval',
    'arbitration',
    'synthesis',
    'override',
    'invalidation',
    'drift_correction',
    'routing_correction',
    'cold_mark',
    'cluster_reinforcement',
    'conflict_resolution',
    'CANDIDATE_SURFACED'
  ));
