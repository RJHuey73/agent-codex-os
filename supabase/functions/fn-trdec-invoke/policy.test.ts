// Run with: node --test supabase/functions/fn-trdec-invoke/policy.test.ts (Node >= 22.18)
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  AUTHORITY_CAP_TIER,
  checkClaims,
  exceedsAuthorityCap,
  exceedsTrustCap,
  meetsFloor,
  provenanceBinding,
  tierRank,
} from "./policy.ts";

test("tier direction: T0 is the highest authority", () => {
  assert.ok(tierRank(0) > tierRank(1));
  assert.ok(tierRank(1) > tierRank(2));
  assert.ok(tierRank(2) > tierRank(5));
  assert.throws(() => tierRank(6), RangeError);
  assert.throws(() => tierRank(-1), RangeError);
  assert.throws(() => tierRank(1.5), RangeError);
});

test("G1: the cap is T2; claiming T0/T1 exceeds it, T2..T5 do not", () => {
  assert.equal(AUTHORITY_CAP_TIER, 2);
  assert.equal(exceedsAuthorityCap(0), true);
  assert.equal(exceedsAuthorityCap(1), true);
  for (const t of [2, 3, 4, 5]) assert.equal(exceedsAuthorityCap(t), false, `T${t}`);
});

test("G4: trust is capped at VALIDATED", () => {
  assert.equal(exceedsTrustCap("STRUCTURED"), false);
  assert.equal(exceedsTrustCap("VALIDATED"), false);
  assert.equal(exceedsTrustCap("RATIFIED"), true);
  assert.equal(exceedsTrustCap("SOVEREIGN"), true);
});

test("checkClaims: reject reasons", () => {
  const ok = { authority_tier: 2, packet_trust_state: "VALIDATED" as const };
  const F = "VALIDATED";
  assert.equal(checkClaims(ok, "TRDEC-A03", true, F), null);
  assert.equal(checkClaims({ ...ok, authority_tier: 0 }, "TRDEC-A03", true, F), "AUTHORITY_CAP_EXCEEDED");
  assert.equal(checkClaims({ ...ok, packet_trust_state: "RATIFIED" }, "TRDEC-A03", true, F), "TRUST_CAP_EXCEEDED");
  assert.equal(checkClaims({ ...ok, requested_agent_id: "TRDEC-A02" }, "TRDEC-A03", true, F), "AGENT_OVERRIDE_MISMATCH");
  assert.equal(checkClaims({ ...ok, requested_agent_id: "TRDEC-A03" }, "TRDEC-A03", true, F), null);
  assert.equal(checkClaims(ok, "TRDEC-A03", false, F), "AGENT_NOT_LIVE", "DB flag must also allow");
  assert.equal(checkClaims(ok, "TRDEC-A06", true, F), "AGENT_NOT_LIVE", "A06–A13 not live");
  assert.equal(checkClaims(ok, "TRDEC-A13", true, F), "AGENT_NOT_LIVE", "A13 never invocable here");
});

test("floor (enforce): packet trust must meet the registry floor by rank", () => {
  const ok = { authority_tier: 2, packet_trust_state: "VALIDATED" as const };
  // Live registry floors: A01/A02/A04 RATIFIED, A03/A05 VALIDATED.
  for (const a of ["TRDEC-A01", "TRDEC-A02", "TRDEC-A04"]) assert.equal(checkClaims(ok, a, true, "RATIFIED"), "BELOW_AGENT_FLOOR", a);
  assert.equal(checkClaims(ok, "TRDEC-A03", true, "VALIDATED"), null);
  assert.equal(checkClaims({ ...ok, packet_trust_state: "STRUCTURED" }, "TRDEC-A03", true, "VALIDATED"), "BELOW_AGENT_FLOOR");
  // Rank, not string order: "RATIFIED" < "VALIDATED" alphabetically, but ranks above it.
  assert.equal(meetsFloor("VALIDATED", "RATIFIED"), false);
  assert.equal(meetsFloor("VALIDATED", "STRUCTURED"), true);
  // Fail closed on a missing or unknown floor.
  for (const bad of [undefined, null, "", "validated", "SOVEREIGNTY"]) assert.equal(checkClaims(ok, "TRDEC-A03", true, bad), "BELOW_AGENT_FLOOR", String(bad));
});

test("G7: provenance binding is fixed server-side", () => {
  assert.deepEqual(provenanceBinding(), {
    source_tier: "sfx-t2", ratified: false, authority_cap: "T2", trust_cap: "VALIDATED", bound_by: "fn-trdec-invoke v6",
  });
});
