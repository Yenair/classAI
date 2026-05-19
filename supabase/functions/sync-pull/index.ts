import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const { lastSyncTimestamp, tables } = await req.json();

    if (!Array.isArray(tables) || tables.length === 0) {
      return new Response(
        JSON.stringify({ error: "Request body must include a non-empty `tables` array." }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const PAGE_SIZE = 50;
    const changes: { table: string; row: Record<string, unknown> }[] = [];

    for (const table of tables) {
      let query = supabase
        .from(table)
        .select("*")
        .order("updated_at", { ascending: true })
        .limit(PAGE_SIZE);

      if (lastSyncTimestamp) {
        query = query.gt("updated_at", lastSyncTimestamp);
      }

      const { data, error } = await query;
      if (error) {
        console.warn(`sync-pull: error querying table "${table}": ${error.message}`);
        continue; // skip tables that don't exist or cause errors
      }

      if (data && data.length > 0) {
        for (const row of data) {
          changes.push({ table, row });
        }
      }
    }

    // Sort all changes globally by updated_at for deterministic ordering
    changes.sort((a, b) => {
      const aTime = a.row.updated_at as string | undefined;
      const bTime = b.row.updated_at as string | undefined;
      if (!aTime && !bTime) return 0;
      if (!aTime) return -1;
      if (!bTime) return 1;
      return aTime.localeCompare(bTime);
    });

    // Determine next_cursor from the last change's updated_at if we hit the page limit
    let nextCursor: string | null = null;
    if (changes.length >= PAGE_SIZE) {
      const lastChange = changes[changes.length - 1];
      nextCursor = (lastChange.row.updated_at as string) ?? null;
    }

    return new Response(
      JSON.stringify({ changes, next_cursor: nextCursor }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
