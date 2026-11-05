const calls: string[] = [];
const realFetch = globalThis.fetch;
globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
  calls.push(`${init?.method ?? "GET"} ${url}`);
  if (url.startsWith("https://api.airtable.com/")) {
    return new Response("rate limited", { status: 429, headers: { "Retry-After": "30" } });
  }
  if (url.includes("/rest/v1/rpc/fn_sfx_sync_key_matches")) {
    return new Response("true", { status: 200, headers: { "Content-Type": "application/json" } });
  }
  return new Response("unexpected", { status: 599 });
}) as typeof fetch;

Deno.env.set("SUPABASE_URL", "http://fake-supabase.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-key");
Deno.env.set("SFX_AIRTABLE_PAT", "test-pat");

await import("./index.ts");

Deno.test("429 from Airtable returns 429 + Retry-After and writes nothing", async () => {
  calls.length = 0;
  const res = await realFetch("http://localhost:8000/", {
    method: "POST",
    headers: { "x-sfx-sync-key": "test-key" },
  });
  const body = await res.text();
  if (res.status !== 429) throw new Error(`expected 429, got ${res.status}: ${body}`);
  if (res.headers.get("Retry-After") !== "30") throw new Error(`Retry-After missing: ${res.headers.get("Retry-After")}`);
  const airtableCalls = calls.filter(c => c.includes("api.airtable.com"));
  if (airtableCalls.length !== 1) throw new Error(`expected 1 Airtable call (no retry), got ${airtableCalls.length}`);
  const writes = calls.filter(c => !c.startsWith("GET") && !c.includes("fn_sfx_sync_key_matches") && !c.includes("api.airtable.com"));
  if (writes.length) throw new Error(`unexpected writes: ${writes.join(", ")}`);
});
