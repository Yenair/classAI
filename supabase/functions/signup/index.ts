import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts";

/** Convert a plain string secret into a CryptoKey for HS256 JWT signing. */
function getHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

serve(async (req) => {
  try {
    const JWT_SECRET = Deno.env.get("JWT_SECRET");
    if (!JWT_SECRET) {
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: JWT_SECRET not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const { school_name, admin_email, admin_password, recovery_email } =
      await req.json();

    // ── Validate required fields ──────────────────────────────────────────
    if (!school_name || !admin_email || !admin_password) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: school_name, admin_email, admin_password",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (typeof admin_password !== "string" || admin_password.length < 8) {
      return new Response(
        JSON.stringify({ error: "Password must be at least 8 characters" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── Check if email already exists ────────────────────────────────────
    const { data: existingTeacher } = await supabase
      .from("teachers")
      .select("id")
      .eq("email", admin_email)
      .maybeSingle();

    if (existingTeacher) {
      return new Response(
        JSON.stringify({ error: "An account with this email already exists" }),
        { status: 409, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Hash password with bcrypt + pepper ─────────────────────────────────
    const pepper = Deno.env.get("PASSWORD_PEPPER");
    if (!pepper) {
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: PASSWORD_PEPPER not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
    const passwordHash = await bcrypt.hash(admin_password + pepper, 10);

    // Generate random 32-byte salt (base64)
    const salt = crypto.getRandomValues(new Uint8Array(32));
    const saltBase64 = btoa(String.fromCharCode(...salt));

    // ── Generate school short code ─────────────────────────────────────────
    const shortCode =
      "SCH" +
      Math.random().toString(36).substring(2, 6).toUpperCase() +
      Math.random().toString(36).substring(2, 4).toUpperCase();

    // ── Create the school ──────────────────────────────────────────────────
    const { data: school, error: schoolError } = await supabase
      .from("schools")
      .insert({
        school_name,
        short_code: shortCode,
        subscription_tier: "free",
        total_seats: 5,
        admin_recovery_email: recovery_email ?? null,
        admin_recovery_email_verified: false,
      })
      .select()
      .single();

    if (schoolError) {
      console.error("[signup] school insert error:", schoolError);
      throw schoolError;
    }

    // ── Create the admin teacher ───────────────────────────────────────────
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .insert({
        email: admin_email,
        teacher_name: school_name, // use school name as initial teacher name
        role: "admin",
        school_id: school.id,
        password_hash: passwordHash,
        salt: saltBase64,
        password_hash_version: 1,
        force_password_reset: false,
        is_active: true,
      })
      .select()
      .single();

    if (teacherError) {
      console.error("[signup] teacher insert error:", teacherError);
      // Rollback: delete the school we just created
      await supabase.from("schools").delete().eq("id", school.id);
      throw teacherError;
    }

    // ── Generate JWT ──────────────────────────────────────────────────────
    const cryptoKey = await getHmacKey(JWT_SECRET);
    const jwt = await create(
      { alg: "HS256", typ: "JWT" },
      {
        sub: teacher.id,
        teacher_id: teacher.id,
        school_id: teacher.school_id,
        is_admin: true,
        exp: getNumericDate(60 * 60 * 24), // 24 hours
      },
      cryptoKey
    );

    // ── Return AuthResult-compatible payload ──────────────────────────────
    return new Response(
      JSON.stringify({
        jwt,
        teacher: {
          id: teacher.id,
          email: teacher.email,
          name: teacher.teacher_name,
          role: teacher.role,
          school_id: teacher.school_id,
        },
        school: {
          id: school.id,
          name: school.school_name,
          subscription_tier: school.subscription_tier,
        },
        wrapped_school_key: school.school_master_key_wrapped ?? null,
        salt: teacher.salt,
        password_hash_version: teacher.password_hash_version,
        offline_credits: 3,
        last_credit_refill_server_time: new Date().toISOString(),
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[signup] error:", err);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
