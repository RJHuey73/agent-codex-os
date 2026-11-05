// Runtime tests for the Airtable 429 breaker. Stubs fetch for Airtable,
// the sync-key RPC, and the sfx_canon_sync_breaker table.
let breakerState: { blocked_until: string | null } = { blocked_until: null };
const calls: string[] = [];
const realFetch = globalThis.fetch;

globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
  const method = init?.method ?? "GET";
  calls.push(`${method} ${url}`);
  if (url.startsWith("https://api.airtable.com/")) {
    return new Response("rate limited", { status: 429, headers: { "Retry-After": "30" } });
  }
  if (url.includes("/rest/v1/rpc/fn_sfx_sync_key_matches")) {
    return new Response("true", { status: 200, headers: { "Content-Type": "application/json" } });
  }
  if (url.includes("/rest/v1/sfx_canon_sync_breaker")) {
    if (method === "PATCH") {
      breakerState = { ...breakerState, ...JSON.parse(String(init?.body ?? "{}")) };
      return new Response(null, { status: 204 });
    }
    return new Response(JSON.stringify(breakerState), {
      status: 200, headers: { "Content-Type": "application/vnd.pgrst.object+json" },
    });
  }
  return new Response("unexpected", { status: 599 });
}) as typeof fetch;

Deno.env.set("SUPABASE_URL", "http://fake-supabase.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-key");
Deno.env.set("SFX_AIRTABLE_PAT", "test-pat");

await import("./index.ts");

const post = () => realFetch("http://localhost:8000/", {
  method: "POST", headers: { "x-sfx-sync-key": "test-key" },
});
const airtableCalls = () => calls.filter(c => c.includes("api.airtable.com")).length;

Deno.test("429 from Airtable opens the breaker and persists it", async () => {
  breakerState = { blocked_until: null };
  calls.length = 0;
  const res = await post();
  await res.text();
  if (res.status !== 429) throw new Error(`expected 429, got ${res.status}`);
  if (res.headers.get("Retry-After") !== "30") throw new Error("Retry-After missing");
  if (airtableCalls() !== 1) throw new Error(`expected 1 Airtable call, got ${airtableCalls()}`);
  if (!breakerState.blocked_until) throw new Error("breaker not persisted");
  const writes = calls.filter(c => c.startsWith("PATCH") && c.includes("sfx_canon_sync_breaker"));
  if (writes.length !== 1) throw new Error(`expected 1 breaker write, got ${writes.length}`);
});

Deno.test("open breaker skips Airtable entirely", async () => {
  breakerState = { blocked_until: new Date(Date.now() + 600_000).toISOString() };
  calls.length = 0;
  const res = await post();
  await res.text();
  if (res.status !== 429) throw new Error(`expected 429, got ${res.status}`);
  if (airtableCalls() !== 0) throw new Error(`expected 0 Airtable calls, got ${airtableCalls()}`);
});

Deno.test("expired breaker allows the pull again", async () => {
  breakerState = { blocked_until: new Date(Date.now() - 1000).toISOString() };
  calls.length = 0;
  const res = await post();
  await res.text();
  if (airtableCalls() !== 1) throw new Error(`expected Airtable to be called once, got ${airtableCalls()}`);
});
