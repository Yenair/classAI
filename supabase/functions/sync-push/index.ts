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
  // scheme_of_work fields
  admin_edited_topic: "admin_edited_topic",
  admin_comment: "admin_comment",
  class_level: "class_level",
  // vault_items fields
  subject_id: "subject_id",
  author_name: "author_name",
  credit_cost: "credit_cost",
  needs_approval: "needs_approval",
  thumbnail_url: "thumbnail_url",
  // payment_events fields
  transaction_reference: "transaction_reference",
  confirmed_by_webhook: "confirmed_by_webhook",
  // subjects
  subject_name: "subject_name",
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
 * Normalize a subject name for case/whitespace-insensitive matching:
 * trims, collapses internal whitespace, lowercases.
 */
function normalizeName(value: string): string {
  return value.trim().replace(/\s+/g, " ").toLowerCase();
}

/**
 * Normalize a class level for case/whitespace-insensitive matching:
 * same as normalizeName, plus removes ALL spaces so "JSS 1" === "JSS1".
 * null/undefined (missing class) normalize to "".
 */
function normalizeClass(value: string | null | undefined): string {
  if (value == null) return "";
  return value.trim().replace(/\s+/g, "").toLowerCase();
}

/**
 * Resolve a subject's server UUID from its text name using NORMALIZED
 * (case/whitespace-insensitive) matching.  All subjects for the school are
 * fetched once and matched in memory, so "English Studies" matches
 * "english  studies" and "JSS 1" matches "JSS1".
 *
 * Resolution order:
 *   1. row with the same normalized name AND normalized class
 *   2. row with the same normalized name and an empty class level
 *      (client-created subjects have no class — the subjects handler below
 *      inserts class_level = '')
 *   3. any row with the same normalized name
 *
 * Returns the subject's server UUID or null when no row matches.
 */
async function lookupSubjectId(
  supabase: ReturnType<typeof createClient>,
  subjectName: string,
  schoolId: string | undefined,
  classLevel: string | null | undefined,
): Promise<string | null> {
  let query = supabase
    .from("subjects")
    .select("id, subject_name, class_level")
    .limit(1000);
  if (schoolId) {
    query = query.eq("school_id", schoolId);
  }
  const { data: subjects } = await query;
  const rows = (subjects ?? []) as Array<{
    id: string;
    subject_name: string;
    class_level: string | null;
  }>;

  const nName = normalizeName(subjectName);
  const nClass = normalizeClass(classLevel);

  // 1. Same normalized name AND normalized class.
  const byNameAndClass = rows.find(
    (s) =>
      normalizeName(s.subject_name) === nName &&
      normalizeClass(s.class_level) === nClass
  );
  if (byNameAndClass) return byNameAndClass.id;

  // 2. Same normalized name and an empty class (client-created subject).
  const byNameEmptyClass = rows.find(
    (s) =>
      normalizeName(s.subject_name) === nName &&
      normalizeClass(s.class_level) === ""
  );
  if (byNameEmptyClass) return byNameEmptyClass.id;

  // 3. Any row with the same normalized name.
  const byNameAny = rows.find((s) => normalizeName(s.subject_name) === nName);
  return byNameAny?.id ?? null;
}

/**
 * Check-before-insert guard (Fix 5): before a FIRST-TIME INSERT (no
 * server_id), look up an existing ACTIVE row by the table's natural key. If
 * one exists, the INSERT is idempotently converted to an UPDATE on that row
 * (returning its id) instead of creating a duplicate.
 *
 * This closes the duplicate window for re-pushed INSERTs — reconciliation
 * re-queues and network retries of a committed-but-lost-response INSERT — for
 * scheme_of_work, lessons, exams, and subjects. Keys mirror the app's own
 * identity rules and the partial unique indexes created in the
 * 20260813 natural-key migration.
 */
async function findExistingByNaturalKey(
  supabase: ReturnType<typeof createClient>,
  table: string,
  rowData: Record<string, unknown>
): Promise<string | null> {
  if (table === "scheme_of_work") {
    const schoolId = rowData["school_id"];
    const subjectId = rowData["subject_id"];
    const term = rowData["term"];
    const weekNumber = rowData["week_number"];
    if (!schoolId || !subjectId || term === undefined || weekNumber === undefined) {
      return null;
    }
    const { data } = await supabase
      .from("scheme_of_work")
      .select("id")
      .eq("school_id", schoolId)
      .eq("subject_id", subjectId)
      .eq("term", String(term))
      .eq("week_number", Number(weekNumber))
      .eq("is_deleted", false)
      .limit(1);
    return data && data.length > 0 ? (data[0].id as string) : null;
  }
  if (table === "lessons") {
    const schoolId = rowData["school_id"];
    const teacherId = rowData["teacher_id"];
    const subjectId = rowData["subject_id"];
    const classLevel = rowData["class_level"] ?? "";
    const week = rowData["week"] ?? rowData["week_number"];
    const term = rowData["term"];
    if (!schoolId || !teacherId || !subjectId || week === undefined) {
      return null;
    }
    // Mirror COALESCE(term,'') from the unique index: NULL and '' are the same key.
    // The `.or()` filter is unreliable for empty-string matching, so run two
    // separate queries when term is null/undefined/empty and return the first hit.
    const baseFilter = (
      q: ReturnType<typeof supabase.from>
    ) =>
      q
        .select("id")
        .eq("school_id", schoolId)
        .eq("teacher_id", teacherId)
        .eq("subject_id", subjectId)
        .eq("class_level", String(classLevel))
        .eq("week", Number(week))
        .eq("is_deleted", false);
    if (term === undefined || term === null || term === "") {
      const { data: nullTerm } = await baseFilter(
        supabase.from("lessons")
      )
        .is("term", null)
        .limit(1);
      if (nullTerm && nullTerm.length > 0) return nullTerm[0].id as string;
      const { data: emptyTerm } = await baseFilter(
        supabase.from("lessons")
      )
        .eq("term", "")
        .limit(1);
      return emptyTerm && emptyTerm.length > 0
        ? (emptyTerm[0].id as string)
        : null;
    }
    const { data } = await baseFilter(
      supabase.from("lessons")
    )
      .eq("term", String(term))
      .limit(1);
    return data && data.length > 0 ? (data[0].id as string) : null;
  }
  if (table === "exams") {
    const schoolId = rowData["school_id"];
    const teacherId = rowData["teacher_id"];
    const subjectId = rowData["subject_id"];
    const classLevel = rowData["class_level"] ?? "";
    const weekNumber = rowData["week_number"];
    const term = rowData["term"];
    const topic = rowData["topic"] ?? "";
    if (!schoolId || !teacherId || !subjectId || weekNumber === undefined) {
      return null;
    }
    const baseFilterExams = (
      q: ReturnType<typeof supabase.from>
    ) =>
      q
        .select("id")
        .eq("school_id", schoolId)
        .eq("teacher_id", teacherId)
        .eq("subject_id", subjectId)
        .eq("class_level", String(classLevel))
        .eq("week_number", Number(weekNumber))
        .eq("topic", String(topic))
        .eq("is_deleted", false);
    if (term === undefined || term === null || term === "") {
      const { data: nullTerm } = await baseFilterExams(
        supabase.from("exams")
      )
        .is("term", null)
        .limit(1);
      if (nullTerm && nullTerm.length > 0) return nullTerm[0].id as string;
      const { data: emptyTerm } = await baseFilterExams(
        supabase.from("exams")
      )
        .eq("term", "")
        .limit(1);
      return emptyTerm && emptyTerm.length > 0
        ? (emptyTerm[0].id as string)
        : null;
    }
    const { data } = await baseFilterExams(
      supabase.from("exams")
    )
      .eq("term", String(term))
      .limit(1);
    return data && data.length > 0 ? (data[0].id as string) : null;
  }
  if (table === "subjects") {
    const name = (rowData["subject_name"] ?? rowData["name"]) as string | undefined;
    const schoolId = rowData["school_id"] as string | undefined;
    const classLevel = rowData["class_level"] as string | undefined;
    if (!name || !schoolId) return null;
    // Same normalized name+class → empty-class → any-name chain as
    // lookupSubjectId(), so a retried INSERT lands on the row the app would
    // have resolved anyway.
    return lookupSubjectId(supabase, name, schoolId, classLevel);
  }
  return null;
}

