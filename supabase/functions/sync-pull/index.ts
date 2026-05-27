import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

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

    // ── 2. Process sync-pull request ───────────────────────────────────────
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

    // ── 3. Fetch teacher metadata for client-side reconciliation ──────────────
    // Return the set of all active teacher IDs so the client can delete local
    // records for teachers that were hard-deleted from the server (Issue 1).
    // Also return teachers with force_password_reset=true that may have been
    // missed by the incremental pull (Issue 3).
    let activeTeacherIds: string[] = [];
    let pendingTeachers: Record<string, unknown>[] = [];

    try {
      // All teacher IDs that are not soft-deleted
      const { data: teacherData } = await supabase
        .from("teachers")
        .select("id")
        .or("is_deleted.is.null,is_deleted.eq.false");

      if (teacherData && teacherData.length > 0) {
        activeTeacherIds = teacherData.map((t: Record<string, unknown>) => t.id as string);
      }

      // All teachers with force_password_reset = true (pending sign-in)
      const { data: pendingData } = await supabase
        .from("teachers")
        .select("*")
        .eq("force_password_reset", true);

      if (pendingData && pendingData.length > 0) {
        pendingTeachers = pendingData;
      }
    } catch (e) {
      console.warn("sync-pull: error fetching teacher metadata:", e);
    }

    return new Response(
      JSON.stringify({
        changes,
        next_cursor: nextCursor,
        active_teacher_ids: activeTeacherIds,
        pending_teachers: pendingTeachers,
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
