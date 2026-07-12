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

    let { email, otp, newPassword } = await req.json();
    email = email.toLowerCase();

    if (!email || !otp || !newPassword) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: email, otp, newPassword" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── Look up the admin teacher ──────────────────────────────────────────
    const { data: admin, error: adminError } = await supabase
      .from("teachers")
      .select("id, school_id, email")
      .eq("email", email)
      .eq("role", "admin")
      .maybeSingle();

    if (adminError || !admin) {
      return new Response(
        JSON.stringify({ error: "Admin account not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Hash the provided OTP for comparison ───────────────────────────────
    const otpHashBytes = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(otp)
    );
    const otpHash = Array.from(new Uint8Array(otpHashBytes))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // ── Find the OTP record ────────────────────────────────────────────────
    const { data: otpRecord, error: otpError } = await supabase
      .from("admin_recovery_otps")
      .select("*")
      .eq("email", email)
      .eq("otp_hash", otpHash)
      .eq("used", false)
      .maybeSingle();

    if (otpError || !otpRecord) {
      return new Response(
        JSON.stringify({ error: "Invalid OTP" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Check expiry ───────────────────────────────────────────────────────
    if (new Date(otpRecord.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({ error: "OTP has expired" }),
        { status: 410, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Check attempts ─────────────────────────────────────────────────────
    if (otpRecord.attempts >= 5) {
      return new Response(
        JSON.stringify({ error: "Too many failed attempts. Request a new OTP." }),
        { status: 429, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Increment attempts ─────────────────────────────────────────────────
    await supabase
      .from("admin_recovery_otps")
      .update({ attempts: otpRecord.attempts + 1 })
      .eq("id", otpRecord.id);

    // ── Update password in Supabase Auth ───────────────────────────────────
    // First, find the auth user by email
    const { data: users, error: usersError } = await supabase.auth.admin.listUsers();
    if (usersError) throw usersError;

    const authUser = users.users.find((u) => u.email === email);
    if (!authUser) {
      return new Response(
        JSON.stringify({ error: "Auth user not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    const { error: updateAuthError } = await supabase.auth.admin.updateUserById(
      authUser.id,
      { password: newPassword }
    );
    if (updateAuthError) throw updateAuthError;

    // ── Update local password hash in teachers table ──────────────────────
    const pepper = Deno.env.get("PASSWORD_PEPPER")!;
    const newPasswordHash = await bcrypt.hash(newPassword + pepper, 10);

    await supabase
      .from("teachers")
      .update({
        password_hash: newPasswordHash,
        password_hash_version: 2,
        force_password_reset: false,
      })
      .eq("id", admin.id);

    // ── Mark OTP as used ───────────────────────────────────────────────────
    await supabase
      .from("admin_recovery_otps")
      .update({ used: true })
      .eq("id", otpRecord.id);

    // ── Fetch updated teacher and school ───────────────────────────────────
    const { data: updatedTeacher } = await supabase
      .from("teachers")
      .select("*, schools(*)")
      .eq("id", admin.id)
      .single();

    const teacher = updatedTeacher;
    const school = updatedTeacher?.schools as Record<string, unknown> | undefined;

    // ── Sign JWT so the client can proceed without re-login ────────────────
    const cryptoKey = await getHmacKey(JWT_SECRET);
    const tokenVersion = (teacher.token_version as number) ?? 1;
    const jwt = await create(
      { alg: "HS256", typ: "JWT" },
      {
        sub: teacher.id,
        teacher_id: teacher.id,
        school_id: teacher.school_id,
        is_admin: teacher.role === "admin",
        token_version: tokenVersion,
        exp: getNumericDate(60 * 60 * 24), // 24 hours
      },
      cryptoKey
    );

    return new Response(
      JSON.stringify({
        jwt,
        teacher: {
          id: teacher.id,
          email: teacher.email,
          name: teacher.teacher_name,
          role: teacher.role,
          school_id: teacher.school_id,
          email_verified: teacher.email_verified ?? false,
        },
        school: {
          id: school?.id,
          name: school?.school_name,
          subscription_tier: school?.subscription_tier,
        },
        wrapped_school_key: school?.school_master_key_wrapped ?? null,
        password_hash_version: 2,
        email_verified: teacher.email_verified ?? false,
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
