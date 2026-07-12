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
  // audit_logs / payment_events fields
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
 * Default values for columns the client's INSERT payload may omit.
 * The Supabase lessons/exams tables have NOT NULL columns that are not
 * sent directly by the client — they must be derived or defaulted.
 *
 * NOTE: school_id, teacher_id, subject_id are resolved from text
 * references by resolveForeignKeys().
 */
const LESSON_DEFAULTS: Record<string, unknown> = {
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
  title: "",
  credits_spent: 0,
  questions: "",
  theory_questions: "",
  marking_scheme: "",
};

const SCHEME_OF_WORK_DEFAULTS: Record<string, unknown> = {
  status: "draft",
};

const VAULT_ITEMS_DEFAULTS: Record<string, unknown> = {
  min_tier: "free",
  credit_cost: 0,
  needs_approval: true,
  approval_status: "pending",
  is_deleted: false,
};

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
): Promise<void> {
  if (table === "lessons" || table === "exams") {
    // ── 1. School: school_server_id IS schools.id (UUID) ──────────────
    if (rowData["school_server_id"] && !rowData["school_id"]) {
      rowData["school_id"] = rowData["school_server_id"];
    }

    // ── 2. Teacher: teacher_server_id IS teachers.id (UUID) ────────────
    if (rowData["teacher_server_id"] && !rowData["teacher_id"]) {
      rowData["teacher_id"] = rowData["teacher_server_id"];
    }

    // ── 3. Subject text name → subject_id UUID lookup ────────────────
    // The subjects table uses `subject_name`, scoped by school_id and class_level.
    // If we have both a subject name AND a resolved school_id, use them.
    if (rowData["subject"] && !rowData["subject_id"]) {
      const subjectName = rowData["subject"] as string;
      const schoolId = rowData["school_id"] as string | undefined;
      const classLevel = rowData["class_level"] as string | undefined;

      let subjectQuery = supabase
        .from("subjects")
        .select("id")
        .eq("subject_name", subjectName)
        .maybeSingle();

      // Narrow by school and class_level if available
      if (schoolId) {
        subjectQuery = subjectQuery.eq("school_id", schoolId);
      }
      if (classLevel) {
        subjectQuery = subjectQuery.eq("class_level", classLevel);
      }

      const { data: subject } = await subjectQuery;
      if (subject?.id) {
        rowData["subject_id"] = subject.id;
      } else {
        console.warn(
          `resolveForeignKeys: no subject found for name="${subjectName}" ` +
          `school="${schoolId}" class="${classLevel}"`
        );
        // Use placeholder to avoid NOT NULL violation
        rowData["subject_id"] = "00000000-0000-0000-0000-000000000000";
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
    // Resolve teacher_server_id → teacher_id (UUID)
    if (rowData["teacher_server_id"] && !rowData["teacher_id"]) {
      rowData["teacher_id"] = rowData["teacher_server_id"];
    }
    // Resolve school_server_id → school_id (UUID)
    if (rowData["school_server_id"] && !rowData["school_id"]) {
      rowData["school_id"] = rowData["school_server_id"];
    }
    // Resolve subject_id — the client may send it as a local integer or a UUID string.
    // If it looks like a UUID, use it directly; otherwise skip (server has its own FKs).
    if (rowData["subject_id"]) {
      const subId = rowData["subject_id"] as string;
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(subId)) {
        // It's a local integer ID — we can't resolve it server-side.
        delete rowData["subject_id"];
      }
    }
    // Apply defaults
    for (const [col, defaultVal] of Object.entries(SCHEME_OF_WORK_DEFAULTS)) {
      if (rowData[col] === undefined || rowData[col] === null) {
        rowData[col] = defaultVal;
      }
    }
    // Remove local-only fields
    delete rowData["teacher_server_id"];
    delete rowData["school_server_id"];
    delete rowData["local_id"];
  }

  // ═══════════════════════════════════════════════════════════════
  // vault_items handler
  // ═══════════════════════════════════════════════════════════════
  if (table === "vault_items") {
    // Resolve teacher_server_id → teacher_id (UUID)
    if (rowData["teacher_server_id"] && !rowData["teacher_id"]) {
      rowData["teacher_id"] = rowData["teacher_server_id"];
    }
    // Resolve school_server_id → school_id (UUID)
    if (rowData["school_server_id"] && !rowData["school_id"]) {
      rowData["school_id"] = rowData["school_server_id"];
    }
    // Map subject text name → subject_id if needed
    if (rowData["subject"] && !rowData["subject_id"]) {
      const subjectName = rowData["subject"] as string;
      const { data: subject } = await supabase
        .from("subjects")
        .select("id")
        .eq("subject_name", subjectName)
        .maybeSingle();
      if (subject?.id) {
        rowData["subject_id"] = subject.id;
      }
    }
    // Map author_name → author_name (already correct field)
    // Apply defaults
    for (const [col, defaultVal] of Object.entries(VAULT_ITEMS_DEFAULTS)) {
      if (rowData[col] === undefined || rowData[col] === null) {
        rowData[col] = defaultVal;
      }
    }
    // Remove local-only fields
    delete rowData["teacher_server_id"];
    delete rowData["school_server_id"];
    delete rowData["local_id"];
    delete rowData["encrypted"];
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
  }

  // ═══════════════════════════════════════════════════════════════
  // audit_logs handler
  // ═══════════════════════════════════════════════════════════════
  if (table === "audit_logs") {
    // teacher_id and school_id are already UUIDs — use them directly
    delete rowData["local_id"];
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
      "audit_logs", "payment_events",
      "security_config", "credit_spend",
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
    //   audit_logs     — audit trail of admin actions
    //   payment_events — payment/transaction records
    //   app_config     — system-wide config (pricing, limits, feature flags)
    //   pending_activations — activation codes for onboarding
    //   activation_codes    — payment activation codes with reference
    //   admin_recovery_otps — admin password-recovery OTPs
    //   verification_codes  — email verification OTPs
    //   recovery_codes      — password-reset recovery codes
    const adminTables = new Set([
      "teachers", "schools", "subjects",
      "audit_logs", "payment_events",
      "app_config",
      "pending_activations",
      "activation_codes",
      "admin_recovery_otps",
      "verification_codes",
      "recovery_codes",
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
          local_id: 0,
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
          local_id: 0,
          server_id: null,
          status: "error",
          retryable: false,
          error: "Admin access required for this table",
        });
        continue;
      }

      // DIAG: Log the raw rowData keys BEFORE decompression
      console.log(`[SYNC-PUSH-DIAG] Entry ${idx}: table=${table}, op=${op}, rawKeys=${Object.keys(rowData as Record<string, unknown>).join(",")}`);

      // Decompress rowData if it has short keys
      const fullRowData = decompressRow(rowData as Record<string, unknown>);

      // DIAG: Log decompressed keys to verify KEY_MAP is working
      console.log(`[SYNC-PUSH-DIAG] Entry ${idx}: decompressedKeys=${Object.keys(fullRowData).join(",")}`);

      // Extract local_id early so we can echo it back even on failure.
      const localId = (fullRowData["local_id"] as number | string | undefined) ?? 0;
      console.log(`[SYNC-PUSH-DIAG] Entry ${idx}: localId=${localId}, server_id=${fullRowData["server_id"] ?? "null"}`);

      try {
        if (op === "INSERT") {
          // Remove local-only fields; let server generate UUIDs
          const { local_id: _lid, localId: _lid2, ...insertData } = fullRowData;

          // ════════════════════════════════════════════════════════════
          // FIX: Resolve FK text references to UUIDs and apply defaults
          // ════════════════════════════════════════════════════════════
          await resolveForeignKeys(supabase, table, insertData);

          console.log(`[SYNC-PUSH-DIAG] INSERT data after resolveForeignKeys: ${JSON.stringify(insertData)}`);

          const { data: insertData_, error } = await supabase
            .from(table)
            .insert(insertData)
            .select("id");
          if (error) {
            console.warn(`sync-push: INSERT error on "${table}" (local_id=${localId}): ${error.message}`);
            console.warn(`sync-push: INSERT data was: ${JSON.stringify(insertData)}`);
            results.push({ local_id: localId, server_id: null, status: "error", retryable: true });
            continue;
          }
          const generatedId = insertData_?.[0]?.id as string | undefined;
          // DIAG: Log what INSERT returned
          console.log(`[SYNC-PUSH-DIAG] INSERT result: localId=${localId}, generatedId=${generatedId ?? "null"}, insertData_=${JSON.stringify(insertData_)}`);
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

          // ── Diagram cleanup: fetch lesson content before soft-delete ────
          if (table === "lessons") {
            await cleanupLessonDiagrams(supabase, serverId as string, localId);
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
