/**
 * fn-canon-sync v7 — Canon Version Sync (PULL from Airtable SoT)
 * ============================================================================
 * Project (deploy target): agent-codex-os (oufyfdhjjvhrseythgrr)
 * Replaces: fn-canon-sync v6 (T0-ratified PULL direction, 2026-06-15)
 *
 * v7 (GO-2b, T0 2026-10-10) — auth hardening only, sync logic unchanged:
 *   - FAIL CLOSED: x-sfx-sync-key is required. v6 skipped the check when the
 *     SFX_SYNC_KEY env var was unset, which left the endpoint open.
 *   - The key lives in Vault (`sfx_sync_key`) and is verified in-DB by
 *     public.fn_sfx_sync_key_matches() (service_role only, hash compare).
 *     The expected key never enters this process.
 *   - 502 responses no longer echo upstream error text (`detail`).
 *
 * DOCTRINE ENCODED: Airtable Canon ID Registry is the single Source of Truth.
 * This function PULLS from it and mirrors to both Supabase substrates.
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-sfx-sync-key",
};

const AIRTABLE_BASE = "appVftexD3KJRcdij";
const AIRTABLE_TABLE = "tbltw4Jy0LHWWz5DL";
const F_CANON_ID = "fldyg24N6evVANwnt";
const F_VERSION = "fldK4CqmEwpmwALPO";
const F_STATUS = "fld1K3deZgtYkxrIU";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json", "Connection": "keep-alive" },
  });
}

function parseSuffix(canonId: string): number | null {
  const m = String(canonId).match(/(\d+)$/);
  return m ? parseInt(m[1], 10) : null;
}

interface RegistryRow { canonId: string; version: string | null; status: string | null; suffix: number; }

async function pullRegistry(pat: string): Promise<RegistryRow[]> {
  const rows: RegistryRow[] = [];
  let offset: string | undefined;
  do {
    const url = new URL(`https://api.airtable.com/v0/${AIRTABLE_BASE}/${AIRTABLE_TABLE}`);
    url.searchParams.set("pageSize", "100");
    url.searchParams.append("fields[]", F_CANON_ID);
    url.searchParams.append("fields[]", F_VERSION);
    url.searchParams.append("fields[]", F_STATUS);
    if (offset) url.searchParams.set("offset", offset);

    const res = await fetch(url.toString(), { headers: { Authorization: `Bearer ${pat}` } });
    if (!res.ok) throw new Error(`Airtable ${res.status}: ${await res.text()}`);
    const data = await res.json();

    for (const rec of data.records ?? []) {
      const f = rec.fields ?? {};
      const canonId = (f[F_CANON_ID] ?? f["Canon ID"]) as string | undefined;
      if (!canonId) continue;
      const suffix = parseSuffix(canonId);
      if (suffix === null) continue;
      rows.push({
        canonId,
        version: (f[F_VERSION] ?? f["Version Ratified"] ?? null) as string | null,
        status: (f[F_STATUS] ?? f["Status"] ?? null) as string | null,
        suffix,
      });
    }
    offset = data.offset;
  } while (offset);

  return rows;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json({ error: "Method Not Allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({ error: "Service unavailable" }, 503);
  const ccx = createClient(supabaseUrl, serviceKey);

  // Auth: fail closed. Missing header, verifier error, or mismatch => reject.
  const got = req.headers.get("x-sfx-sync-key");
  if (!got) return json({ error: "Unauthorized" }, 401);
  const { data: keyOk, error: keyErr } = await ccx.rpc("fn_sfx_sync_key_matches", { p_key: got });
  if (keyErr) {
    console.error(`[fn-canon-sync v7] key verifier unavailable: ${keyErr.message}`);
    return json({ error: "Service unavailable" }, 503);
  }
  if (keyOk !== true) return json({ error: "Unauthorized" }, 401);

  const pat = Deno.env.get("SFX_AIRTABLE_PAT");
  if (!pat) return json({ error: "SFX_AIRTABLE_PAT not set — cannot reach SoT" }, 500);

  let rows: RegistryRow[];
  try {
    rows = await pullRegistry(pat);
  } catch (e) {
    console.error(`[fn-canon-sync v7] Airtable pull FAILED — writing nothing: ${e}`);
    return json({ error: "Airtable SoT read failed" }, 502);
  }
  if (rows.length === 0) return json({ error: "Registry empty — refusing to write" }, 422);

  const nextId = Math.max(...rows.map(r => r.suffix)) + 1;

  const activeRows = rows
    .filter(r => (r.status ?? "").toUpperCase() === "ACTIVE")
    .sort((a, b) => b.suffix - a.suffix);
  if (activeRows.length === 0) return json({ error: "No ACTIVE entry — refusing to write" }, 422);

  const latestActive = activeRows[0];
  const canonVersion = latestActive.version;
  if (!canonVersion) {
    return json({ error: `Latest ACTIVE ${latestActive.canonId} has no Version Ratified` }, 422);
  }

  const notes = `Canon sync (PULL): SoT latest ACTIVE=${latestActive.canonId} ` +
                `version=${canonVersion} next_id=${nextId}. Source: fn-canon-sync v7.`;
  const actor = "AUTO-002B-PULL";

  const results: { project: string; success: boolean; error?: string }[] = [];

  const { error: ccxErr } = await ccx.rpc("update_canon_version", {
    p_version: canonVersion, p_next_id: nextId, p_actor: actor, p_notes: notes,
  });
  results.push({ project: "agent-codex-os", success: !ccxErr, error: ccxErr?.message });

  const sfxUrl = Deno.env.get("SFX_SUPABASE_URL") ?? "";
  const sfxKey = Deno.env.get("SFX_SERVICE_ROLE_KEY") ?? "";
  if (sfxUrl && sfxKey) {
    const sfx = createClient(sfxUrl, sfxKey);
    const { error: sfxErr } = await sfx.rpc("update_canon_version", {
      p_version: canonVersion, p_next_id: nextId, p_actor: actor, p_notes: notes,
    });
    results.push({ project: "shadowfox-os", success: !sfxErr, error: sfxErr?.message });
  } else {
    results.push({ project: "shadowfox-os", success: false, error: "SFX_SERVICE_ROLE_KEY not set" });
  }

  const allOk = results.every(r => r.success);
  console.log(`[fn-canon-sync v7] version=${canonVersion} next_id=${nextId}`, JSON.stringify(results));
  return json({
    status: allOk ? "SYNCED" : "PARTIAL",
    source: "airtable-sot",
    latest_active: latestActive.canonId,
    canon_version: canonVersion,
    canon_next_id: nextId,
    results,
  }, allOk ? 200 : 207);
});