/**
 * Strips local-only fields from a resolved INSERT payload and updates the
 * given server row, pushing a "updated" result. Returns true on success so
 * the caller can count it as processed. Used by the check-before-insert path
 * (natural-key match before insert, and the duplicate-key race backstop).
 */
async function updateExistingRowAndReport(
  supabase: ReturnType<typeof createClient>,
  results: Record<string, unknown>[],
  table: string,
  localId: number | string,
  serverId: string,
  insertData: Record<string, unknown>,
  reason: string
): Promise<boolean> {
  const {
    local_id: _l1,
    localId: _l2,
    server_id: _s1,
    serverId: _s2,
    id: _id,
    school_server_id: _ss,
    teacher_server_id: _ts,
    ...updateData
  } = insertData;
  if (updateData["updated_at"] === undefined) {
    updateData["updated_at"] = new Date().toISOString();
  }
  const { error } = await supabase
    .from(table)
    .update(updateData)
    .eq("id", serverId);
  if (error) {
    console.warn(
      `sync-push: check-before-insert UPDATE error on "${table}" ` +
        `(local_id=${localId}): ${error.message}`
    );
    results.push({
      local_id: localId,
      server_id: serverId,
      status: "error",
      retryable: true,
      error: error.message,
    });
    return false;
  }
  console.log(
    `[SYNC-PUSH-DIAG] check-before-insert: ${reason} — converted INSERT to ` +
      `UPDATE on id=${serverId} (local_id=${localId}, table=${table})`
  );
  results.push({
    local_id: localId,
    server_id: serverId,
    status: "updated",
    retryable: false,
  });
  return true;
}

/** PostgREST duplicate-key signal (unique index violation). */
function isDuplicateKeyError(error: { message?: string; code?: string }): boolean {
  return (
    error?.code === "23505" ||
    (typeof error?.message === "string" &&
      error.message.includes("duplicate key value violates unique constraint"))
  );
}

/**
 * Default values for columns the client's INSERT payload may omit.
 * The Supabase lessons/exams tables have NOT NULL columns that are not
 * sent directly by the client — they must be derived or defaulted.
 *
 * NOTE: school_id, teacher_id, subject_id are resolved from text
 * references by resolveForeignKeys().
 */
const LESSON_DEFAULTS: Record<string, unknown> = {
  topic: "",
  difficulty: "medium",
  blooms_verbs: "",
  title: "",
  credits_spent: 0,
  objectives: "",
  vocabulary: "",
  materials: "",
  presentation: "",
  assessment: "",
  homework: "",
};

const EXAM_DEFAULTS: Record<string, unknown> = {
  difficulty: "medium",
  title: "",
  credits_spent: 0,
  questions: "",
  theory_questions: "",
  marking_scheme: "",
};

const SCHEME_OF_WORK_DEFAULTS: Record<string, unknown> = {
  status: "draft",
  objectives: "",
  topic: "",
  is_deleted: false,
  term: "first",
};

/**
 * Push a results entry for a resolveForeignKeys() skip reason.
 *
 * Reasons prefixed with "RETRYABLE:" become status:"error" with
 * retryable:true so the client keeps the entry pending and pushes it again
 * on the next cycle (used when a foreign key may still be created later in
 * the same batch, e.g. a brand-new subject whose INSERT has not been
 * processed yet). Every other reason becomes a terminal status:"skipped"
 * entry so the client removes it from the queue instead of retrying forever.
 */
function pushSkipResult(
  results: Record<string, unknown>[],
  localId: number | string,
  serverId: string | null,
  table: string,
  op: string,
  skipReason: string
): void {
  const retryable = skipReason.startsWith("RETRYABLE:");
  const reason = retryable ? skipReason.slice("RETRYABLE:".length).trim() : skipReason;
  console.warn(`sync-push: SKIP ${op} on "${table}" (local_id=${localId}): ${reason}`);
  results.push({
    local_id: localId,
    server_id: serverId,
    status: retryable ? "error" : "skipped",
    retryable,
    error: reason,
  });
}

