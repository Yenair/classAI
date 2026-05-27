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

    let { email, password, device_id } = await req.json();
    email = email.toLowerCase();

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1. Fetch teacher
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("*, schools(id, school_name, school_master_key_wrapped, subscription_tier)")
      .eq("email", email)
      .maybeSingle();

    if (teacherError || !teacher) {
      return new Response(JSON.stringify({ error: "Invalid credentials" }), { status: 401 });
    }

    // 2. Verify password
    const pepper = Deno.env.get("PASSWORD_PEPPER");
    if (!pepper) {
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: PASSWORD_PEPPER not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
    const valid = await bcrypt.compare(password + pepper, teacher.password_hash);
    if (!valid) {
      return new Response(JSON.stringify({ error: "Invalid credentials" }), { status: 401 });
    }

    // 3. Check for concurrent sessions (no device sharing)
    // If device_id is provided and different from current_device_id, reject login
    if (device_id && teacher.current_device_id && teacher.current_device_id !== device_id) {
      return new Response(
        JSON.stringify({ error: "Session active on another device. Please logout from the other device first." }),
        { status: 403 }
      );
    }

    // 4. Determine if this is a new device
    let newDevice = false;
    if (device_id) {
      const { data: existingDevice } = await supabase
        .from("teacher_devices")
        .select("id")
        .eq("teacher_id", teacher.id)
        .eq("device_id", device_id)
        .maybeSingle();

      newDevice = !existingDevice;
    }

    // 5. If force_password_reset, issue short-lived JWT (5 min) with flag
    const isForceReset = teacher.force_password_reset === true;
    const tokenExpiry = isForceReset ? getNumericDate(60 * 5) : getNumericDate(60 * 60 * 24); // 5 min vs 24 hours

    // 6. Generate JWT
    const cryptoKey = await getHmacKey(JWT_SECRET);
    const jwt = await create(
      { alg: "HS256", typ: "JWT" },
      {
        sub: teacher.id,
        teacher_id: teacher.id,
        school_id: teacher.school_id,
        is_admin: teacher.role === "admin",
        force_password_reset: isForceReset,
        exp: tokenExpiry,
      },
      cryptoKey
    );

    if (isForceReset) {
      const school = teacher.schools;
      return new Response(
        JSON.stringify({
          jwt,
          force_password_reset: true,
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
          wrapped_school_key: school.school_master_key_wrapped,
          salt: teacher.salt,
          password_hash_version: teacher.password_hash_version,
          offline_credits: 3,
          last_credit_refill_server_time: teacher.last_credit_refill_date?.toISOString() ?? null,
        }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    // 7. Register device - update current_device_id on teachers table
    if (device_id) {
      await supabase.from("teachers").update({ current_device_id: device_id }).eq("id", teacher.id);
    }

    // 8. Return auth result
    const school = teacher.schools;
    // If this is a new device, force email_verified to false even if
    // the teacher's account is already verified globally, so the client
    // shows the email verification popup.
    const responseEmailVerified = newDevice ? false : (teacher.email_verified ?? false);
    
    return new Response(
      JSON.stringify({
        jwt,
        teacher: {
          id: teacher.id,
          email: teacher.email,
          name: teacher.teacher_name,
          role: teacher.role,
          school_id: teacher.school_id,
          email_verified: responseEmailVerified,
        },
        school: {
          id: school.id,
          name: school.school_name,
          subscription_tier: school.subscription_tier,
        },
        wrapped_school_key: school.school_master_key_wrapped, // may be null if activation not done
        salt: teacher.salt,
        password_hash_version: teacher.password_hash_version,
        offline_credits: 3, // placeholder, should come from a credit table later
        last_credit_refill_server_time: teacher.last_credit_refill_date?.toISOString() ?? null,
        email_verified: responseEmailVerified,
        new_device: newDevice,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});