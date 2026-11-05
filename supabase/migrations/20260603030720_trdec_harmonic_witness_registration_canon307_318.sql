
-- ══════════════════════════════════════════════════════════════════════════
-- TRDECAGON HARMONIC + WITNESS AGENT REGISTRATION
-- CANON-307–318 | Canon v9.44.0 | Session SFX-SESSION-20260603-A
-- T0 ratified | T1 authored
-- ══════════════════════════════════════════════════════════════════════════

-- ─── STEP 1: Insert Harmonic clusters (TRDEC-C6 through TRDEC-C13) ──────────

INSERT INTO cluster_bindings (cluster_id, name, scope) VALUES
  ('TRDEC-C6',  'Harmonic-Alpha',   'HARMONIC'),
  ('TRDEC-C7',  'Harmonic-Beta',    'HARMONIC'),
  ('TRDEC-C8',  'Harmonic-Gamma',   'HARMONIC'),
  ('TRDEC-C9',  'Harmonic-Delta',   'HARMONIC'),
  ('TRDEC-C10', 'Harmonic-Epsilon', 'HARMONIC'),
  ('TRDEC-C11', 'Harmonic-Zeta',    'HARMONIC'),
  ('TRDEC-C12', 'Harmonic-Eta',     'HARMONIC'),
  ('TRDEC-C13', 'Harmonic-Theta',   'HARMONIC')
ON CONFLICT (cluster_id) DO NOTHING;

-- ─── STEP 2: Insert Witness cluster ─────────────────────────────────────────

INSERT INTO cluster_bindings (cluster_id, name, scope) VALUES
  ('TRDEC-WITNESS', 'Witness-Sovereign', 'WITNESS')
ON CONFLICT (cluster_id) DO NOTHING;

-- ─── STEP 3: Insert Harmonic agents (TRDEC-A06 through TRDEC-A13) ───────────
-- Class: HARMONIC | invocable: false (CANON-318 lifts this per-agent)
-- trust_state_floor: RATIFIED (minimum — elevated per agent at activation)
-- Authority JSONB mirrors Core pattern but restricted until CANON activation

INSERT INTO trdec_agents (
  agent_id, canonical_name, class, cluster_id,
  trust_state_floor, invocable, authority, constraints,
  invocation_surface, provenance_req, replay_req,
  ratified_by, ratified_in
) VALUES

-- TRDEC-A06 / Harmonic-Alpha — Reserved: Signal Intelligence
('TRDEC-A06', 'Harmonic-Alpha', 'HARMONIC', 'TRDEC-C6', 'RATIFIED', false,
  '{"can_read": true, "can_write_data": false, "can_block_execution": false, "can_route": false, "can_dispatch": false, "can_flag": false, "can_quarantine": false, "can_score": false, "can_write_memory": false, "canon_write_authority": false, "notes": "Reserved: Signal Intelligence. Activation gated on CANON-307 ratification."}',
  '{"activation_gate": "CANON-307", "requires_t1_authorization": true, "invocable_after": "CANON-318"}',
  '{"surfaces": [], "note": "No surfaces until CANON-318 activation"}',
  '{"requires_provenance_binding": true, "requires_canon_id": true}',
  'deterministic', 'T0', 'SFX-CANON-307'),

-- TRDEC-A07 / Harmonic-Beta — Reserved: Pattern Recognition
('TRDEC-A07', 'Harmonic-Beta', 'HARMONIC', 'TRDEC-C7', 'RATIFIED', false,
  '{"can_read": true, "can_write_data": false, "can_block_execution": false, "can_route": false, "can_dispatch": false, "can_flag": false, "can_quarantine": false, "can_score": true, "can_write_memory": false, "canon_write_authority": false, "notes": "Reserved: Pattern Recognition."}',
  '{"activation_gate": "CANON-308", "requires_t1_authorization": true, "invocable_after": "CANON-318"}',
  '{"surfaces": [], "note": "No surfaces until CANON-318 activation"}',
  '{"requires_provenance_binding": true, "requires_canon_id": true}',
  'deterministic', 'T0', 'SFX-CANON-308'),

