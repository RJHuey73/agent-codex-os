
UPDATE sfx_system_config
SET
  canon_version   = 'v9.44.0',
  canon_next_id   = 319,
  last_updated_at = now(),
  updated_by      = 'T1',
  notes           = 'SFX-SESSION-20260603-A close. All 4 forward gates cleared: '
                 || '(1) Test suite 47/47 green — PROD gate cleared. '
                 || '(2) CANON-307-318 ratified: 14 agents registered, 9 clusters live. '
                 || '(3) run-agent Phase A deployed (shadowfox-os). '
                 || '(4) fn-canon-sync deployed + AUTO-001A wired (AUTO-002A). '
                 || 'Next: CANON-318 per-agent T0 activation reviews, P2 Phase B (verify_jwt+RLS).'
WHERE config_id IS NOT NULL;
