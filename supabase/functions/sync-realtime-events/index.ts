import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

// Placeholder Edge Function for realtime event replay.
//
// In production, wire this to a dedicated `realtime_events` table or
// Supabase Realtime broadcast. For now, it acknowledges the event
// and returns a no-op success response.
//
// Expected request body: { event: { ... } }

serve(async (req) => {
  try {
    const body = await req.json();

    // Log the event for debugging / observability
    console.log("sync-realtime-events received:", JSON.stringify(body));

    return new Response(
      JSON.stringify({ ok: true }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
