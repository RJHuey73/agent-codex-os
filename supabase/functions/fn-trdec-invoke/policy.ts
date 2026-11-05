/**
 * fn-trdec-invoke caller policy (GO-4b, T0 rulings 2026-10-10).
 * Pure functions with no Deno or Supabase APIs, unit-tested in policy.test.ts.
 *
 * G1: the invoke key may claim at most T2. Tier numbers are inverted, since a
 *     lower number means more authority (T0 is highest), so all comparisons go
 *     through tierRank(). Never compare tier numbers directly.
 * G3: live agents are A01–A05 only. A13 is T0-direct and never invocable here.
 * G4: incoming packet trust is capped at VALIDATED (STAGED ≠ ratified).
 * G7: every output carries a server-side ProvenanceBinding.
 * Floor (T0 ruling `enforce`, 2026-10-10): the packet's trust must meet the
 *     routed agent's trdec_agents.trust_state_floor, compared by enum rank.
 *     An unknown or missing floor rejects (fail closed).
 * A05 code reject (T0 2026-10-10): an agent whose own logic requires more trust
 *     than its registry floor gets a code-level floor too. The effective floor is
 *     the higher of the two, so the request is refused before any write instead of
 *     hard-stopping inside the agent after packets are persisted.
 */

export const TIERS = ["T0", "T1", "T2", "T3", "T4", "T5"] as const;
export type TierName = (typeof TIERS)[number];

/** Authority rank, higher means more authority: T0 → 5 … T5 → 0. */
export function tierRank(tier: number): number {
  if (!Number.isInteger(tier) || tier < 0 || tier > 5) throw new RangeError(`invalid authority tier ${tier}`);
  return 5 - tier;
}

/** Highest authority the invoke key may claim (G1 ruling: T2). */
export const AUTHORITY_CAP_TIER = 2;

/** True when the claim asks for more authority than the cap allows. */
export function exceedsAuthorityCap(claimedTier: number, capTier: number = AUTHORITY_CAP_TIER): boolean {
  return tierRank(claimedTier) > tierRank(capTier);
}

export const TRUST_ORDER = ["STRUCTURED", "VALIDATED", "RATIFIED", "SOVEREIGN"] as const;
export type TrustState = (typeof TRUST_ORDER)[number];

/** Highest incoming packet trust accepted on this path (G4). */
export const TRUST_CAP: TrustState = "VALIDATED";

/** Rank of a trust state, or -1 when the value is not a known state. */
export function trustRank(state: unknown): number {
  return TRUST_ORDER.indexOf(state as TrustState);
}

/** True when the packet meets the agent's floor. Unknown values never meet it. */
export function meetsFloor(packet: TrustState, floor: unknown): boolean {
  const p = trustRank(packet), f = trustRank(floor);
  return p >= 0 && f >= 0 && p >= f;
}

/**
 * Code-level floors for agents whose runtime logic demands more than the
 * ratified registry floor. The registry rows are write-once, so this is where
 * the stricter requirement lives. A05 (Liaison) hard-stops below RATIFIED.
 */
export const CODE_TRUST_FLOOR: Readonly<Record<string, TrustState>> = { "TRDEC-A05": "RATIFIED" };

/** The higher of the registry floor and any code-level floor; unknown registry values stay unknown. */
export function effectiveFloor(routedAgentId: string, dbFloor: unknown): unknown {
  const code = CODE_TRUST_FLOOR[routedAgentId];
  if (code === undefined || trustRank(dbFloor) < 0) return dbFloor;
  return trustRank(code) > trustRank(dbFloor) ? code : dbFloor;
}

export function exceedsTrustCap(claimed: TrustState, cap: TrustState = TRUST_CAP): boolean {
  return TRUST_ORDER.indexOf(claimed) > TRUST_ORDER.indexOf(cap);
}

/** G3 ruling: the live set. A06–A13 stay unreachable until CANON-307 is ratified. */
export const LIVE_AGENT_ALLOWLIST: readonly string[] = ["TRDEC-A01", "TRDEC-A02", "TRDEC-A03", "TRDEC-A04", "TRDEC-A05"];

export type RejectReason =
  | "AUTHORITY_CAP_EXCEEDED"
  | "TRUST_CAP_EXCEEDED"
  | "AGENT_OVERRIDE_MISMATCH"
  | "AGENT_NOT_LIVE"
  | "BELOW_AGENT_FLOOR";

export interface CallerClaims {
  authority_tier: number;
  packet_trust_state: TrustState;
  requested_agent_id?: string;
}

/**
 * Decide whether the caller's claims are acceptable for the routed agent.
 * Returns null when allowed, otherwise the first reject reason.
 * `dbInvocable` and `dbFloor` come from the routed agent's trdec_agents row.
 * Both the flag and the allowlist must allow the agent, and the packet must meet the floor.
 */
export function checkClaims(claims: CallerClaims, routedAgentId: string, dbInvocable: boolean, dbFloor: unknown): RejectReason | null {
  if (exceedsAuthorityCap(claims.authority_tier)) return "AUTHORITY_CAP_EXCEEDED";
  if (exceedsTrustCap(claims.packet_trust_state)) return "TRUST_CAP_EXCEEDED";
  if (claims.requested_agent_id !== undefined && claims.requested_agent_id !== routedAgentId) return "AGENT_OVERRIDE_MISMATCH";
  if (!LIVE_AGENT_ALLOWLIST.includes(routedAgentId) || !dbInvocable) return "AGENT_NOT_LIVE";
  if (!meetsFloor(claims.packet_trust_state, effectiveFloor(routedAgentId, dbFloor))) return "BELOW_AGENT_FLOOR";
  return null;
}

/** G7: server-side provenance stamped on every output; never taken from the caller. */
export function provenanceBinding(): { source_tier: "sfx-t2"; ratified: false; authority_cap: TierName; trust_cap: TrustState; bound_by: string } {
  return {
    source_tier: "sfx-t2",
    ratified: false,
    authority_cap: TIERS[AUTHORITY_CAP_TIER]!,
    trust_cap: TRUST_CAP,
    bound_by: "fn-trdec-invoke v7",
  };
}
