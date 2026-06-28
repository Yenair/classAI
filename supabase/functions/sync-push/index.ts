import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

// Key compression map (mirrors PayloadCompressor._keyMap on the Dart side)
const KEY_MAP: Record<string, string> = {
  lid: "local_id",
  sid: "server_id",
  slid: "school_local_id",
  ssid: "school_server_id",
  tlid: "teacher_local_id",
  tsid: "teacher_server_id",
  subid: "subject_id",
  ca: "created_at",
  ua: "updated_at",
  del: "is_deleted",
  uc: "update_counter",
  lmb: "last_modified_by",
  ss: "sync_status",
  c: "content",
  ch: "content_hash",
  t: "topic",
  cl: "class_level",
  d: "difficulty",
  cur: "curriculum",
  w: "week",
  s: "subject",
  tn: "teacher_name",
  sn: "school_name",
  e: "email",
  r: "role",
  ia: "is_active",
  phv: "password_hash_version",
  sa: "salt",
  skw: "school_key_wrapped",
  st: "subscription_tier",
  ac: "active_curriculum",
  ts: "total_seats",
  sc: "short_code",
  lu: "logo_url",
  ed: "expiry_date",
  are: "admin_recovery_email",
  arev: "admin_recovery_email_verified",
  acode: "activation_code",
  id: "id",
  n: "name",
  desc: "description",
  tnum: "term_number",
  ay: "academic_year",
  sd: "start_date",
  ic: "is_current",
};

/** Decompress a compressed rowData map back to full key names. */
function decompressRow(rowData: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(rowData)) {
    const fullKey = KEY_MAP[key] ?? key;
    result[fullKey] = value;
  }
  return result;
}

/** Extract a value from rowData, checking compressed keys first, then full keys. */
function getValue(rowData: Record<string, unknown>, ...keys: string[]): unknown {
  for (const key of keys) {
    if (rowData[key] !== undefined) return rowData[key];
  }
  return undefined;
}

serve(async (req) => {
  try {
    // ── 1. Validate JWT and token_version ──────────────────────────────────
    const jwtSecret = Deno.env.get("JWT_SECRET");
    if (!jwtSecret) {
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: JWT_SECRET not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const classaiJwt = req.headers.get("x-classai-jwt");
    if (!classaiJwt) {
      return new Response(
        JSON.stringify({ error: "Missing authentication token" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    try {
      await validateTokenVersion(
        classaiJwt,
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        jwtSecret,
      );
    } catch (err) {
      const { error, code, status } = err as { error: string; code: string; status: number };
      return new Response(
        JSON.stringify({ error, code }),
        { status, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 2. Process sync-push request ───────────────────────────────────────
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
    const results: Record<string, unknown>[] = [];

    for (const change of changes) {
      const { table, operation, rowData } = change;

      if (!table || !operation || !rowData) {
        console.warn(`sync-push: skipping invalid change entry`, change);
        continue;
      }

      // Decompress rowData if it has short keys
      const fullRowData = decompressRow(rowData as Record<string, unknown>);

      const op = (operation as string).toUpperCase();

      try {
        if (op === "INSERT") {
          // Remove local-only fields; let server generate UUIDs
          const { local_id, localId, ...insertData } = fullRowData;
          const { data: insertData_, error } = await supabase
            .from(table)
            .insert(insertData)
            .select("id");
          if (error) {
            console.warn(`sync-push: INSERT error on "${table}": ${error.message}`);
            continue;
          }
          // Capture the server-generated UUID so it can be returned in results
          const generatedId = insertData_?.[0]?.id as string | undefined;
          if (generatedId) {
            // Store in a per-change map keyed by local_id
            (change as Record<string, unknown>)["__generated_id"] = generatedId;
          }
        } else if (op === "UPDATE") {
          const serverId = getValue(fullRowData, "server_id", "serverId", "id", "school_server_id", "teacher_server_id");
          if (!serverId) {
            console.warn(`sync-push: UPDATE on "${table}" missing server id`);
            continue;
          }
          const { local_id, localId, server_id, serverId: _sid, id, school_server_id, teacher_server_id, ...updateData } = fullRowData;
          const { error } = await supabase
            .from(table)
            .update(updateData)
            .eq("id", serverId);
          if (error) {
            console.warn(`sync-push: UPDATE error on "${table}": ${error.message}`);
            continue;
          }
        } else if (op === "DELETE") {
          const serverId = getValue(fullRowData, "server_id", "serverId", "id", "school_server_id", "teacher_server_id");
          if (!serverId) {
            console.warn(`sync-push: DELETE on "${table}" missing server id`);
            continue;
          }
          // Soft delete
          const { error } = await supabase
            .from(table)
            .update({ is_deleted: true })
            .eq("id", serverId);
          if (error) {
            console.warn(`sync-push: DELETE error on "${table}": ${error.message}`);
            continue;
          }
        } else if (op === "SPEND_CREDITS") {
          // Credits are managed client-side and by the sync-credits function.
          // No Supabase table modification needed.
          results.push({
            local_id: getValue(fullRowData, 'local_id', 'localId', 'id') ?? 0,
            server_id: null,
            status: 'skipped',
            retryable: false,
          });
          (change as Record<string, unknown>)["__skipped"] = true;
          continue;
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

    // Build per-entry results matching SyncPushResponse.fromJson expectations.
    // Each result includes local_id, status, server_id, and retryable.
    for (const change of changes) {
      // SPEND_CREDITS results were already pushed during processing
      if ((change as Record<string, unknown>)["__skipped"] === true) {
        continue;
      }
      const fullRowData = decompressRow(change.rowData as Record<string, unknown>);
      const localId = getValue(fullRowData, "local_id", "localId", "id");
      // Use the generated ID from INSERT, or fall back to the incoming server_id
      const generatedId = (change as Record<string, unknown>)["__generated_id"] as string | undefined;
      const serverId = generatedId ?? getValue(fullRowData, "server_id", "serverId", "id");
      results.push({
        local_id: localId ?? 0,
        status: "updated",
        server_id: serverId ?? null,
        retryable: false,
      });
    }

    return new Response(
      JSON.stringify({
        success: true,
        processed,
        results,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
