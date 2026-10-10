/**
 * fn-trdec-invoke v7 — Tridecagon invocation
 * v7 (T0 A05 ruling `code reject`, 2026-10-10):
 *   - policy.ts CODE_TRUST_FLOOR raises A05 (Liaison) to RATIFIED, matching its own
 *     runtime check, so A05 is refused with 403 BELOW_AGENT_FLOOR before any write
 *     instead of persisting a HARD_STOP row. The registry rows stay untouched.
 * v6 (T0 floor ruling `enforce`, 2026-10-10):
 *   - Packet trust must meet the routed agent's trdec_agents.trust_state_floor,
 *     compared by enum rank (policy.ts meetsFloor). Below floor → 403
 *     BELOW_AGENT_FLOOR before any write; an unknown floor fails closed.
 *     At the T2/VALIDATED cap only A03 (floor VALIDATED) is reachable.
 *   - Arbiter's STRUCTURED hard-stop message no longer claims a RATIFIED floor.
 * v5 (GO-4b, T0 2026-10-10; rulings G1=T2, G3=A01–A05 option a):
 *   - G1: claims above T2 authority → 403 (tier rank, T0 highest; see policy.ts).
 *   - G4: packet_trust_state above VALIDATED → 403.
 *   - G2: an agent_id that differs from the router's choice → 403 (no override).
 *   - G3: routed agent must be in the A01–A05 allowlist AND trdec_agents.invocable.
 *   - G5: canon_id may be null (fn_trdec_invoke_db no longer invents one).
 *   - G7: server-side ProvenanceBinding (sfx-t2, ratified=false) on every output.
 *   - Rejections return 403 and emit a structured TRDEC_INVOKE_REJECTED log event
 *     before any write. dry_run=true returns the decision and writes nothing.
 *   - G6 (registry ACTIVE/can_execute) deferred: no TRDEC→registry mapping exists.
 * v4 (GO-4a, T0 2026-10-10) — auth hardening only, invocation logic unchanged:
 *   - Key is the per-function Vault secret `trdec_invoke_key`, verified in-DB by
 *     public.fn_trdec_invoke_key_matches() (service_role only, hash compare).
 *     The SFX_SYNC_KEY env var is no longer used.
 *   - Only the x-sfx-sync-key header is accepted (no Authorization/Bearer).
 *   - Fails closed: missing header or mismatch => 401; verifier error => 503.
 *   - 500 responses no longer echo internal error text (`detail`).
 * v3 lineage: SFX-SESSION-20260611 Phase 2 | CANON-304/305/306
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkClaims, provenanceBinding, type RejectReason, type TrustState } from "./policy.ts";

export type GovernanceTrust = "TRUSTED" | "SANDBOXED" | "UNTRUSTED";
export type PacketTrustState = "STRUCTURED" | "VALIDATED" | "RATIFIED" | "SOVEREIGN";
export type AuthorityTier = 0 | 1 | 2 | 3 | 4 | 5;
export type Regime = "PROD" | "SANDBOX" | "DEV";

export interface GovernanceEnvelope {
  context_id: string; binding_id: string; authority_tier: AuthorityTier;
  regime: Regime; governance_trust: GovernanceTrust; canon_version: string;
  canon_id: string | null; labels?: Record<string, unknown>;
}

export type LiveAgentId = "TRDEC-A01" | "TRDEC-A02" | "TRDEC-A03" | "TRDEC-A04" | "TRDEC-A05";
export type PacketDirection = "IN" | "OUT";
export type ProvenanceEventType = "NORMAL_INVOCATION" | "WITNESS_INVOCATION_ATTEMPT" | "HARD_STOP" | "TRUST_VIOLATION" | "CLUSTER_VIOLATION" | "CONSTRAINT_VIOLATION";
export type InvocationResultStatus = "SUCCESS" | "HARD_STOP" | "ERROR";
export type ClusterId = "TRDEC-C1" | "TRDEC-C2" | "TRDEC-C3" | "TRDEC-C4" | "TRDEC-C5" | "TRDEC-WITNESS";

export interface TrdecInvokeRequest {
  agent_id?: LiveAgentId; intent?: string; audit?: boolean;
  payload: unknown; metadata?: Record<string, unknown>;
  governance: GovernanceEnvelope; packet_trust_state?: PacketTrustState;
}

export interface TrdecAgentDef {
  agent_id: LiveAgentId; cluster_id: ClusterId; canonical_name: string;
  can_write_data: boolean; can_block_execution: boolean; can_initiate_execution: boolean;
  can_flag: boolean; can_quarantine: boolean; can_read: boolean; can_score: boolean;
  can_write_memory: boolean; can_route: boolean; can_dispatch: boolean;
  canon_write_authority: boolean; trust_state_floor: PacketTrustState;
  min_governance_trust: GovernanceTrust; min_authority_tier: AuthorityTier;
  invocation_surfaces: string[];
}

const AGENT_REGISTRY: Record<LiveAgentId, TrdecAgentDef> = {
  "TRDEC-A01": { agent_id: "TRDEC-A01", cluster_id: "TRDEC-C1", canonical_name: "The Arbiter", can_write_data: false, can_block_execution: true, can_initiate_execution: false, can_flag: false, can_quarantine: false, can_read: true, can_score: false, can_write_memory: false, can_route: true, can_dispatch: false, canon_write_authority: false, trust_state_floor: "RATIFIED", min_governance_trust: "TRUSTED", min_authority_tier: 1, invocation_surfaces: ["governance_gate", "truststate_check"] },
  "TRDEC-A02": { agent_id: "TRDEC-A02", cluster_id: "TRDEC-C2", canonical_name: "The Warden", can_write_data: false, can_block_execution: true, can_initiate_execution: false, can_flag: true, can_quarantine: true, can_read: true, can_score: false, can_write_memory: false, can_route: false, can_dispatch: false, canon_write_authority: false, trust_state_floor: "RATIFIED", min_governance_trust: "SANDBOXED", min_authority_tier: 2, invocation_surfaces: ["anomaly_detection", "rls_monitor", "immutability_check"] },
  "TRDEC-A03": { agent_id: "TRDEC-A03", cluster_id: "TRDEC-C3", canonical_name: "The Assessor", can_write_data: false, can_block_execution: false, can_initiate_execution: false, can_flag: true, can_quarantine: false, can_read: true, can_score: true, can_write_memory: false, can_route: false, can_dispatch: false, canon_write_authority: false, trust_state_floor: "VALIDATED", min_governance_trust: "SANDBOXED", min_authority_tier: 2, invocation_surfaces: ["invocation_scoring", "canon_compliance_check", "truststate_delta_eval"] },
  "TRDEC-A04": { agent_id: "TRDEC-A04", cluster_id: "TRDEC-C4", canonical_name: "The Archivist", can_write_data: false, can_block_execution: false, can_initiate_execution: false, can_flag: false, can_quarantine: false, can_read: true, can_score: false, can_write_memory: true, can_route: false, can_dispatch: false, canon_write_authority: false, trust_state_floor: "RATIFIED", min_governance_trust: "TRUSTED", min_authority_tier: 1, invocation_surfaces: ["trdec_agent_state", "trdec_agent_state_snapshots"] },
  "TRDEC-A05": { agent_id: "TRDEC-A05", cluster_id: "TRDEC-C5", canonical_name: "The Liaison", can_write_data: false, can_block_execution: false, can_initiate_execution: false, can_flag: false, can_quarantine: false, can_read: true, can_score: false, can_write_memory: false, can_route: true, can_dispatch: true, canon_write_authority: false, trust_state_floor: "VALIDATED", min_governance_trust: "TRUSTED", min_authority_tier: 1, invocation_surfaces: ["make_com", "supabase", "canon_write_gateway"] },
};

function getAgent(id: string): TrdecAgentDef {
  const a = AGENT_REGISTRY[id as LiveAgentId];
  if (!a) throw new Error(`Unknown agent_id: ${id}`);
  return a;
}

type HarmonicIntent = "analysis" | "memory" | "evaluation" | "integration" | "safety" | "audit" | "unknown";
interface RouterDecision { cluster_id: ClusterId; agent_id: LiveAgentId | null; reason: string; is_witness: boolean; }

function normalizeIntent(raw: string): HarmonicIntent {
  const v: HarmonicIntent[] = ["analysis", "memory", "evaluation", "integration", "safety", "audit", "unknown"];
  return v.includes(raw as HarmonicIntent) ? (raw as HarmonicIntent) : "unknown";
}

function decideRoute(input: { intent: string; governance_trust: GovernanceTrust; authority_tier: AuthorityTier; audit?: boolean }): RouterDecision {
  const intent = normalizeIntent(input.intent ?? "unknown");
  const { governance_trust, authority_tier, audit } = input;
  if (audit || intent === "audit") return { cluster_id: "TRDEC-WITNESS", agent_id: null, reason: "audit=true -> Witness (non-invocable until CANON-318)", is_witness: true };
  if (authority_tier >= 3) return { cluster_id: "TRDEC-C2", agent_id: "TRDEC-A02", reason: `tier=${authority_tier} >= T3 -> Warden`, is_witness: false };
  if (governance_trust === "UNTRUSTED" && ["analysis","integration","safety","unknown"].includes(intent)) return { cluster_id: "TRDEC-C2", agent_id: "TRDEC-A02", reason: `UNTRUSTED+${intent} -> Warden`, is_witness: false };
  switch (intent) {
    case "analysis": return { cluster_id: "TRDEC-C1", agent_id: "TRDEC-A01", reason: `analysis/${governance_trust} -> Arbiter`, is_witness: false };
    case "memory": return governance_trust === "TRUSTED" ? { cluster_id: "TRDEC-C4", agent_id: "TRDEC-A04", reason: "memory/TRUSTED -> Archivist", is_witness: false } : { cluster_id: "TRDEC-C3", agent_id: "TRDEC-A03", reason: `memory/${governance_trust} -> Assessor`, is_witness: false };
    case "evaluation": return { cluster_id: "TRDEC-C3", agent_id: "TRDEC-A03", reason: `evaluation -> Assessor`, is_witness: false };
    case "integration": return { cluster_id: "TRDEC-C5", agent_id: "TRDEC-A05", reason: `integration -> Liaison`, is_witness: false };
    case "safety": return { cluster_id: "TRDEC-C2", agent_id: "TRDEC-A02", reason: `safety -> Warden`, is_witness: false };
    default: return governance_trust === "SANDBOXED" ? { cluster_id: "TRDEC-C3", agent_id: "TRDEC-A03", reason: "unknown/SANDBOXED -> Assessor", is_witness: false } : { cluster_id: "TRDEC-C1", agent_id: "TRDEC-A01", reason: "unknown/TRUSTED -> Arbiter", is_witness: false };
  }
}

interface AgentOutput {
  result_status: InvocationResultStatus; output_payload: unknown;
  trust_state_after: PacketTrustState; hard_stop_reason?: string;
  t1_notes?: string; anomalies?: { type: string; severity: string; detail: string; escalate_to_t1: boolean }[];
  scores?: { governance_alignment: number; canon_compliance: number; trust_state_validity: number; overall: number; flags: string[]; recommendation: string; requires_t1_triage: true };
  dispatch_target?: string; state_version?: bigint;
}

function isTrustEscalation(before: PacketTrustState, req: PacketTrustState): boolean {
  const o: PacketTrustState[] = ["STRUCTURED","VALIDATED","RATIFIED","SOVEREIGN"];
  return o.indexOf(req) > o.indexOf(before);
}

function runArbiter(req: TrdecInvokeRequest, gov: GovernanceEnvelope, ts: PacketTrustState): AgentOutput {
  if (req.intent === "audit") return { result_status: "HARD_STOP", output_payload: { blocked: true }, trust_state_after: ts, hard_stop_reason: "WITNESS_INVOCATION_ATTEMPT" };
  if (ts === "STRUCTURED") return { result_status: "HARD_STOP", output_payload: { blocked: true }, trust_state_after: ts, hard_stop_reason: "TRUST_VIOLATION — STRUCTURED packet rejected" };
  const issues: string[] = [];
  if (gov.authority_tier >= 3 && gov.governance_trust === "TRUSTED") issues.push(`tier=${gov.authority_tier} claims TRUSTED — inconsistent`);
  return { result_status: "SUCCESS", output_payload: { gate_passed: issues.length === 0, issues, governance_summary: { authority_tier: gov.authority_tier, governance_trust: gov.governance_trust, regime: gov.regime, canon_version: gov.canon_version } }, trust_state_after: ts, t1_notes: issues.length > 0 ? `Arbiter flagged: ${issues.join("; ")}` : undefined };
}

function runWarden(req: TrdecInvokeRequest, gov: GovernanceEnvelope, ts: PacketTrustState): AgentOutput {
  const anomalies: AgentOutput["anomalies"] = [];
  if (req.packet_trust_state && isTrustEscalation(ts, req.packet_trust_state)) anomalies!.push({ type: "TRUST_ESCALATION_ATTEMPT", severity: "CRITICAL", detail: `${ts} -> ${req.packet_trust_state}`, escalate_to_t1: true });
  if (gov.authority_tier >= 3 && gov.governance_trust !== "UNTRUSTED") anomalies!.push({ type: "AUTHORITY_MISMATCH", severity: "MEDIUM", detail: `T${gov.authority_tier} claims ${gov.governance_trust}`, escalate_to_t1: false });
  if (gov.regime === "PROD" && gov.authority_tier >= 2) { anomalies!.push({ type: "CONSTRAINT_VIOLATION", severity: "HIGH", detail: `PROD write T${gov.authority_tier}`, escalate_to_t1: true }); return { result_status: "HARD_STOP", output_payload: { quarantined: true, anomalies }, trust_state_after: ts, hard_stop_reason: "CONSTRAINT_VIOLATION — PROD write blocked T2+", anomalies }; }
  if (anomalies!.some(a => a.severity === "CRITICAL")) return { result_status: "HARD_STOP", output_payload: { quarantined: true, anomalies }, trust_state_after: ts, hard_stop_reason: "TRUST_VIOLATION — critical anomalies", anomalies };
  return { result_status: "SUCCESS", output_payload: { cleared: true, anomaly_count: anomalies!.length, anomalies }, trust_state_after: ts, anomalies };
}

function runAssessor(_req: TrdecInvokeRequest, gov: GovernanceEnvelope, ts: PacketTrustState): AgentOutput {
  const flags: string[] = [];
  let ga = 1.0; if (gov.authority_tier >= 3) { ga -= 0.3; flags.push("low_authority_tier"); } if (gov.governance_trust === "UNTRUSTED") { ga -= 0.4; flags.push("untrusted_caller"); } if (!gov.canon_id || !gov.canon_version) { ga -= 0.2; flags.push("missing_canon_provenance"); } ga = Math.max(0, ga);
  let cc = 1.0; if (!gov.context_id) { cc -= 0.5; flags.push("missing_context_id"); } if (!gov.binding_id) { cc -= 0.3; flags.push("missing_binding_id"); } cc = Math.max(0, cc);
  let tv = 1.0; if (ts === "STRUCTURED") { tv = 0.5; flags.push("low_trust_state"); }
  const overall = (ga + cc + tv) / 3;
  const recommendation = overall >= 0.8 ? "PASS" : overall >= 0.5 ? "CONDITIONAL — T1 review required" : "FAIL — multiple gaps";
  const scores = { governance_alignment: ga, canon_compliance: cc, trust_state_validity: tv, overall, flags, recommendation, requires_t1_triage: true as const };
  return { result_status: "SUCCESS", output_payload: { scored: true, scores }, trust_state_after: ts, scores, t1_notes: `[Assessor] score=${overall.toFixed(2)}. ${recommendation}.` };
}

function runArchivist(req: TrdecInvokeRequest, gov: GovernanceEnvelope, ts: PacketTrustState, cv: bigint): AgentOutput {
  if (gov.governance_trust !== "TRUSTED") return { result_status: "HARD_STOP", output_payload: { blocked: true }, trust_state_after: ts, hard_stop_reason: "CONSTRAINT_VIOLATION — Archivist requires TRUSTED" };
  const next_version = cv + 1n;
  return { result_status: "SUCCESS", output_payload: { archived: true, state_delta: { last_invocation_at: new Date().toISOString(), canon_version: gov.canon_version, canon_id: gov.canon_id }, next_version: next_version.toString() }, trust_state_after: ts, state_version: next_version };
}

function runLiaison(req: TrdecInvokeRequest, gov: GovernanceEnvelope, ts: PacketTrustState): AgentOutput {
  if (ts !== "RATIFIED" && ts !== "SOVEREIGN") return { result_status: "HARD_STOP", output_payload: { blocked: true }, trust_state_after: ts, hard_stop_reason: `CONSTRAINT_VIOLATION — Liaison requires RATIFIED, got ${ts}` };
  const target = ["make_com","supabase","canon_write_gateway"].includes((req.metadata?.dispatch_to as string) ?? "") ? (req.metadata!.dispatch_to as string) : "supabase";
  if (target === "canon_write_gateway" && gov.authority_tier > 1) return { result_status: "HARD_STOP", output_payload: { blocked: true }, trust_state_after: ts, hard_stop_reason: "CONSTRAINT_VIOLATION — canon write requires T0/T1" };
  return { result_status: "SUCCESS", output_payload: { dispatched: true, dispatch_target: target, packet_trust_state: ts }, trust_state_after: ts, dispatch_target: target };
}

const AGENT_LOGIC: Record<string, (r: TrdecInvokeRequest, g: GovernanceEnvelope, t: PacketTrustState, v?: bigint) => AgentOutput> = {
  "TRDEC-A01": (r, g, t) => runArbiter(r, g, t),
  "TRDEC-A02": (r, g, t) => runWarden(r, g, t),
  "TRDEC-A03": (r, g, t) => runAssessor(r, g, t),
  "TRDEC-A04": (r, g, t, v = 0n) => runArchivist(r, g, t, v),
  "TRDEC-A05": (r, g, t) => runLiaison(r, g, t),
};

type SupabaseClient = ReturnType<typeof createClient>;

function makeDB(c: SupabaseClient) {
  return {
    async insertPacket(row: { packet_id?: string; direction: PacketDirection; agent_id?: string; cluster_id?: string; trust_state: PacketTrustState; payload: unknown; action?: string; replay_id?: string; signature?: string }): Promise<string> {
      const id = row.packet_id ?? crypto.randomUUID();
      const { error } = await c.from("trdec_packets").insert({ packet_id: id, direction: row.direction, agent_id: row.agent_id ?? null, cluster_id: row.cluster_id ?? null, trust_state: row.trust_state, payload: row.payload, action: row.action ?? null, replay_id: row.replay_id ?? null, signature: row.signature ?? null });
      if (error) throw new Error(`packets: ${error.message}`); return id;
    },
    async insertInvocation(row: { invocation_id?: string; agent_id: string; cluster_id: string; input_packet_id: string; output_packet_id?: string; trust_state_before: PacketTrustState; trust_state_after: PacketTrustState; replay_signature: string; result_status: InvocationResultStatus; hard_stop_reason?: string }): Promise<string> {
      const id = row.invocation_id ?? crypto.randomUUID();
      const { error } = await c.from("trdec_invocations").insert({ invocation_id: id, agent_id: row.agent_id, cluster_id: row.cluster_id, input_packet_id: row.input_packet_id, output_packet_id: row.output_packet_id ?? null, trust_state_before: row.trust_state_before, trust_state_after: row.trust_state_after, replay_signature: row.replay_signature, result_status: row.result_status, hard_stop_reason: row.hard_stop_reason ?? null });
      if (error) throw new Error(`invocations: ${error.message}`); return id;
    },
    async insertProvenanceEvent(row: { event_id?: string; agent_id: string; cluster_id: string; invocation_id: string; trust_state_before: PacketTrustState; trust_state_after: PacketTrustState; input_packet_id: string; output_packet_id?: string; state_delta: Record<string, unknown>; replay_signature: string; event_type: ProvenanceEventType }): Promise<void> {
      const { error } = await c.from("trdec_provenance_events").insert({ event_id: row.event_id ?? crypto.randomUUID(), agent_id: row.agent_id, cluster_id: row.cluster_id, invocation_id: row.invocation_id, trust_state_before: row.trust_state_before, trust_state_after: row.trust_state_after, input_packet_id: row.input_packet_id, output_packet_id: row.output_packet_id ?? null, state_delta: row.state_delta, replay_signature: row.replay_signature, event_type: row.event_type });
      if (error) throw new Error(`provenance: ${error.message}`);
    },
    async getAgentState(agent_id: string): Promise<{ current_state: Record<string, unknown>; version: bigint } | null> {
      const { data, error } = await c.from("trdec_agent_state").select("current_state, version").eq("agent_id", agent_id).maybeSingle();
      if (error) throw new Error(`agent_state: ${error.message}`); if (!data) return null;
      return { current_state: data.current_state as Record<string, unknown>, version: BigInt(data.version) };
    },
    async upsertAgentState(row: { agent_id: string; current_state: Record<string, unknown>; version: bigint }): Promise<void> {
      const { error } = await c.from("trdec_agent_state").upsert({ agent_id: row.agent_id, current_state: row.current_state, version: row.version.toString(), updated_at: new Date().toISOString() }, { onConflict: "agent_id" });
      if (error) throw new Error(`agent_state upsert: ${error.message}`);
    },
    async insertTruststateTransition(row: { agent_id: string; cluster_id: string; invocation_id: string; from_state: PacketTrustState; to_state: PacketTrustState; reason: string }): Promise<void> {
      const { error } = await c.from("trdec_truststate_transitions").insert(row);
      if (error) throw new Error(`truststate_transitions: ${error.message}`);
    },
  };
}

function sig(agent_id: string, inv_id: string, before: PacketTrustState, after: PacketTrustState, cv: string): string {
  return `sig:${agent_id}:${inv_id}:${before}:${after}:${cv}`;
}

async function orchestrate(request: TrdecInvokeRequest, routing_agent_id: LiveAgentId, db: ReturnType<typeof makeDB>) {
  const agent = getAgent(routing_agent_id);
  const gov = request.governance;
  const ts_before: PacketTrustState = request.packet_trust_state ?? "STRUCTURED";
  const inv_id = crypto.randomUUID();

  const in_id = await db.insertPacket({ direction: "IN", agent_id: agent.agent_id, cluster_id: agent.cluster_id, trust_state: ts_before, payload: request.payload, action: request.intent ?? "unknown", replay_id: inv_id, signature: sig(agent.agent_id, inv_id, ts_before, ts_before, gov.canon_version) });

  const fn = AGENT_LOGIC[agent.agent_id];
  if (!fn) throw new Error(`No logic for ${agent.agent_id}`);

  let cv = 0n;
  if (agent.agent_id === "TRDEC-A04") { const ex = await db.getAgentState(agent.agent_id); cv = ex?.version ?? 0n; }

  const out = fn(request, gov, ts_before, cv);
  const ts_after = out.trust_state_after;
  const out_id = await db.insertPacket({ direction: "OUT", agent_id: agent.agent_id, cluster_id: agent.cluster_id, trust_state: ts_after, payload: out.output_payload, action: out.result_status, replay_id: inv_id, signature: sig(agent.agent_id, inv_id, ts_before, ts_after, gov.canon_version) });

  const replay_sig = sig(agent.agent_id, inv_id, ts_before, ts_after, gov.canon_version);
  await db.insertInvocation({ invocation_id: inv_id, agent_id: agent.agent_id, cluster_id: agent.cluster_id, input_packet_id: in_id, output_packet_id: out_id, trust_state_before: ts_before, trust_state_after: ts_after, replay_signature: replay_sig, result_status: out.result_status, hard_stop_reason: out.hard_stop_reason });

  const event_type: ProvenanceEventType = out.result_status === "HARD_STOP"
    ? (out.hard_stop_reason?.includes("WITNESS") ? "WITNESS_INVOCATION_ATTEMPT" : out.hard_stop_reason?.includes("TRUST") ? "TRUST_VIOLATION" : out.hard_stop_reason?.includes("CLUSTER") ? "CLUSTER_VIOLATION" : "CONSTRAINT_VIOLATION")
    : "NORMAL_INVOCATION";

  const state_delta: Record<string, unknown> = { provenance_binding: provenanceBinding(), trust_state_before: ts_before, trust_state_after: ts_after, result_status: out.result_status, canon_version: gov.canon_version, canon_id: gov.canon_id, authority_tier: gov.authority_tier, governance_trust: gov.governance_trust };
  if (out.anomalies?.length) state_delta.anomalies = out.anomalies;
  if (out.scores) state_delta.scores = out.scores;

  await db.insertProvenanceEvent({ agent_id: agent.agent_id, cluster_id: agent.cluster_id, invocation_id: inv_id, trust_state_before: ts_before, trust_state_after: ts_after, input_packet_id: in_id, output_packet_id: out_id, state_delta, replay_signature: replay_sig, event_type });

  const next_v = out.state_version ?? cv + 1n;
  const ex_state = await db.getAgentState(agent.agent_id);
  await db.upsertAgentState({ agent_id: agent.agent_id, current_state: { ...(ex_state?.current_state ?? {}), last_invocation_id: inv_id, last_invocation_at: new Date().toISOString(), last_result_status: out.result_status, last_trust_state: ts_after, last_canon_version: gov.canon_version }, version: next_v });

  if (ts_before !== ts_after) {
    const valid_to: PacketTrustState[] = ["STRUCTURED","VALIDATED","RATIFIED"];
    if (valid_to.includes(ts_after)) await db.insertTruststateTransition({ agent_id: agent.agent_id, cluster_id: agent.cluster_id, invocation_id: inv_id, from_state: ts_before, to_state: ts_after, reason: `${agent.canonical_name}: ${out.result_status}` });
  }

  return { invocation_id: inv_id, agent_id: agent.agent_id, cluster_id: agent.cluster_id, input_packet_id: in_id, output_packet_id: out_id, result_status: out.result_status, output_payload: out.output_payload, trust_state_before: ts_before, trust_state_after: ts_after, hard_stop_reason: out.hard_stop_reason, governance: gov };
}

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST, OPTIONS", "Access-Control-Allow-Headers": "Content-Type, x-sfx-sync-key" };
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json", "Connection": "keep-alive" } });
}

function parseGovernance(raw: Record<string, unknown>): GovernanceEnvelope | { error: string } {
  if (!raw.context_id || typeof raw.context_id !== "string") return { error: "governance.context_id required" };
  if (!raw.binding_id || typeof raw.binding_id !== "string") return { error: "governance.binding_id required" };
  if (typeof raw.authority_tier !== "number" || raw.authority_tier < 0 || raw.authority_tier > 5) return { error: "governance.authority_tier required (0-5)" };
  if (!["TRUSTED","SANDBOXED","UNTRUSTED"].includes(raw.governance_trust as string)) return { error: "governance.governance_trust: TRUSTED|SANDBOXED|UNTRUSTED" };
  if (!["PROD","SANDBOX","DEV"].includes(raw.regime as string)) return { error: "governance.regime: PROD|SANDBOX|DEV" };
  if (!raw.canon_version || typeof raw.canon_version !== "string") return { error: "governance.canon_version required" };
  if (raw.canon_id !== undefined && raw.canon_id !== null && typeof raw.canon_id !== "string") return { error: "governance.canon_id must be a string or null" };
  if (!Number.isInteger(raw.authority_tier)) return { error: "governance.authority_tier must be an integer" };
  return { context_id: raw.context_id, binding_id: raw.binding_id, authority_tier: raw.authority_tier as AuthorityTier, governance_trust: raw.governance_trust as GovernanceTrust, regime: raw.regime as Regime, canon_version: raw.canon_version, canon_id: (raw.canon_id as string | null | undefined) ?? null, labels: raw.labels as Record<string, unknown> | undefined };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json({ error: "Method Not Allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({ error: "Service unavailable" }, 503);
  const client = createClient(supabaseUrl, serviceKey);

  // Auth guard (fail closed) — must pass before GovernanceEnvelope check
  const provided = req.headers.get("x-sfx-sync-key");
  if (!provided) return json({ error: "Unauthorized — x-sfx-sync-key required" }, 401);
  const { data: keyOk, error: keyErr } = await client.rpc("fn_trdec_invoke_key_matches", { p_key: provided });
  if (keyErr) {
    console.error(`[fn-trdec-invoke v7] key verifier unavailable: ${keyErr.message}`);
    return json({ error: "Service unavailable" }, 503);
  }
  if (keyOk !== true) return json({ error: "Unauthorized — x-sfx-sync-key required" }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  if (!body.governance || typeof body.governance !== "object") return json({ error: "governance envelope required" }, 400);
  const govResult = parseGovernance(body.governance as Record<string, unknown>);
  if ("error" in govResult) return json({ error: govResult.error }, 400);
  const governance = govResult as GovernanceEnvelope;

  if (body.payload === undefined) return json({ error: "payload required" }, 400);
  const payload = body.payload;

  const valid_ts: PacketTrustState[] = ["STRUCTURED","VALIDATED","RATIFIED","SOVEREIGN"];
  const rts = body.packet_trust_state as string | undefined;
  const packet_trust_state: PacketTrustState = rts && valid_ts.includes(rts as PacketTrustState) ? rts as PacketTrustState : "STRUCTURED";

  const request: TrdecInvokeRequest = { agent_id: body.agent_id as LiveAgentId | undefined, intent: (body.intent as string) ?? (payload as Record<string, unknown>)?.intent as string, audit: body.audit === true, payload, metadata: body.metadata as Record<string, unknown> | undefined, governance, packet_trust_state };
  const routing = decideRoute({ intent: request.intent ?? "unknown", governance_trust: governance.governance_trust, authority_tier: governance.authority_tier, audit: request.audit });

  if (routing.is_witness) return json({ status: "WITNESS_ROUTED", message: "Non-invocable until CANON-318.", routing, governance: { context_id: governance.context_id, canon_version: governance.canon_version } });

  // GO-4b + floor rulings: caller claims and the effective floor are checked before any write.
  const target = routing.agent_id as LiveAgentId;
  const { data: agentRow, error: agentErr } = await client.from("trdec_agents").select("invocable, trust_state_floor").eq("agent_id", target).maybeSingle();
  if (agentErr) {
    console.error(`[fn-trdec-invoke v7] registry lookup failed: ${agentErr.message}`);
    return json({ error: "Service unavailable" }, 503);
  }
  const reject: RejectReason | null = checkClaims(
    { authority_tier: governance.authority_tier, packet_trust_state: packet_trust_state as TrustState, requested_agent_id: request.agent_id },
    target,
    agentRow?.invocable === true,
    agentRow?.trust_state_floor,
  );
  if (reject) {
    console.warn(JSON.stringify({ event: "TRDEC_INVOKE_REJECTED", reason: reject, routed_agent: target, requested_agent: request.agent_id ?? null, claimed_tier: governance.authority_tier, claimed_trust: packet_trust_state, context_id: governance.context_id }));
    return json({ error: "Forbidden", reason: reject, routing: { cluster_id: routing.cluster_id, agent_id: target } }, 403);
  }

  const provenance = provenanceBinding();
  if (body.dry_run === true) {
    return json({ status: "DRY_RUN", routing: { cluster_id: routing.cluster_id, agent_id: target, reason: routing.reason }, provenance, governance: { context_id: governance.context_id, authority_tier: governance.authority_tier, canon_id: governance.canon_id } });
  }

  const db = makeDB(client);

  try {
    const result = await orchestrate(request, target, db);
    return json({ status: result.result_status, invocation_id: result.invocation_id, agent: { id: result.agent_id, cluster_id: result.cluster_id }, routing: { cluster_id: routing.cluster_id, reason: routing.reason }, output: result.output_payload, trust: { before: result.trust_state_before, after: result.trust_state_after }, hard_stop_reason: result.hard_stop_reason ?? null, provenance, governance: { context_id: governance.context_id, authority_tier: governance.authority_tier, governance_trust: governance.governance_trust, regime: governance.regime, canon_version: governance.canon_version, canon_id: governance.canon_id } });
  } catch (err) {
    console.error("[fn-trdec-invoke v7]", err);
    return json({ error: "orchestration_error" }, 500);
  }
});
