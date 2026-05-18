import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface RealtimeEvent {
  event_id: number;
  table: string;
  record_id: string;
  event_type: string;
  payload: Record<string, unknown>;
  created_at: string;
}

serve(async (req) => {
  try {
    // Accept parameters from both URL query params (for direct HTTP calls)
    // and JSON body (for Supabase client SDK calls).
    const url = new URL(req.url);

    let sinceEventId: number;
    let schoolId: string;

    // Try query params first, then body
    if (url.searchParams.has("since_event_id") || url.searchParams.has("school_id")) {
      const rawSince = url.searchParams.get("since_event_id") || "0";
      sinceEventId = parseInt(rawSince, 10);
      if (isNaN(sinceEventId) || sinceEventId < 0) sinceEventId = 0;

      const rawSchool = url.searchParams.get("school_id");
      if (!rawSchool) {
        return new Response(
          JSON.stringify({ error: "Missing required query parameter: school_id" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }
      schoolId = rawSchool;
    } else {
      // Parse request body
      const body = await req.json();
      sinceEventId = body.since_event_id ?? body.sinceEventId ?? 0;
      if (typeof sinceEventId !== "number" || sinceEventId < 0) sinceEventId = 0;

      schoolId = body.school_id ?? body.schoolId;
      if (!schoolId) {
        return new Response(
          JSON.stringify({ error: "Missing required field: school_id" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Query realtime_events for events after sinceEventId, ordered by id ASC
    const { data, error } = await supabase
      .from("realtime_events")
      .select("id, table_name, record_id, event_type, payload, created_at")
      .eq("school_id", schoolId)
      .gt("id", sinceEventId)
      .order("id", { ascending: true })
      .limit(100);

    if (error) {
      console.error("sync-realtime-events: query error:", error.message);
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Map DB rows to the response format expected by SyncRealtimePage.fromJson()
    const events: RealtimeEvent[] = (data ?? []).map((row) => ({
      event_id: row.id,
      table: row.table_name,
      record_id: row.record_id,
      event_type: row.event_type,
      payload: row.payload ?? {},
      created_at: row.created_at,
    }));

    // Determine the latest event id from the returned set
    const latestEventId = events.length > 0
      ? Math.max(...events.map((e) => e.event_id))
      : sinceEventId;

    return new Response(
      JSON.stringify({ events, latest_event_id: latestEventId }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("sync-realtime-events: unexpected error:", err.message);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
