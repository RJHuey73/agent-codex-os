
-- ============================================================
-- SFX System Config + Dynamic Canon Version
-- Migration: add_sfx_system_config_and_canon_version_fn
-- Canon ref: SFX-CANON-284 (pending T0 ratification)
-- Applied: 2026-06-01 | Canon v9.41.0
-- Agent Codex OS project — was stale at v9.28.0
-- ============================================================

-- ── 1. System config table ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sfx_system_config (
  config_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  canon_version     text NOT NULL,
  canon_next_id     integer NOT NULL DEFAULT 284,
  last_updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by        text NOT NULL DEFAULT 'T1',
  notes             text,

  CONSTRAINT sfx_system_config_singleton CHECK (config_id IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS sfx_system_config_one_row
  ON public.sfx_system_config ((true));

ALTER TABLE public.sfx_system_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "system_config_read_all"
  ON public.sfx_system_config FOR SELECT
  USING (true);

CREATE POLICY "system_config_write_service_role"
  ON public.sfx_system_config FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- ── 2. Seed — correcting stale v9.28.0 to v9.41.0 ──────────
INSERT INTO public.sfx_system_config
  (canon_version, canon_next_id, updated_by, notes)
VALUES
  ('v9.41.0', 284, 'T1',
   'Seeded 2026-06-01. Corrected from stale v9.28.0. Source: Airtable Session Ledger SFX-SESSION-20260601-A.')
ON CONFLICT DO NOTHING;

-- ── 3. current_canon_version() ───────────────────────────────
CREATE OR REPLACE FUNCTION public.current_canon_version()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT canon_version FROM public.sfx_system_config LIMIT 1;
$$;

-- ── 4. update_canon_version() ────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_canon_version(
  p_version     text,
  p_next_id     integer,
  p_actor       text DEFAULT 'T1',
  p_notes       text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.sfx_system_config
  SET
    canon_version   = p_version,
    canon_next_id   = p_next_id,
    last_updated_at = now(),
    updated_by      = p_actor,
    notes           = COALESCE(p_notes, notes)
  WHERE true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'sfx_system_config row not found — seed the table first.';
  END IF;

  RETURN 'Canon version updated to ' || p_version || ' (next ID: ' || p_next_id || ')';
END;
$$;

-- ── 5. Rewire column defaults → function call ────────────────
ALTER TABLE public.agents
  ALTER COLUMN sfx_canon_version SET DEFAULT public.current_canon_version();

ALTER TABLE public.sfx_agent_registry
  ALTER COLUMN canon_version SET DEFAULT public.current_canon_version();

ALTER TABLE public.sfx_agent_workflows
  ALTER COLUMN canon_version SET DEFAULT public.current_canon_version();

ALTER TABLE public.sfx_canon_drafts
  ALTER COLUMN canon_version SET DEFAULT public.current_canon_version();

ALTER TABLE public.sfx_workflow_execution_log
  ALTER COLUMN canon_version SET DEFAULT public.current_canon_version();

ALTER TABLE public.sfx_workflow_templates
  ALTER COLUMN canon_version SET DEFAULT public.current_canon_version();

-- ── 6. Comments ──────────────────────────────────────────────
COMMENT ON FUNCTION public.current_canon_version() IS
  'Returns the active Canon version from sfx_system_config. '
  'Used as column default across all governance tables. '
  'Update via update_canon_version() each Canon sprint. CANON-284.';

COMMENT ON TABLE public.sfx_system_config IS
  'Singleton system config table. Single source of truth for Canon version and next ID. '
  'Replaces hardcoded v9.28.0 defaults across 6 governance tables. CANON-284.';
