import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts";

/** Convert a plain string secret into a CryptoKey for HS256 JWT verification. */
function getHmacVerifyKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
}

serve(async (req) => {
  try {
    // ── 1. Extract and verify JWT ──────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid Authorization header" }),
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

    const token = authHeader.replace("Bearer ", "");
    let claims: Record<string, unknown>;
    try {
      const cryptoKey = await getHmacVerifyKey(jwtSecret);
      claims = await verify(token, cryptoKey);
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid or expired JWT" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    const teacherId = claims.teacher_id as string;

    // ── 2. Parse request body ─────────────────────────────────────────────
    const { new_password } = await req.json();

    if (!new_password || typeof new_password !== "string") {
      return new Response(
        JSON.stringify({ error: "Missing required field: new_password" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (new_password.length < 8) {
      return new Response(
        JSON.stringify({ error: "Password must be at least 8 characters" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 3. Verify teacher exists ───────────────────────────────────────────
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("id, password_hash_version")
      .eq("id", teacherId)
      .maybeSingle();

    if (teacherError || !teacher) {
      return new Response(
        JSON.stringify({ error: "Teacher not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 4. Hash new password with bcrypt + pepper ─────────────────────────
    const pepper = Deno.env.get("PASSWORD_PEPPER")!;
    const newPasswordHash = await bcrypt.hash(new_password + pepper, 10);

    // ── 5. Update password in teachers table, clear temp_password ──────────
    const newVersion = (teacher.password_hash_version ?? 1) + 1;

    const { error: updateError } = await supabase
      .from("teachers")
      .update({
        password_hash: newPasswordHash,
        password_hash_version: newVersion,
        force_password_reset: false,
        temp_password: null,
      })
      .eq("id", teacherId);

    if (updateError) {
      console.error("[change-password] update error:", updateError);
      throw updateError;
    }

    // ── 6. Return success ─────────────────────────────────────────────────
    return new Response(
      JSON.stringify({
        success: true,
        message: "Password changed successfully.",
        password_hash_version: newVersion,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[change-password] error:", err);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
