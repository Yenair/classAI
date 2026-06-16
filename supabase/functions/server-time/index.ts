import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

// ---------------------------------------------------------------------------
// server-time Edge Function
//
// Returns the current server timestamp in ISO 8601 format.
// Used for secure subscription expiry checking.
// ---------------------------------------------------------------------------

serve(async (_req) => {
  try {
    const now = new Date();

    return new Response(
      JSON.stringify({
        server_time: now.toISOString(),
        timestamp: now.getTime(),
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
