import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const { changes } = await req.json();

    if (!Array.isArray(changes)) {
      return new Response(
        JSON.stringify({ error: "Request body must include a `changes` array." }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    let processed = 0;

    for (const change of changes) {
      const { table, operation, rowData } = change;

      if (!table || !operation || !rowData) {
        console.warn(`sync-push: skipping invalid change entry`, change);
        continue;
      }

      const op = (operation as string).toUpperCase();

      try {
        if (op === "INSERT") {
          // Remove local-only fields; let server generate UUIDs
          const { local_id, localId, ...insertData } = rowData;
          const { error } = await supabase
            .from(table)
            .insert(insertData);
          if (error) {
            console.warn(`sync-push: INSERT error on "${table}": ${error.message}`);
            continue;
          }
        } else if (op === "UPDATE") {
          const serverId = rowData.server_id || rowData.serverId || rowData.id;
          if (!serverId) {
            console.warn(`sync-push: UPDATE on "${table}" missing server id`);
            continue;
          }
          const { local_id, localId, server_id, serverId, id, ...updateData } = rowData;
          const { error } = await supabase
            .from(table)
            .update(updateData)
            .eq("id", serverId);
          if (error) {
            console.warn(`sync-push: UPDATE error on "${table}": ${error.message}`);
            continue;
          }
        } else if (op === "DELETE") {
          const serverId = rowData.server_id || rowData.serverId || rowData.id;
          if (!serverId) {
            console.warn(`sync-push: DELETE on "${table}" missing server id`);
            continue;
          }
          // Soft delete
          const { error } = await supabase
            .from(table)
            .update({ deleted_at: new Date().toISOString(), is_deleted: true })
            .eq("id", serverId);
          if (error) {
            console.warn(`sync-push: DELETE error on "${table}": ${error.message}`);
            continue;
          }
        } else {
          console.warn(`sync-push: unknown operation "${operation}" on "${table}"`);
          continue;
        }

        processed++;
      } catch (innerErr) {
        console.warn(`sync-push: exception processing ${operation} on ${table}:`, innerErr);
        // continue processing remaining changes
      }
    }

    return new Response(
      JSON.stringify({ success: true, processed }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
