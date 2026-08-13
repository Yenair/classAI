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

    let jwtClaims: Record<string, unknown>;
    try {
      jwtClaims = await validateTokenVersion(
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

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── 1b. Check email_verified ───────────────────────────────────────────
    const { data: teacherRec, error: teacherRecError } = await supabase
      .from("teachers")
      .select("id, email_verified")
      .eq("id", jwtClaims.teacher_id as string)
      .maybeSingle();

    if (teacherRecError || !teacherRec) {
      return new Response(
        JSON.stringify({ error: "Teacher record not found", code: "teacher_not_found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!teacherRec.email_verified) {
      return new Response(
        JSON.stringify({
          error: "Email not verified. Please verify your email before syncing.",
          code: "email_not_verified",
        }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 2. Process sync-pull request ───────────────────────────────────────
    const { lastSyncTimestamp, tables, school_id, catalogs } = await req.json();

    if (!Array.isArray(tables) || tables.length === 0) {
      return new Response(
        JSON.stringify({ error: "Request body must include a non-empty `tables` array." }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const PAGE_SIZE = 50;
    const changes: { table: string; row: Record<string, unknown> }[] = [];

    for (const table of tables) {
      let query = supabase
        .from(table)
        .select("*")
        .order("updated_at", { ascending: true })
        .limit(PAGE_SIZE);

      // ── School-id scoping ──────────────────────────────────────────
      // Every syncable table that has a school_id FK must be scoped to
      // the requesting school so one school cannot see another's data.
      //
      // Tables below have been verified (via migration analysis and/or
      // sync-push resolveForeignKeys) to possess a school_id (uuid FK)
      // column on the Supabase side.
      if (school_id) {
        const scopedTables = new Set([
          "teachers",
          "lessons",
          "exams",
          "subjects",
          "scheme_of_work",
          "vault_items",
          "progress_logs",
          "payment_events",
          "schools",
        ]);
        if (scopedTables.has(table)) {
          // For 'schools', the row's PK (id) IS the requesting school_id
          const column = table === "schools" ? "id" : "school_id";
          query = query.eq(column, school_id);
        }
      }

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

      // ── 2b. Update the requesting teacher's last_sync_at ────────────────
      // Track the last successful pull cycle per-teacher for the admin
      // dashboard's sync status indicators.  This is a best-effort write:
      // it MUST NOT abort the pull response on failure.
      try {
        const teacherId = jwtClaims.teacher_id as string;
        if (teacherId) {
          await supabase
            .from('teachers')
            .update({ last_sync_at: new Date().toISOString() })
            .eq('id', teacherId);
        }
      } catch (e) {
        console.warn(
          `[sync-pull] failed to update last_sync_at for teacher ` +
          `${jwtClaims.teacher_id}: ${e instanceof Error ? e.message : e}`
        );
        // Non-fatal — the pull response must succeed regardless
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

    // ── 2c. Full subject catalog for client-side subject self-heal ────────────
    // Return the school's ENTIRE subjects list (independent of the
    // incremental cursor) so the client can reconcile local subjects that
    // never reached the server (e.g. a stale server_id assigned by the old
    // cross-table local_id collision) and permanently self-heal them. The
    // catalog is small (one row per subject) and is returned on every page.
    let subjectCatalog: Record<string, unknown>[] = [];
    try {
      if (school_id) {
        const { data: subjectData, error: subjectError } = await supabase
          .from("subjects")
          .select("id, subject_name, school_id, is_active, deleted_at")
          .eq("school_id", school_id);
        if (subjectError) {
          console.warn(
            "[sync-pull] error fetching subject catalog:", subjectError.message
          );
        } else if (subjectData && subjectData.length > 0) {
          subjectCatalog = subjectData;
        }
      }
    } catch (e) {
      console.warn(
        "[sync-pull] error fetching subject catalog:",
        e instanceof Error ? e.message : e
      );
    }

    // ── 2d. Identity catalogs for full-table reconciliation ───────────────────
    // Minimal identity columns per table so the client can reconcile local rows
    // against the server (match by server id, then by natural key) — the same
    // pattern as subject_catalog above. Returned on every page; the client
    // captures the last page's value. Volume is tiny for small schools.
    const CATALOG_PROJECTIONS: Record<string, string> = {
      lessons:
        "id, school_id, teacher_id, subject_id, subject, class_level, week, week_number, term, topic, is_deleted, deleted_at, updated_at",
      exams:
        "id, school_id, teacher_id, subject_id, subject, class_level, week_number, term, topic, is_deleted, deleted_at, updated_at",
      scheme_of_work:
        "id, school_id, teacher_id, subject_id, term, week_number, topic, class_level, status, is_deleted, deleted_at, updated_at",
      progress_logs:
        "id, school_id, teacher_id, lesson_id, exam_id, event_type, event_date, notes, is_deleted, deleted_at, updated_at",
    };
    const catalogsResponse: Record<string, Record<string, unknown>[]> = {};
    if (Array.isArray(catalogs)) {
      for (const table of catalogs) {
        const projection = CATALOG_PROJECTIONS[table as string];
        if (!projection) continue;
        try {
          let query = supabase.from(table as string).select(projection);
          if (school_id) {
            query = query.eq("school_id", school_id);
          }
          const { data, error } = await query;
          if (error) {
            console.warn(
              `[sync-pull] error fetching catalog for "${table}": ${error.message}`
            );
            continue;
          }
          catalogsResponse[table as string] =
            (data ?? []) as Record<string, unknown>[];
        } catch (e) {
          console.warn(
            `[sync-pull] error fetching catalog for "${table}":`,
            e instanceof Error ? e.message : e
          );
        }
      }
    }

    // ── 3. Fetch teacher metadata for client-side reconciliation ──────────────
    // Return the set of all active teacher IDs so the client can delete local
    // records for teachers that were hard-deleted from the server (Issue 1).
    // Also return teachers with force_password_reset=true that may have been
    // missed by the incremental pull (Issue 3).
    let activeTeacherIds: string[] = [];
    let pendingTeachers: Record<string, unknown>[] = [];

    try {
      // Scope all teacher metadata queries to the admin's school
      if (!school_id) {
        console.warn("sync-pull: no school_id provided, skipping teacher metadata queries");
      } else {
        // All active teacher IDs for this school (teachers table has no is_deleted column)
        const { data: teacherData, error: teacherError } = await supabase
          .from("teachers")
          .select("id")
          .eq("school_id", school_id);

        if (teacherError) {
          console.error("[sync-pull] error fetching active teacher IDs:", teacherError.message);
          return new Response(
            JSON.stringify({
              error: "Failed to fetch active teacher IDs",
              changes,
              next_cursor: nextCursor,
              active_teacher_ids: [],
              pending_teachers: [],
            }),
            { headers: { "Content-Type": "application/json" } }
          );
        }

        if (teacherData && teacherData.length > 0) {
          activeTeacherIds = teacherData.map((t: Record<string, unknown>) => t.id as string);
        }

        // All teachers with force_password_reset = true (pending sign-in, scoped to school)
        const { data: pendingData } = await supabase
          .from("teachers")
          .select("*")
          .eq("school_id", school_id)
          .eq("force_password_reset", true);

        if (pendingData && pendingData.length > 0) {
          pendingTeachers = pendingData;
        }
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
        subject_catalog: subjectCatalog,
        catalogs: catalogsResponse,
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
