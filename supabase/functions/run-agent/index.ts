/**
 * run-agent — DISABLED stub (GO-4c, T0 2026-10-10)
 *
 * Replaces run-agent v21 (generic DAG runner). v21 let any caller holding the
 * shared key choose arbitrary LLM providers and models with no budget, fetch
 * caller-controlled URLs through the http_fetch tool, and run unvalidated
 * graphs. It had no callers in the 24h before this change.
 *
 * Every request now gets 410 Gone. The stub reads nothing, writes nothing,
 * calls nothing, and holds no credentials. A governed replacement built on
 * packages/agents waits on the T0 ruling for Edge Function wiring.
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve((_req: Request) =>
  new Response(
    JSON.stringify({
      error: "Gone",
      message: "run-agent is disabled pending a governed replacement.",
    }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  )
);
