import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as bcrypt from "https://deno.land/x/bcrypt@v0.4.1/mod.ts";
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts";

const JWT_SECRET = Deno.env.get("JWT_SECRET")!;

serve(async (req) => {
  try {
    const { email, password, device_id } = await req.json();

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1. Fetch teacher
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("*, schools(school_master_key_wrapped, subscription_tier)")
      .eq("email", email)
      .maybeSingle();

    if (teacherError || !teacher) {
      return new Response(JSON.stringify({ error: "Invalid credentials" }), { status: 401 });
    }

    // 2. Verify password
    const pepper = Deno.env.get("PASSWORD_PEPPER")!;
    const valid = await bcrypt.compare(password + pepper, teacher.password_hash);
    if (!valid) {
      return new Response(JSON.stringify({ error: "Invalid credentials" }), { status: 401 });
    }

    // 3. If force_password_reset, issue short-lived JWT (5 min) with flag
    const isForceReset = teacher.force_password_reset === true;
    const tokenExpiry = isForceReset ? getNumericDate(60 * 5) : getNumericDate(60 * 60 * 24); // 5 min vs 24 hours

    // 4. Generate JWT
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
      JWT_SECRET
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

    // 5. Register device
    if (device_id) {
      await supabase.from("teacher_devices").upsert({
        teacher_id: teacher.id,
        device_id,
        last_active: new Date(),
        is_active: true,
      });
    }

    // 6. Return auth result
    const school = teacher.schools;
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
        wrapped_school_key: school.school_master_key_wrapped, // may be null if activation not done
        salt: teacher.salt,
        password_hash_version: teacher.password_hash_version,
        offline_credits: 3, // placeholder, should come from a credit table later
        last_credit_refill_server_time: teacher.last_credit_refill_date?.toISOString() ?? null,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});