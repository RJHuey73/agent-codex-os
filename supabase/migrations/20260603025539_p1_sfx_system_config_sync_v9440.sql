
-- P1: sfx_system_config sync — agent-codex-os
-- Canon: v9.44.0 | next_id: 307

UPDATE sfx_system_config
SET
  canon_version   = 'v9.44.0',
  canon_next_id   = 307,
  last_updated_at = now(),
  updated_by      = 'T1',
  notes           = 'Synced to live Canon state post SFX-SESSION-20260602-B. '
                 || 'Tridecagon CANON-304/305/306 registered. '
                 || 'Phase B migration applied (sfx_* governance columns, ccx_governance_events fix). '
                 || 'Next: CANON-307 (Harmonic agent registration batch).'
WHERE config_id IS NOT NULL;