/**
 * Apply defaults and resolve text-based references to UUID foreign keys.
 *
 * KEY INSIGHT about the data model:
 * - The schools and teachers tables use `id` (UUID) as their PK.
 *   There is NO `server_id` column on those Supabase tables — the
 *   schools.id UUID IS the server_id used on the Dart side.
 * - The client sends `school_server_id` / `teacher_server_id` in the
 *   lesson payload.  These ARE the UUIDs from schools.id / teachers.id.
 *
 * For `lessons` and `exams` tables:
 *   school_server_id (TEXT, UUID) → school_id (uuid FK)
 *   teacher_server_id (TEXT, UUID) → teacher_id (uuid FK)
 *   subject (TEXT name) → subject_id (uuid FK, looked up from subjects)
 *
 * For `progress_logs` table:
 *   school_id (TEXT UUID from client) → school_id (uuid FK on server)
 *   teacher_id (TEXT UUID from client) → teacher_id (uuid FK on server)
 *   lesson_id (integer local Drift ID) → lesson_id (uuid FK, looked up)
 */
async function resolveForeignKeys(
  supabase: ReturnType<typeof createClient>,
  table: string,
  rowData: Record<string, unknown>,
  jwtClaims: Record<string, unknown>,
): Promise<string | null> {
  if (table === "lessons" || table === "exams") {
    // ── 1. School: Override from JWT — never trust client-supplied values ─
    const jwtSchoolId = jwtClaims["school_id"] as string | undefined;
    if (!jwtSchoolId) {
      console.warn(
        `resolveForeignKeys: jwtClaims.school_id is missing/falsy for ${table} — skipping entry`
      );
      return `Foreign key could not be resolved for ${table}: jwtClaims.school_id is missing`;
    }
    rowData["school_id"] = jwtSchoolId;
    rowData["school_server_id"] = jwtSchoolId;

    // ── 2. Teacher: teacher_server_id IS teachers.id (UUID) ────────────
    if (rowData["teacher_server_id"] && !rowData["teacher_id"]) {
      rowData["teacher_id"] = rowData["teacher_server_id"];
    }

    // ── 3. Subject text name → subject_id UUID lookup ────────────────
    // The subjects table uses `subject_name`, scoped by school_id and
    // class_level.  Matching is NORMALIZED (case/whitespace-insensitive)
    // because the client sends labels that may differ in case or spacing
    // from the server rows ("english studies" vs "English Studies",
    // "JSS1" vs "JSS 1").  See lookupSubjectId() for the fallback chain.
    if (rowData["subject"] && !rowData["subject_id"]) {
      const subjectName = rowData["subject"] as string;
      const schoolId = rowData["school_id"] as string | undefined;
      const classLevel = rowData["class_level"] as string | undefined;

      const subjectId = await lookupSubjectId(
        supabase,
        subjectName,
        schoolId,
        classLevel
      );
      if (subjectId) {
        rowData["subject_id"] = subjectId;
      } else {
        console.warn(
          `resolveForeignKeys: no subject found for name="${subjectName}" ` +
          `school="${schoolId}" class="${classLevel}" — skipping entry`
        );
        // Cannot resolve FK — signal caller to skip this entry.
        // The caller will produce a "skipped" result with retryable: false
        // so the sync_queue entry is not retried pointlessly.
        delete rowData["subject"];
        return `Foreign key could not be resolved for ${table}: no subject found for name="${subjectName}", school="${schoolId}", class="${classLevel}"`;
      }

      // Remove the text `subject` field since the server uses `subject_id`
      delete rowData["subject"];
    }

    // ── 4. Apply defaults for missing NOT NULL columns ─────────────
    const defaults = table === "lessons" ? LESSON_DEFAULTS : EXAM_DEFAULTS;
    for (const [col, defaultVal] of Object.entries(defaults)) {
      if (rowData[col] === undefined || rowData[col] === null) {
        rowData[col] = defaultVal;
      }
    }

    // ── 4a. Skip if week_number is missing (not sent by client) ────
    // week_number is planned to matter for future features (course/lesson
    // ordering in upcoming app updates). A silent fallback that looks like
    // a real value (e.g. "Week 0") would be actively misleading later.
    // Treat this the same as the subject-not-found skip pattern above.
    if (rowData["week_number"] === undefined || rowData["week_number"] === null) {
      console.warn(
        `resolveForeignKeys: week_number is missing for ${table} — skipping entry`
      );
      return `Foreign key could not be resolved for ${table}: week_number is missing from payload`;
    }

    // ── 5. Derive `title` from `topic` if not already set ──────────
    if (!rowData["title"] || rowData["title"] === "") {
      rowData["title"] = rowData["topic"] ?? "";
    }

    // ── 6. Try to extract sub-fields from `content` JSON if present ─
    if (table === "lessons" && rowData["content"]) {
      const contentRaw = rowData["content"] as string;
      try {
        const parsed = JSON.parse(contentRaw);
        if (typeof parsed === "object" && parsed !== null) {
          const subFields = ["objectives", "vocabulary", "materials", "presentation", "assessment", "homework"];
          for (const field of subFields) {
            if (parsed[field] && (!rowData[field] || rowData[field] === "")) {
              rowData[field] = parsed[field];
            }
          }
        }
      } catch {
        // content is encrypted or not valid JSON — leave defaults
      }
    }
  }

  if (table === "progress_logs") {
    // ── 1. School: client sends UUID string → use directly ─────────
    // The client sends _schoolId which is the schools.id UUID.
    if (!rowData["school_id"]) {
      rowData["school_id"] = "00000000-0000-0000-0000-000000000000";
    }

    // ── 2. Teacher: client sends UUID string → use directly ────────
    // The client sends _teacherId which is the teachers.id UUID.
    if (!rowData["teacher_id"]) {
      rowData["teacher_id"] = "00000000-0000-0000-0000-000000000000";
    }

    // ── 3. Lesson: client sends local Drift integer → resolve UUID ─
    // The client sends a local integer ID for the lesson.  We must
    // look up the lesson's server UUID from the Supabase lessons table.
    if (rowData["lesson_id"] !== undefined && rowData["lesson_id"] !== null) {
      const lessonLocalId = rowData["lesson_id"];
      // Try matching as local_id first, then as server_id
      const { data: lesson } = await supabase
        .from("lessons")
        .select("id")
        .eq("local_id", lessonLocalId)
        .maybeSingle();

      if (lesson?.id) {
        rowData["lesson_id"] = lesson.id;
      } else {
        // Try matching by server_id (text UUID)
        const { data: lessonBySid } = await supabase
          .from("lessons")
          .select("id")
          .eq("server_id", lessonLocalId)
          .maybeSingle();
        if (lessonBySid?.id) {
          rowData["lesson_id"] = lessonBySid.id;
        } else {
          console.warn(`resolveForeignKeys: no lesson found for id="${lessonLocalId}"`);
          rowData["lesson_id"] = null;
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // scheme_of_work handler
  // ═══════════════════════════════════════════════════════════════
  if (table === "scheme_of_work") {
    // ── 1. School: Override from JWT — never trust client-supplied values ─
    const jwtSchoolId = jwtClaims["school_id"] as string | undefined;
    if (!jwtSchoolId) {
      console.warn(
        `resolveForeignKeys: jwtClaims.school_id is missing/falsy for scheme_of_work — skipping entry`
      );
      return `Foreign key could not be resolved for scheme_of_work: jwtClaims.school_id is missing`;
    }
    rowData["school_id"] = jwtSchoolId;
    rowData["school_server_id"] = jwtSchoolId;

    // ── 2. Teacher: Override from JWT — same pattern as school_id ─────
    const jwtTeacherId = jwtClaims["teacher_id"] as string | undefined;
    if (!jwtTeacherId) {
      console.warn(
        `resolveForeignKeys: jwtClaims.teacher_id is missing/falsy for scheme_of_work — skipping entry`
      );
      return `Foreign key could not be resolved for scheme_of_work: jwtClaims.teacher_id is missing`;
    }
    rowData["teacher_id"] = jwtTeacherId;
    rowData["teacher_server_id"] = jwtTeacherId;

    // ── 3. Subject_id: validate UUID format, else resolve by name ────
    // A brand-new subject (e.g. "English Studies" created by Bulk Generate)
    // has no server UUID yet, so the client sends subject_id: null plus
    // subject_name. When subject_id is missing or not a valid UUID, resolve
    // it by name via lookupSubjectId(). If the subject row has not been
    // created yet, return a RETRYABLE error so the entry is pushed again
    // after the subject INSERT is processed (the sync queue is topologically
    // sorted: subjects are pushed before scheme_of_work).
    const subjectName = rowData["subject_name"] as string | undefined;
    // subject_name is a client-side hint only — never a column on scheme_of_work.
    delete rowData["subject_name"];

    const rawSubjectId = rowData["subject_id"];
    const hasValidSubjectId =
      typeof rawSubjectId === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(rawSubjectId);
    if (!hasValidSubjectId) {
      delete rowData["subject_id"];
      if (subjectName) {
        const schoolId = rowData["school_id"] as string | undefined;
        const classLevel = rowData["class_level"] as string | undefined;
        const subjectId = await lookupSubjectId(
          supabase,
          subjectName,
          schoolId,
          classLevel
        );
        if (subjectId) {
          rowData["subject_id"] = subjectId;
        } else {
          console.warn(
            `resolveForeignKeys: scheme_of_work subject "${subjectName}" not found ` +
            `(school="${schoolId}" class="${classLevel}") — retrying after the subject INSERT is processed`
          );
          return `RETRYABLE: Foreign key could not be resolved for scheme_of_work: subject "${subjectName}" not found yet (subject INSERT may still be pending)`;
        }
      }
    }

    // ── 4. Admin-gated fields: only admins may set status to
    //    'approved'/'rejected', or write admin_edited_topic/admin_comment ──
    const isAdmin = jwtClaims.is_admin === true;
    const attemptedStatus = rowData["status"] as string | undefined;
    const adminOnlyFields = ["admin_edited_topic", "admin_comment"];

    if (!isAdmin) {
      // Check for admin-only status values
      if (attemptedStatus === "approved" || attemptedStatus === "rejected") {
        console.warn(
          `resolveForeignKeys: non-admin teacher ${jwtClaims.teacher_id} ` +
          `attempted to set status="${attemptedStatus}" on scheme_of_work — skipping`
        );
        return `Admin access required: only admins may set scheme_of_work status to "${attemptedStatus}"`;
      }
      // Check for admin-only field writes
      for (const field of adminOnlyFields) {
        if (rowData[field] !== undefined && rowData[field] !== null) {
          console.warn(
            `resolveForeignKeys: non-admin teacher ${jwtClaims.teacher_id} ` +
            `attempted to write "${field}" on scheme_of_work — skipping`
          );
          return `Admin access required: only admins may write "${field}" on scheme_of_work`;
        }
      }
    }

    // ── 5. Apply defaults ────────────────────────────────────────────
    for (const [col, defaultVal] of Object.entries(SCHEME_OF_WORK_DEFAULTS)) {
      if (rowData[col] === undefined || rowData[col] === null) {
        rowData[col] = defaultVal;
      }
    }

    // ── 6. Remove local-only fields ──────────────────────────────────
    delete rowData["teacher_server_id"];
    delete rowData["school_server_id"];
    delete rowData["local_id"];
  }

  // ═══════════════════════════════════════════════════════════════
  // vault_items handler
  // ═══════════════════════════════════════════════════════════════
  if (table === "vault_items") {
    // The Vault feature is currently disabled, and the server-side
    // vault_items table is missing several columns the client payload
    // contains (teacher_id, author_name, curriculum, class_level, ...).
    // Pushing INSERT/UPDATE payloads therefore fails permanently and the
    // sync queue retries them endlessly, cluttering the queue.
    //
    // Safest minimal fix: skip every vault_items INSERT/UPDATE as a
    // non-retryable "skipped" entry (the caller maps a skip reason to
    // status:"skipped", retryable:false, which the client treats as
    // terminal and removes from the queue). Local vault data is retained,
    // and when the feature is re-enabled with an aligned server table this
    // early return can simply be removed to resume pushing.
    //
    // DELETE operations never reach this handler (they are processed by
    // server_id in the main loop) and keep working.
    return "Vault items sync is disabled: the server vault_items table is missing client columns (teacher_id, author_name, curriculum, class_level)";
  }

  // ═══════════════════════════════════════════════════════════════
  // teachers handler
  // ═══════════════════════════════════════════════════════════════
  if (table === "teachers") {
    // school_server_id → school_id (UUID FK)
    if (rowData["school_server_id"] && !rowData["school_id"]) {
      rowData["school_id"] = rowData["school_server_id"];
    }
    delete rowData["school_server_id"];
    delete rowData["server_id"];
    delete rowData["serverId"];
    delete rowData["local_id"];
  }

  // ═══════════════════════════════════════════════════════════════
  // schools handler
  // ═══════════════════════════════════════════════════════════════
  if (table === "schools") {
    delete rowData["local_id"];
  }

  // ═══════════════════════════════════════════════════════════════
  // subjects handler
  // ═══════════════════════════════════════════════════════════════
  if (table === "subjects") {
    // Map name → subject_name for the server column
    if (rowData["name"] && !rowData["subject_name"]) {
      rowData["subject_name"] = rowData["name"];
    }
    delete rowData["name"];
    delete rowData["local_id"];

    // ── Fill NOT NULL columns the client payload omits ──────────────
    // The server subjects table requires school_id, subject_name,
    // curriculum and class_level (all NOT NULL, no defaults).  The client
    // only sends subject_name + school_id (see _resolveOrInsertSubjectId
    // in scheme_of_work_service.dart), so without these defaults the
    // INSERT fails with "null value in column ... violates not-null
    // constraint" and the subject never reaches other devices.
    // curriculum: existing server rows use lowercase "nerdc".
    // class_level: client-created subjects have no class — '' keeps the
    //   row findable by the empty-class fallback in lookupSubjectId().
    if (rowData["curriculum"] === undefined || rowData["curriculum"] === null) {
      rowData["curriculum"] = "nerdc";
    }
    if (rowData["class_level"] === undefined || rowData["class_level"] === null) {
      rowData["class_level"] = "";
    }
    // School must come from the JWT — never trust client-supplied values
    // (same pattern as lessons/exams/scheme_of_work above).
    const jwtSchoolId = jwtClaims["school_id"] as string | undefined;
    if (jwtSchoolId) {
      rowData["school_id"] = jwtSchoolId;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // payment_events handler
  // ═══════════════════════════════════════════════════════════════
  if (table === "payment_events") {
    // Resolve school_server_id → school_id
    if (rowData["school_server_id"] && !rowData["school_id"]) {
      rowData["school_id"] = rowData["school_server_id"];
    }
    delete rowData["school_server_id"];
    delete rowData["local_id"];
  }

  // No skip needed
  return null;
}

// ═══════════════════════════════════════════════════════════════
// Diagram cleanup helpers
// ═══════════════════════════════════════════════════════════════

/**
 * Extract the Storage object path from a Supabase Storage public URL.
 * e.g. "https://<project>.supabase.co/storage/v1/object/public/diagrams/abc.png"
 *      -> "abc.png"
 */
function extractStoragePath(publicUrl: string, bucketName: string): string | null {
  try {
    const marker = `/object/public/${bucketName}/`;
    const idx = publicUrl.indexOf(marker);
    if (idx === -1) return null;
    return publicUrl.substring(idx + marker.length);
  } catch {
    return null;
  }
}

/**
 * Parse diagram URL(s) from a lesson's content JSON and delete them from
 * the diagrams Storage bucket. This runs BEFORE the soft-delete so the
 * lesson's content is still readable.
 *
 * This is intentionally defensive: any parse/format issue is logged and
 * skipped rather than failing the entire sync-push operation.
 */
async function cleanupLessonDiagrams(
  supabase: ReturnType<typeof createClient>,
  lessonServerId: string,
  localId: number | string,
): Promise<void> {
  try {
    // Fetch the lesson content while it's still intact (before soft-delete)
    const { data: lesson, error: fetchError } = await supabase
      .from("lessons")
      .select("content")
      .eq("id", lessonServerId)
      .maybeSingle();

    if (fetchError || !lesson) {
      console.warn(
        `[cleanupLessonDiagrams] Failed to fetch lesson ${lessonServerId} (local_id=${localId}): ${fetchError?.message ?? "not found"}`,
      );
      return;
    }

    const contentRaw = lesson.content as string;
    if (!contentRaw || contentRaw.trim() === "") {
      return; // No content to parse
    }

    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(contentRaw) as Record<string, unknown>;
    } catch {
      // Content may be encrypted or not valid JSON — skip diagram cleanup
      console.log(
        `[cleanupLessonDiagrams] Lesson ${lessonServerId} content is not valid JSON (likely encrypted), skipping diagram cleanup`,
      );
      return;
    }

    const diagrams = parsed["diagrams"];
    if (diagrams === undefined || diagrams === null) {
      return; // No diagrams field
    }

    if (!Array.isArray(diagrams)) {
      console.warn(
        `[cleanupLessonDiagrams] Lesson ${lessonServerId}: "diagrams" field is not an array (type=${typeof diagrams}), skipping`,
      );
      return;
    }

    const BUCKET_NAME = "diagrams";
    const pathsToDelete: string[] = [];

    for (let i = 0; i < diagrams.length; i++) {
      const entry = diagrams[i];
      if (!entry || typeof entry !== "object") {
        console.warn(
          `[cleanupLessonDiagrams] Lesson ${lessonServerId}: diagram entry ${i} is malformed (not an object), skipping`,
        );
        continue;
      }

      const imageUrl = (entry as Record<string, unknown>)["imageUrl"] as string | undefined;
      if (!imageUrl || typeof imageUrl !== "string" || imageUrl.trim() === "") {
        continue; // No URL in this entry
      }

      const path = extractStoragePath(imageUrl, BUCKET_NAME);
      if (!path) {
        console.warn(
          `[cleanupLessonDiagrams] Lesson ${lessonServerId}: could not extract storage path from URL "${imageUrl.substring(0, 80)}...", skipping`,
        );
        continue;
      }

      pathsToDelete.push(path);
    }

    if (pathsToDelete.length === 0) {
      return;
    }

    // Delete all found diagram objects. This is idempotent — if the object
    // was already deleted (e.g. via section 3's client-side call), the
    // Storage remove call simply no-ops on an already-missing object.
    const { error: deleteError } = await supabase
      .storage
      .from(BUCKET_NAME)
      .remove(pathsToDelete);

    if (deleteError) {
      console.warn(
        `[cleanupLessonDiagrams] Failed to delete ${pathsToDelete.length} diagram(s) for lesson ${lessonServerId}: ${deleteError.message}`,
      );
    } else {
      console.log(
        `[cleanupLessonDiagrams] Deleted ${pathsToDelete.length} diagram(s) for lesson ${lessonServerId}`,
      );
    }
  } catch (err) {
    // Never let diagram cleanup fail the sync-push operation
    console.warn(
      `[cleanupLessonDiagrams] Unexpected error cleaning up diagrams for lesson ${lessonServerId} (local_id=${localId}): ${err instanceof Error ? err.message : err}`,
    );
  }
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

    // ── 1b. Check email_verified ───────────────────────────────────────────
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

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

    // ── 2. Process sync-push request ───────────────────────────────────────
    const { changes } = await req.json();

    if (!Array.isArray(changes)) {
      return new Response(
        JSON.stringify({ error: "Request body must include a `changes` array." }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const isAdmin = jwtClaims.is_admin === true;

    // ══════════════════════════════════════════════════════════════════
    // Fix 9a: Explicit allowlist — reject tables not in this set
    // ══════════════════════════════════════════════════════════════════
    // Without this, a (possibly malicious) client could send ANY table
    // name from the `table` field in the change payload, and sync-push
    // would attempt to write to it.  This allowlist closes that door.
    // It includes every table the legitimate Dart client ever enqueues
    // via syncQueueDao.insertEntry() — plus the `credit_spend` sentinel
    // which is handled separately via SPEND_CREDITS (a no-op).
    const SYNCABLE_TABLES = new Set([
      "lessons", "exams", "progress_logs",
      "subjects", "teachers", "schools",
      "scheme_of_work", "vault_items",
      "payment_events",
      "credit_spend",
    ]);

    // ══════════════════════════════════════════════════════════════════
    // Fix 9b: Admin-table guard — only admins may push to these tables
    // ══════════════════════════════════════════════════════════════════
    // These tables contain school-level or system-wide data that no
    // non-admin teacher should ever be able to modify:
    //   teachers       — other teachers' records, role, is_active
    //   schools        — subscription_tier, total_seats, expiry_date,
    //                    activation_code, admin_recovery_email
    //   subjects       — school-wide subject catalogue
    //   payment_events — payment/transaction records
    //   app_config     — system-wide config (pricing, limits, feature flags)
    //   pending_activations — activation codes for onboarding
    //   activation_codes    — payment activation codes with reference
    //   admin_recovery_otps — admin password-recovery OTPs
    //   verification_codes  — email verification OTPs
    //   recovery_codes      — password-reset recovery codes
    const adminTables = new Set([
      "teachers", "schools",
      "payment_events",
      "app_config",
      "pending_activations",
      "activation_codes",
      "admin_recovery_otps",
      "verification_codes",
      "recovery_codes",
    ]);

    // Tables whose Supabase rows have a `server_id` column that must be
    // backfilled after INSERT/UPSERT.  schools and teachers use `id` as
    // their server identity and have no `server_id` column.
    const SERVER_ID_TABLES = new Set([
      "lessons",
      "exams",
      "scheme_of_work",
      "subjects",
    ]);

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

      const op = (operation as string).toUpperCase();

      // ──────────────────────────────────────────────────────────────────
      // IMPORTANT: Decompress + extract local_id BEFORE any guard checks,
      // so that rejected entries still carry the correct local_id back to
      // the client.  Without this, the client receives local_id=0 and
      // cannot match the result to its queue entry — causing it to fall
      // into the "no result returned" path, which only increments the
      // attempt counter and NEVER marks the entry terminal (neither the
      // !retryable path nor the >=5-attempts limit is ever reached).
      // ──────────────────────────────────────────────────────────────────

      // DIAG: Log the raw rowData keys BEFORE decompression
      console.log(`[SYNC-PUSH-DIAG] Entry ${idx}: table=${table}, op=${op}, rawKeys=${Object.keys(rowData as Record<string, unknown>).join(",")}`);

      // Decompress rowData if it has short keys
      const fullRowData = decompressRow(rowData as Record<string, unknown>);

      // DIAG: Log decompressed keys to verify KEY_MAP is working
      console.log(`[SYNC-PUSH-DIAG] Entry ${idx}: decompressedKeys=${Object.keys(fullRowData).join(",")}`);

      // Extract local_id early so we can echo it back even on failure.
      const localId = (fullRowData["local_id"] as number | string | undefined) ?? 0;
      console.log(`[SYNC-PUSH-DIAG] Entry ${idx}: localId=${localId}, server_id=${fullRowData["server_id"] ?? "null"}`);

      // NOTE: localId is extracted above, BEFORE this guard, so the guard
      // below can echo the real local_id back to the client (previously it
      // referenced localId before declaration — a Temporal Dead Zone bug).
      if (table === "subjects" && op === "DELETE" && !isAdmin) {
        console.warn(
          `sync-push: non-admin teacher ${jwtClaims.teacher_id} attempted DELETE on admin-only subjects table`,
        );
        results.push({
          local_id: localId,
          server_id: null,
          status: "error",
          retryable: false,
          error: "Admin access required for this table",
        });
        continue;
      }

      // ══════════════════════════════════════════════════════════════════
      // Fix 9a: Explicit table allowlist
      // ══════════════════════════════════════════════════════════════════
      // Reject any table name that the legitimate client never sends.
      // This prevents a crafted or malicious request from writing to
      // arbitrary database tables even if the adminTables guard would
      // otherwise pass (e.g. a table added in the future that is not
      // flagged admin-level but should never be written from the client).
      if (!SYNCABLE_TABLES.has(table)) {
        console.warn(
          `sync-push: rejected change to unknown/non-syncable table "${table}" (op=${op})`,
        );
        results.push({
          local_id: localId,
          server_id: null,
          status: "error",
          retryable: false,
          error: `Table "${table}" is not syncable via this endpoint`,
        });
        continue;
      }

      // ══════════════════════════════════════════════════════════════════
      // Fix 9b: Service-role authorization guard
      // ══════════════════════════════════════════════════════════════════
      // Only admins may push changes to admin-level tables.
      if (adminTables.has(table) && !isAdmin) {
        console.warn(
          `sync-push: non-admin teacher ${jwtClaims.teacher_id} attempted ${op} on admin table "${table}"`,
        );
        results.push({
          local_id: localId,
          server_id: null,
          status: "error",
          retryable: false,
          error: "Admin access required for this table",
        });
        continue;
      }

      try {
        if (op === "INSERT") {
          // Remove local-only fields; let server generate UUIDs
          const { local_id: _lid, localId: _lid2, ...insertData } = fullRowData;

          // ════════════════════════════════════════════════════════════
          // FIX: Resolve FK text references to UUIDs and apply defaults
          // ════════════════════════════════════════════════════════════
          const skipReason = await resolveForeignKeys(supabase, table, insertData, jwtClaims);
          if (skipReason) {
            pushSkipResult(results, localId, null, table, "INSERT", skipReason);
            continue;
          }

          // ── Permanent test-lesson guard ────────────────────────────────
          // Skip INSERT/UPDATE for the old direct-test lesson that was used
          // during initial development.  DELETE still allowed so cleanup can
          // remove any existing server test row.
          if (table === "lessons") {
            const testTeacherId = "4e569a31-99d1-44a6-8bcc-4efbf0d67a71";
            const tsid = insertData["teacher_server_id"] ?? insertData["teacher_id"];
            const topic = insertData["topic"];
            if (
              tsid === testTeacherId &&
              topic === "direct test topic"
            ) {
              console.warn(
                `sync-push: SKIP INSERT test-lesson (local_id=${localId}): ` +
                  `teacher=${tsid}, topic=${topic}`
              );
              results.push({
                local_id: localId,
                server_id: null,
                status: "skipped",
                retryable: false,
              });
              continue;
            }
          }

          console.log(`[SYNC-PUSH-DIAG] INSERT data after resolveForeignKeys: ${JSON.stringify(insertData)}`);

          // ── UPSERT if payload includes server_id (handles stale INSERT
          //    from a client crash between _updateLocalServerId and
          //    removeQueueEntry) ────────────────────────────────────────
          const insertServerId = getValue(insertData, "server_id", "serverId");
          if (insertServerId) {
            console.log(`[SYNC-PUSH-DIAG] UPSERT detected server_id=${insertServerId} (table=${table}, local_id=${localId})`);
            const { data: upsertData_, error } = await supabase
              .from(table)
              .upsert(insertData, { onConflict: "server_id", ignoreDuplicates: false })
              .select("id");
            if (error) {
              console.warn(`sync-push: UPSERT error on "${table}" (local_id=${localId}): ${error.message}`);
              console.warn(`sync-push: UPSERT data was: ${JSON.stringify(insertData)}`);
              results.push({ local_id: localId, server_id: null, status: "error", retryable: true, error: error.message });
              continue;
            }
            const serverId = upsertData_?.[0]?.id as string | undefined;
            console.log(`[SYNC-PUSH-DIAG] UPSERT result: localId=${localId}, serverId=${serverId ?? "null"}, upsertData_=${JSON.stringify(upsertData_)}`);
            // Backfill server_id if UPSERT created a new row (returned id differs
            // from the supplied server_id).  The server_id column is NOT auto-filled
            // by PostgREST on INSERT/UPSERT — it must be written explicitly.
            if (SERVER_ID_TABLES.has(table) && serverId && insertServerId && serverId !== insertServerId) {
              const { error: backfillErr } = await supabase
                .from(table)
                .update({ server_id: serverId })
                .eq("id", serverId)
                .is("server_id", null);
              if (backfillErr) {
                console.warn(
                  `sync-push: UPSERT server_id backfill warning on "${table}" ` +
                    `(id=${serverId}): ${backfillErr.message}`
                );
              }
            }
            results.push({
              local_id: localId,
              server_id: serverId ?? null,
              status: "updated",
              retryable: false,
            });
            processed++;
          } else {
            // First-time INSERT — no server_id. Fix 5 check-before-insert:
            // if an active row already exists under this table's natural key
            // (a re-pushed INSERT — reconciliation re-queue or a network
            // retry after the server committed but the response was lost),
            // convert to an UPDATE on that row instead of inserting a
            // duplicate. The partial unique indexes are the atomic backstop
            // for the SELECT→INSERT race between two devices.
            console.log(`[SYNC-PUSH-DIAG] INSERT (no server_id) on table=${table}, local_id=${localId}`);
            const existingId = await findExistingByNaturalKey(
              supabase,
              table,
              insertData
            );
            if (existingId) {
              if (await updateExistingRowAndReport(
                supabase,
                results,
                table,
                localId,
                existingId,
                insertData,
                "natural-key match before insert"
              )) {
                processed++;
              }
              continue;
            }
            const { data: insertData_, error } = await supabase
              .from(table)
              .insert(insertData)
              .select("id");
            if (error) {
              if (isDuplicateKeyError(error)) {
                // Race: another push inserted the same natural key between
                // our SELECT and INSERT. Convert to an UPDATE on the winning
                // row so the entry never retries forever (Fix 5 backstop).
                const winnerId = await findExistingByNaturalKey(
                  supabase,
                  table,
                  insertData
                );
                if (winnerId) {
                  if (await updateExistingRowAndReport(
                    supabase,
                    results,
                    table,
                    localId,
                    winnerId,
                    insertData,
                    "duplicate-key race"
                  )) {
                    processed++;
                  }
                  continue;
                }
              }
              console.warn(`sync-push: INSERT error on "${table}" (local_id=${localId}): ${error.message}`);
              console.warn(`sync-push: INSERT data was: ${JSON.stringify(insertData)}`);
              results.push({ local_id: localId, server_id: null, status: "error", retryable: true, error: error.message });
              continue;
            }
            const generatedId = insertData_?.[0]?.id as string | undefined;
            console.log(`[SYNC-PUSH-DIAG] INSERT result: localId=${localId}, generatedId=${generatedId ?? "null"}, insertData_=${JSON.stringify(insertData_)}`);
            // Backfill server_id after first-time INSERT.  The server_id column is
            // NOT auto-filled by PostgREST — it must be written explicitly so the
            // client can match its local row to the server row on subsequent pushes.
            // Only needed for tables that have a server_id column (not schools/teachers).
            if (SERVER_ID_TABLES.has(table) && generatedId) {
              const { error: backfillErr } = await supabase
                .from(table)
                .update({ server_id: generatedId })
                .eq("id", generatedId)
                .is("server_id", null);
              if (backfillErr) {
                console.warn(
                  `sync-push: INSERT server_id backfill warning on "${table}" ` +
                    `(id=${generatedId}): ${backfillErr.message}`
                );
              }
            }
            results.push({
              local_id: localId,
              server_id: generatedId ?? null,
              status: "created",
              retryable: false,
            });
            processed++;
          }
        } else if (op === "UPDATE") {
          // For UPDATES the client must include server_id in rowData
          const serverId = getValue(fullRowData, "server_id", "serverId", "id");
          if (!serverId) {
            console.warn(`sync-push: UPDATE on "${table}" missing server_id (local_id=${localId})`);
            results.push({ local_id: localId, server_id: null, status: "error", retryable: true });
            continue;
          }
          const { local_id: _lid, localId: _lid2, server_id: _sid, serverId: _sid2, id: _id, school_server_id: _ssid, teacher_server_id: _tsid, ...updateData } = fullRowData;
          const updateSkipReason = await resolveForeignKeys(supabase, table, updateData, jwtClaims);
          if (updateSkipReason) {
            pushSkipResult(results, localId, serverId as string, table, "UPDATE", updateSkipReason);
            continue;
          }
          // ── Permanent test-lesson guard (UPDATE) ────────────────────
          if (table === "lessons") {
            const testTeacherId = "4e569a31-99d1-44a6-8bcc-4efbf0d67a71";
            // teacher_server_id was extracted into _tsid by destructuring above;
            // use _tsid directly (fall back to fullRowData for safety).
            const tsid = _tsid ?? fullRowData["teacher_server_id"] ?? fullRowData["teacher_id"];
            const topic = updateData["topic"] ?? fullRowData["topic"];
            if (
              tsid === testTeacherId &&
              topic === "direct test topic"
            ) {
              console.warn(
                `sync-push: SKIP UPDATE test-lesson (local_id=${localId}): ` +
                  `teacher=${tsid}, topic=${topic}`
              );
              results.push({
                local_id: localId,
                server_id: serverId as string,
                status: "skipped",
                retryable: false,
              });
              continue;
            }
          }
          // Bump updated_at server-side: client payloads never include it and
          // sync-pull only returns rows with updated_at > lastSyncTimestamp.
          // Without this, an UPDATE (e.g. admin approval changing status)
          // never propagates to other devices.
          if (updateData["updated_at"] === undefined) {
            updateData["updated_at"] = new Date().toISOString();
          }
          const { error } = await supabase
            .from(table)
            .update(updateData)
            .eq("id", serverId);
          if (error) {
            console.warn(`sync-push: UPDATE error on "${table}" (local_id=${localId}): ${error.message}`);
            results.push({ local_id: localId, server_id: serverId as string, status: "error", retryable: true, error: error.message });
            continue;
          }
          // DIAG: Log UPDATE details
          console.log(`[SYNC-PUSH-DIAG] UPDATE success: localId=${localId}, serverId=${serverId}`);
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

          // Guard: if the target id is not a valid server UUID (e.g. a client
          // queued a DELETE for a record whose INSERT was skipped server-side
          // so only its local integer id is present), the `.eq("id", serverId)`
          // soft-delete would throw and retry forever. Treat it as idempotent:
          // there is no server row to soft-delete, so report success.
          const serverIdStr = String(serverId);
          const isUuid =
            /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
              serverIdStr,
            );
          if (!isUuid) {
            console.warn(
              `sync-push: DELETE on "${table}" (local_id=${localId}) has non-UUID id "${serverIdStr}" — treating as already deleted`,
            );
            results.push({
              local_id: localId,
              server_id: serverIdStr,
              status: "deleted",
              retryable: false,
            });
            processed++;
            continue;
          }

          // ── Diagram cleanup: fetch lesson content before soft-delete ────
          if (table === "lessons") {
            await cleanupLessonDiagrams(supabase, serverIdStr, localId);
          }

          const { error } = await supabase
            .from(table)
            .update({
              is_deleted: true,
              // Bump updated_at so the soft-delete propagates to peers
              // (sync-pull filters by updated_at > lastSyncTimestamp).
              updated_at: new Date().toISOString(),
            })
            .eq("id", serverIdStr);
          if (error) {
            console.warn(`sync-push: DELETE error on "${table}" (local_id=${localId}): ${error.message}`);
            results.push({ local_id: localId, server_id: serverIdStr, status: "error", retryable: true });
            continue;
          }
          results.push({
            local_id: localId,
            server_id: serverIdStr,
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

    // DIAG: Log the complete response before sending
    console.log(`[SYNC-PUSH-DIAG] Final response: processed=${processed}, resultsCount=${results.length}`);
    console.log(`[SYNC-PUSH-DIAG] Results: ${JSON.stringify(results)}`);

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
