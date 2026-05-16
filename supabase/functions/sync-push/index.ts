import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const { batches, device_id } = await req.json();
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const results: any[] = [];

    for (const batch of batches) {
      const { table, operation, record } = batch;
      let result: any = { local_id: record.local_id, status: "error" };

      if (operation === "INSERT") {
        // Map local_id -> new server UUID
        const { data, error } = await supabase
          .from(table)
          .insert({ ...record.data, id: undefined }) // let server generate UUID
          .select("id")
          .single();
        if (!error && data) {
          result = { local_id: record.local_id, server_id: data.id, status: "created" };
        }
      } else if (operation === "UPDATE") {
        const { error } = await supabase
          .from(table)
          .update(record.data)
          .eq("id", record.server_id);
        if (!error) result = { local_id: record.local_id, server_id: record.server_id, status: "updated" };
      } else if (operation === "DELETE") {
        const { error } = await supabase
          .from(table)
          .update({ deleted_at: new Date() }) // soft delete
          .eq("id", record.server_id);
        if (!error) result = { local_id: record.local_id, server_id: record.server_id, status: "deleted" };
      }
      results.push(result);
    }

    return new Response(JSON.stringify({ results }), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});