-- TRDEC-A08 / Harmonic-Gamma — Reserved: Synthesis Engine
('TRDEC-A08', 'Harmonic-Gamma', 'HARMONIC', 'TRDEC-C8', 'RATIFIED', false,
  '{"can_read": true, "can_write_data": false, "can_block_execution": false, "can_route": false, "can_dispatch": true, "can_flag": false, "can_quarantine": false, "can_score": false, "can_write_memory": false, "canon_write_authority": false, "notes": "Reserved: Synthesis Engine. Dispatch authorized post-activation."}',
  '{"activation_gate": "CANON-309", "requires_t1_authorization": true, "invocable_after": "CANON-318"}',
  '{"surfaces": [], "note": "No surfaces until CANON-318 activation"}',
  '{"requires_provenance_binding": true, "requires_canon_id": true}',
  'deterministic', 'T0', 'SFX-CANON-309'),

-- TRDEC-A09 / Harmonic-Delta — Reserved: Anomaly Correlation
('TRDEC-A09', 'Harmonic-Delta', 'HARMONIC', 'TRDEC-C9', 'RATIFIED', false,
  '{"can_read": true, "can_write_data": false, "can_block_execution": false, "can_route": false, "can_dispatch": false, "can_flag": true, "can_quarantine": false, "can_score": true, "can_write_memory": false, "canon_write_authority": false, "notes": "Reserved: Anomaly Correlation."}',
  '{"activation_gate": "CANON-310", "requires_t1_authorization": true, "invocable_after": "CANON-318"}',
  '{"surfaces": [], "note": "No surfaces until CANON-318 activation"}',
  '{"requires_provenance_binding": true, "requires_canon_id": true}',
  'deterministic', 'T0', 'SFX-CANON-310'),

-- TRDEC-A10 / Harmonic-Epsilon — Reserved: Trust Chain Verifier
('TRDEC-A10', 'Harmonic-Epsilon', 'HARMONIC', 'TRDEC-C10', 'RATIFIED', false,
  '{"can_read": true, "can_write_data": false, "can_block_execution": true, "can_route": false, "can_dispatch": false, "can_flag": true, "can_quarantine": false, "can_score": false, "can_write_memory": false, "canon_write_authority": false, "notes": "Reserved: Trust Chain Verifier. Block-authorized post-activation."}',
  '{"activation_gate": "CANON-311", "requires_t1_authorization": true, "invocable_after": "CANON-318"}',
  '{"surfaces": [], "note": "No surfaces until CANON-318 activation"}',
  '{"requires_provenance_binding": true, "requires_canon_id": true}',
  'deterministic', 'T0', 'SFX-CANON-311'),

-- TRDEC-A11 / Harmonic-Zeta — Reserved: Lineage Tracer
('TRDEC-A11', 'Harmonic-Zeta', 'HARMONIC', 'TRDEC-C11', 'RATIFIED', false,
  '{"can_read": true, "can_write_data": false, "can_block_execution": false, "can_route": false, "can_dispatch": false, "can_flag": false, "can_quarantine": false, "can_score": false, "can_write_memory": true, "canon_write_authority": false, "notes": "Reserved: Lineage Tracer. Memory-write authorized to lineage tables only."}',
  '{"activation_gate": "CANON-312", "requires_t1_authorization": true, "invocable_after": "CANON-318"}',
  '{"surfaces": [], "note": "No surfaces until CANON-318 activation"}',
  '{"requires_provenance_binding": true, "requires_canon_id": true}',
  'deterministic', 'T0', 'SFX-CANON-312'),

