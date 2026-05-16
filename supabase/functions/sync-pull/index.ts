import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const url = new URL(req.url);
    const cursor = url.searchParams.get("cursor"); // ISO timestamp
    const schoolId = url.searchParams.get("school_id");
    const limit = parseInt(url.searchParams.get("limit") || "50");

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Pull changes from all syncable tables since cursor
    const tables = ["subjects", "lessons", "exams", "progress_logs", "vault_items", "scheme_of_work"];
    const changes: any[] = [];

    for (const table of tables) {
      let query = supabase
        .from(table)
        .select("*")
        .eq("school_id", schoolId)
        .order("updated_at", { ascending: true })
        .limit(limit);

      if (cursor) {
        query = query.gt("updated_at", cursor);
      }

      const { data, error } = await query;
      if (!error && data) {
        changes.push(...data.map((row: any) => ({ table, row })));
      }
    }

    // Sort by updated_at and paginate
    changes.sort((a, b) => a.row.updated_at.localeCompare(b.row.updated_at));
    const page = changes.slice(0, limit);
    const nextCursor = page.length > 0 ? page[page.length - 1].row.updated_at : null;

    return new Response(
      JSON.stringify({ changes: page, next_cursor: nextCursor }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});