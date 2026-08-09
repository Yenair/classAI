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
  const JWT_SECRET = Deno.env.get("JWT_SECRET");
  if (!JWT_SECRET) {
    return new Response(
      JSON.stringify({ error: "Server misconfiguration: JWT_SECRET not set" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
  try {
    const {
      activationCode,
      email,
      password,
      deviceId,
      isAdmin,
      recoveryEmail,
    } = await req.json();

    if (!activationCode || !email || !password) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: activationCode, email, password" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (isAdmin && (!recoveryEmail || recoveryEmail.trim() === "")) {
      return new Response(
        JSON.stringify({ error: "Recovery email is required for admin activation" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── 1. Validate activation code against pending_activations table ──────
    const { data: pending, error: pendingError } = await supabase
      .from("pending_activations")
      .select("*")
      .eq("code", activationCode)
      .maybeSingle();

    if (pendingError || !pending) {
      return new Response(
        JSON.stringify({ error: "Invalid activation code" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    if (pending.used_at) {
      return new Response(
        JSON.stringify({ error: "Activation code has already been used" }),
        { status: 409, headers: { "Content-Type": "application/json" } }
      );
    }

    if (new Date(pending.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({ error: "Activation code has expired" }),
        { status: 410, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 2. Create the auth user in Supabase Auth ───────────────────────────
    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });

    if (authError) {
      // If user already exists, try to get them
      if (authError.message.includes("already exists") || authError.message.includes("already registered")) {
        const { data: existingUsers } = await supabase.auth.admin.listUsers();
        const existingUser = existingUsers?.users.find((u) => u.email === email);
        if (!existingUser) {
          return new Response(
            JSON.stringify({ error: "Failed to create or find auth user" }),
            { status: 500, headers: { "Content-Type": "application/json" } }
          );
        }
      } else {
        throw authError;
      }
    }

    // ── 3. Hash password with bcrypt + pepper ──────────────────────────────
    const pepper = Deno.env.get("PASSWORD_PEPPER")!;
    const passwordHash = await bcrypt.hash(password + pepper, 10);

    // Generate salt for offline login
    const salt = crypto.getRandomValues(new Uint8Array(32));
    const saltBase64 = btoa(String.fromCharCode(...salt));

    // Generate random school master key
    const schoolKey = crypto.getRandomValues(new Uint8Array(32));
    const wrappedSchoolKey = btoa(String.fromCharCode(...schoolKey));

    let schoolRecord: Record<string, unknown>;
    let teacherRecord: Record<string, unknown>;

    if (isAdmin) {
      // ── 4a. Admin activation: create school + admin teacher ──────────────
      const shortCode =
        "SCH" +
        Math.random().toString(36).substring(2, 6).toUpperCase() +
        Math.random().toString(36).substring(2, 4).toUpperCase();

      const { data: school, error: schoolError } = await supabase
        .from("schools")
        .insert({
          school_name: "My School",
          short_code: shortCode,
          admin_recovery_email: recoveryEmail,
          admin_recovery_email_verified: false,
          subscription_tier: "free",
          total_seats: 5,
          school_master_key_wrapped: wrappedSchoolKey,
        })
        .select()
        .single();

      if (schoolError) throw schoolError;
      schoolRecord = school;

      const { data: teacher, error: teacherError } = await supabase
        .from("teachers")
        .insert({
          email,
          teacher_name: email,
          role: "admin",
          school_id: schoolRecord.id,
          password_hash: passwordHash,
          salt: saltBase64,
          password_hash_version: 1,
          force_password_reset: false,
          is_active: true,
          email_verified: false, // must verify email on first login
        })
        .select()
        .single();

      if (teacherError) throw teacherError;
      teacherRecord = teacher;
    } else {
      // ── 4b. Teacher activation: must have school_id from the code ────────
      if (!pending.school_id) {
        return new Response(
          JSON.stringify({ error: "Teacher activation code is not linked to any school" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      const { data: school, error: schoolError } = await supabase
        .from("schools")
        .select("*")
        .eq("id", pending.school_id)
        .single();

      if (schoolError || !school) {
        return new Response(
          JSON.stringify({ error: "Linked school not found" }),
          { status: 404, headers: { "Content-Type": "application/json" } }
        );
      }
      schoolRecord = school;

      const { data: teacher, error: teacherError } = await supabase
        .from("teachers")
        .insert({
          email,
          teacher_name: email,
          role: "teacher",
          school_id: pending.school_id,
          password_hash: passwordHash,
          salt: saltBase64,
          password_hash_version: 1,
          force_password_reset: false,
          is_active: true,
          email_verified: false, // must verify email on first login
        })
        .select()
        .single();

      if (teacherError) throw teacherError;
      teacherRecord = teacher;
    }

    // ── 5. Mark activation code as used ────────────────────────────────────
    await supabase
      .from("pending_activations")
      .update({ used_at: new Date().toISOString() })
      .eq("id", pending.id);

    // ── 6. Register device and set current_device_id ────────────────────────
    if (deviceId) {
      await supabase.from("teacher_devices").upsert({
        teacher_id: teacherRecord.id,
        device_id: deviceId,
        last_active: new Date().toISOString(),
        is_active: true,
      });
      // Initialize current_device_id on the teacher record (F17 gap fix)
      await supabase
        .from("teachers")
        .update({ current_device_id: deviceId })
        .eq("id", teacherRecord.id);
    }

    // ── 7. Sign JWT for the newly created teacher ──────────────────────────
    const cryptoKey = await getHmacKey(JWT_SECRET);
    const tokenVersion = (teacherRecord.token_version as number) ?? 1;
    const jwt = await create(
      { alg: "HS256", typ: "JWT" },
      {
        sub: teacherRecord.id,
        teacher_id: teacherRecord.id,
        school_id: teacherRecord.school_id,
        is_admin: teacherRecord.role === "admin",
        token_version: tokenVersion,
        exp: getNumericDate(60 * 60 * 24 * 7), // 7 days
      },
      cryptoKey
    );

    // ── 8. Return AuthResult-compatible payload with jwt ──────────────────
    return new Response(
      JSON.stringify({
        jwt,
        teacher: {
          id: teacherRecord.id,
          email: teacherRecord.email,
          name: teacherRecord.teacher_name,
          role: teacherRecord.role,
          school_id: teacherRecord.school_id,
          email_verified: false,
        },
        school: {
          id: schoolRecord.id,
          name: schoolRecord.school_name,
          subscription_tier: schoolRecord.subscription_tier,
        },
        wrapped_school_key: wrappedSchoolKey,
        password_hash_version: 1,
        offline_credits: 3,
        last_credit_refill_server_time: new Date().toISOString(),
        email_verified: false,
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