-- TRDEC-A12 / Harmonic-Eta — Reserved: Regime Enforcer
('TRDEC-A12', 'Harmonic-Eta', 'HARMONIC', 'TRDEC-C12', 'RATIFIED', false,
  '{"can_read": true, "can_write_data": false, "can_block_execution": true, "can_route": true, "can_dispatch": false, "can_flag": true, "can_quarantine": true, "can_score": false, "can_write_memory": false, "canon_write_authority": false, "notes": "Reserved: Regime Enforcer. Full protection authority post-activation."}',
  '{"activation_gate": "CANON-313", "requires_t1_authorization": true, "invocable_after": "CANON-318"}',
  '{"surfaces": [], "note": "No surfaces until CANON-318 activation"}',
  '{"requires_provenance_binding": true, "requires_canon_id": true}',
  'deterministic', 'T0', 'SFX-CANON-313'),

-- TRDEC-A13 / Harmonic-Theta — Reserved: Canon Boundary Guard
('TRDEC-A13', 'Harmonic-Theta', 'HARMONIC', 'TRDEC-C13', 'SOVEREIGN', false,
  '{"can_read": true, "can_write_data": false, "can_block_execution": true, "can_route": true, "can_dispatch": false, "can_flag": true, "can_quarantine": true, "can_score": false, "can_write_memory": false, "canon_write_authority": false, "notes": "Reserved: Canon Boundary Guard. Highest harmonic authority. SOVEREIGN trust floor — T0 direct activation only."}',
  '{"activation_gate": "CANON-314", "requires_t0_authorization": true, "invocable_after": "CANON-318", "elevation": "T0_ONLY"}',
  '{"surfaces": [], "note": "No surfaces until CANON-318 T0 activation"}',
  '{"requires_provenance_binding": true, "requires_canon_id": true, "requires_t0_signature": true}',
  'deterministic', 'T0', 'SFX-CANON-314')

ON CONFLICT (agent_id) DO NOTHING;

-- ─── STEP 4: Insert Witness sovereign agent ──────────────────────────────────
-- WITNESS: class=WITNESS, invocable=false (permanent — Witness is non-invocable)
-- agent_id=null at invocation time (handled in router/edge function)
-- This row is the field-anchor registration, not an invocable agent

INSERT INTO trdec_agents (
  agent_id, canonical_name, class, cluster_id,
  trust_state_floor, invocable, authority, constraints,
  invocation_surface, provenance_req, replay_req,
  ratified_by, ratified_in
) VALUES
('TRDEC-WITNESS', 'The Witness', 'WITNESS', 'TRDEC-WITNESS', 'SOVEREIGN', false,
  '{"can_read": true, "can_write_data": false, "can_block_execution": false, "can_route": false, "can_dispatch": false, "can_flag": false, "can_quarantine": false, "can_score": false, "can_write_memory": false, "canon_write_authority": false, "is_sovereign_anchor": true, "notes": "Non-invocable sovereign field. Audit routing terminus. agent_id=null at invocation time by router law. Witness field agents registered under TRDEC-C6-C13 sub-clusters post CANON-318."}',
  '{"non_invocable": true, "permanent": true, "audit_routing_only": true, "field_agent_activation_gate": "CANON-318", "law": "Witness routing produces no DB invocation record. Packets are acknowledged but not persisted until field agents activate."}',
  '{"surfaces": [], "note": "Non-invocable sovereign terminus. No execution surfaces."}',
  '{"requires_provenance_binding": false, "note": "Witness does not generate provenance events — it is the boundary."}',
  'none', 'T0', 'SFX-CANON-316')
ON CONFLICT (agent_id) DO NOTHING;

-- ─── STEP 5: Update sfx_system_config ────────────────────────────────────────

UPDATE sfx_system_config
SET
  canon_version   = 'v9.44.0',
  canon_next_id   = 319,
  last_updated_at = now(),
  updated_by      = 'T1',
  notes           = 'CANON-307-318 ratified: Harmonic agents TRDEC-A06-A13 + Witness registered. '
                 || '8 Harmonic clusters TRDEC-C6-C13 + TRDEC-WITNESS cluster live. '
                 || 'All harmonic agents invocable=false pending CANON-318 field activation. '
                 || 'Test suite 47/47 green. fn-trdec-invoke PROD gate cleared. '
                 || 'Next: P2 run-agent governance patch + P3 Canon sync automation.'
WHERE config_id IS NOT NULL;
