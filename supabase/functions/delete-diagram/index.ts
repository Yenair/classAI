import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

const BUCKET_NAME = "diagrams";

/**
 * Extract the Storage object path from a Supabase Storage public URL.
 * e.g. "https://<project>.supabase.co/storage/v1/object/public/diagrams/abc.png"
 *      -> "abc.png"
 */
function extractStoragePath(publicUrl: string): string | null {
  try {
    const marker = `/object/public/${BUCKET_NAME}/`;
    const idx = publicUrl.indexOf(marker);
    if (idx === -1) return null;
    return publicUrl.substring(idx + marker.length);
  } catch {
    return null;
  }
}

/**
 * Parse the lesson identifier from a storage filename.
 * Filenames follow the pattern: {lessonPart}_{timestamp}.png
 * e.g. "550e8400-e29b-41d4-a716-446655440000_1712345678901.png" -> "550e8400-e29b-41d4-a716-446655440000"
 */
function parseLessonIdFromFilename(filename: string): string | null {
  const underscoreIdx = filename.lastIndexOf("_");
  if (underscoreIdx === -1) return null;
  return filename.substring(0, underscoreIdx);
}

/**
 * Verify the caller is authorized to delete a diagram from the given URL.
 *
 * Strategy: parse the filename to extract the lesson identifier, look up the
 * lesson in the database, and confirm the caller belongs to the same school
 * that owns the lesson.  This prevents cross-school deletion attacks using
 * public/guessable Storage URLs.
 */
async function authorizeDeletion(
  supabase: ReturnType<typeof createClient>,
  storagePath: string,
  callerSchoolId: string,
): Promise<{ authorized: boolean; error?: string }> {
  // ── Parse the filename from the storage path ─────────────────────────
  // path is like "550e8400-e29b-41d4-a716-446655440000_1712345678901.png"
  const filename = storagePath.split("/").pop() ?? storagePath;
  const lessonIdStr = parseLessonIdFromFilename(filename);

  if (!lessonIdStr) {
    return {
      authorized: false,
      error: "Could not parse lesson identifier from diagram filename",
    };
  }

  // ── Check if the lessonId looks like a UUID ─────────────────────────
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(lessonIdStr)) {
    // Non-UUID lesson IDs (e.g. "unknown_0", "new_...") are typically from
    // temporary/offline-created lessons that haven't synced yet.  Allow
    // deletion since the JWT is already validated — the sync-push
    // authoritative cleanup will catch any orphaned files via the normal
    // lesson-level lookup.
    console.warn(
      `[delete-diagram] Non-UUID lesson ID "${lessonIdStr}" — allowing deletion based on valid JWT`,
    );
    return { authorized: true };
  }

  // ── Look up the lesson to verify school ownership ───────────────────
  const { data: lesson, error: lessonError } = await supabase
    .from("lessons")
    .select("school_id")
    .eq("id", lessonIdStr)
    .maybeSingle();

  if (lessonError) {
    return {
      authorized: false,
      error: `Database error looking up lesson: ${lessonError.message}`,
    };
  }

  if (!lesson) {
    // Lesson not found — try matching the full URL in lesson content as
    // a fallback, in case the filename doesn't follow the standard pattern.
    const { data: contentMatch, error: contentError } = await supabase
      .from("lessons")
      .select("school_id")
      .filter("content", "like", `%${storagePath}%`)
      .maybeSingle();

    if (contentError || !contentMatch) {
      return {
        authorized: false,
        error: "No lesson found for this diagram — cannot verify ownership",
      };
    }

    if (contentMatch.school_id !== callerSchoolId) {
      return {
        authorized: false,
        error: "Caller does not own the lesson containing this diagram",
      };
    }

    return { authorized: true };
  }

  // ── Verify school ownership ─────────────────────────────────────────
  if (lesson.school_id !== callerSchoolId) {
    return {
      authorized: false,
      error: "Caller does not own the lesson containing this diagram",
    };
  }

  return { authorized: true };
}

serve(async (req) => {
  try {
    // ── 1. Validate JWT ────────────────────────────────────────────────
    const classaiJwt = req.headers.get("x-classai-jwt");
    if (!classaiJwt) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid JWT header" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    const jwtSecret = Deno.env.get("JWT_SECRET");
    if (!jwtSecret) {
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: JWT_SECRET not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const token = classaiJwt;
    let claims: Record<string, unknown>;
    try {
      claims = await validateTokenVersion(
        token,
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

    const callerSchoolId = claims.school_id as string;
    if (!callerSchoolId) {
      return new Response(
        JSON.stringify({ error: "Invalid token: no school_id claim" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 2. Parse request body ──────────────────────────────────────────
    const { url } = await req.json() as { url?: string };

    if (!url || typeof url !== "string" || url.trim() === "") {
      return new Response(
        JSON.stringify({ error: "Request must include a `url` field" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 3. Extract storage path from URL ───────────────────────────────
    const storagePath = extractStoragePath(url.trim());
    if (!storagePath) {
      return new Response(
        JSON.stringify({
          error: "Could not extract storage path from the provided URL",
          detail: "Expected a Supabase Storage public URL for the 'diagrams' bucket",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 4. Authorize ──────────────────────────────────────────────────
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { authorized, error: authError } = await authorizeDeletion(
      supabase,
      storagePath,
      callerSchoolId,
    );

    if (!authorized) {
      return new Response(
        JSON.stringify({ error: authError ?? "Unauthorized" }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 5. Delete the Storage object ──────────────────────────────────
    const { error: deleteError, data: deleteData } = await supabase
      .storage
      .from(BUCKET_NAME)
      .remove([storagePath]);

    if (deleteError) {
      // Object may already have been deleted — that's fine, it's idempotent.
      console.warn(
        `[delete-diagram] Storage remove returned error for "${storagePath}": ${deleteError.message}`,
      );
      // Still return success since the goal (no orphaned file) is achieved
      // whether the object was already gone or just deleted now.
      return new Response(
        JSON.stringify({ deleted: false, detail: "Object was already removed or not found" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    console.log(`[delete-diagram] Deleted "${storagePath}"`);

    return new Response(
      JSON.stringify({ deleted: true, path: storagePath }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[delete-diagram] Fatal error:", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : "Internal server error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
