import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

// Key compression map (mirrors PayloadCompressor._keyMap on the Dart side)
// Also includes camelCase→snake_case fallbacks for keys the Dart side may
// send uncompressed (e.g. 'classLevel', 'bloomsVerbs').
//
// IMPORTANT: The lessons/exams tables store school_server_id and
// teacher_server_id as plain TEXT columns (not foreign keys to the
// schools/teachers tables).  The `subject` text name is resolved to
// a subject_id UUID via resolveForeignKeys().
const KEY_MAP: Record<string, string> = {
  lid: "local_id",
  sid: "server_id",
  slid: "school_local_id",
  ssid: "school_server_id",    // school_server_id — TEXT column on lessons/exams (not a FK to schools.id)
  tlid: "teacher_local_id",
  tsid: "teacher_server_id",   // teacher_server_id — TEXT column on lessons/exams (not a FK to teachers.id)
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
  // camelCase→snake_case fallbacks for keys the Dart side may send uncompressed
  classLevel: "class_level",
  bloomsVerbs: "blooms_verbs",
  // short code for blooms_verbs
  bv: "blooms_verbs",
  // Full-key fallbacks — these keys are the actual snake_case column names,
  // so they map to themselves (no-op, but defensively listed).
  school_server_id: "school_server_id",
  teacher_server_id: "teacher_server_id",
  scheme_of_work_id: "scheme_of_work_id",
  week_number: "week_number",
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

/**
 * After decompression, resolve any foreign-key names to their UUIDs.
 *
 * NOTE: The lessons & exams tables store `subject` as a TEXT column, NOT
 * as a subject_id UUID FK.  The `subjects` table is used only for AI
 * generation context on the client — the server-side lessons/exams table
 * simply stores the subject name string.  Therefore this function is a
 * no-op for lessons/exams; the subject TEXT value passes through as-is.
 *
 * Mutates `rowData` in place.
 */
async function resolveForeignKeys(
  _supabase: ReturnType<typeof createClient>,
  _table: string,
  _rowData: Record<string, unknown>,
): Promise<void> {
  // No FK columns need resolution on any table currently synced via
  // sync-push.  The `subject` column on lessons/exams is TEXT, not a
  // foreign key to `subjects.id`.
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

    // Process changes sequentially and push one result per change immediately.
    // The results array is built in the same order as the changes array so
    // the client can always find its entries by local_id (which the client
    // must include in rowData as "local_id" or "lid").
    for (const [idx, change] of changes.entries()) {
      const { table, operation, rowData } = change;

      if (!table || !operation || !rowData) {
        console.warn(`sync-push: skipping invalid change entry at index ${idx}`, change);
        results.push({ local_id: 0, server_id: null, status: "error", retryable: true });
        continue;
      }

      // Decompress rowData if it has short keys
      const fullRowData = decompressRow(rowData as Record<string, unknown>);

      // Extract local_id early so we can echo it back even on failure.
      const localId = (fullRowData["local_id"] as number | string | undefined) ?? 0;

      const op = (operation as string).toUpperCase();

      try {
        if (op === "INSERT") {
          // Remove local-only fields; let server generate UUIDs
          const { local_id: _lid, localId: _lid2, ...insertData } = fullRowData;
          await resolveForeignKeys(supabase, table, insertData);
          const { data: insertData_, error } = await supabase
            .from(table)
            .insert(insertData)
            .select("id");
          if (error) {
            console.warn(`sync-push: INSERT error on "${table}" (local_id=${localId}): ${error.message}`);
            results.push({ local_id: localId, server_id: null, status: "error", retryable: true });
            continue;
          }
          const generatedId = insertData_?.[0]?.id as string | undefined;
          results.push({
            local_id: localId,
            server_id: generatedId ?? null,
            status: "created",
            retryable: false,
          });
          processed++;
        } else if (op === "UPDATE") {
          // For UPDATES the client must include server_id in rowData
          const serverId = getValue(fullRowData, "server_id", "serverId", "id");
          if (!serverId) {
            console.warn(`sync-push: UPDATE on "${table}" missing server_id (local_id=${localId})`);
            results.push({ local_id: localId, server_id: null, status: "error", retryable: true });
            continue;
          }
          const { local_id: _lid, localId: _lid2, server_id: _sid, serverId: _sid2, id: _id, school_server_id: _ssid, teacher_server_id: _tsid, ...updateData } = fullRowData;
          await resolveForeignKeys(supabase, table, updateData);
          const { error } = await supabase
            .from(table)
            .update(updateData)
            .eq("id", serverId);
          if (error) {
            console.warn(`sync-push: UPDATE error on "${table}" (local_id=${localId}): ${error.message}`);
            results.push({ local_id: localId, server_id: serverId as string, status: "error", retryable: true });
            continue;
          }
          results.push({
            local_id: localId,
            server_id: serverId as string,
            status: "updated",
            retryable: false,
          });
          processed++;
        } else if (op === "DELETE") {
          const serverId = getValue(fullRowData, "server_id", "serverId", "id");
          if (!serverId) {
            console.warn(`sync-push: DELETE on "${table}" missing server_id (local_id=${localId})`);
            results.push({ local_id: localId, server_id: null, status: "error", retryable: true });
            continue;
          }
          const { error } = await supabase
            .from(table)
            .update({ is_deleted: true })
            .eq("id", serverId);
          if (error) {
            console.warn(`sync-push: DELETE error on "${table}" (local_id=${localId}): ${error.message}`);
            results.push({ local_id: localId, server_id: serverId as string, status: "error", retryable: true });
            continue;
          }
          results.push({
            local_id: localId,
            server_id: serverId as string,
            status: "deleted",
            retryable: false,
          });
          processed++;
        } else if (op === "SPEND_CREDITS") {
          results.push({
            local_id: localId,
            server_id: null,
            status: "skipped",
            retryable: false,
          });
          continue;
        } else {
          console.warn(`sync-push: unknown operation "${operation}" on "${table}"`);
          results.push({ local_id: localId, server_id: null, status: "error", retryable: false });
          continue;
        }
      } catch (innerErr) {
        console.warn(`sync-push: exception processing ${operation} on ${table} (local_id=${localId}):`, innerErr);
        results.push({ local_id: localId, server_id: null, status: "error", retryable: true });
      }
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
