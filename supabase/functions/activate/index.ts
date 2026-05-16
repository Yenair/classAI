import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as bcrypt from "https://deno.land/x/bcrypt@v0.4.1/mod.ts";
import { v4 as uuid } from "https://deno.land/std@0.177.0/uuid/mod.ts";

serve(async (req) => {
  try {
    const { activation_code, email, password, recovery_email } = await req.json();

    // Validate activation code (in production, check against a pre-shared secret or database)
    if (activation_code !== Deno.env.get("ACTIVATION_SECRET")) {
      return new Response(JSON.stringify({ error: "Invalid activation code" }), { status: 401 });
    }

    // Initialize Supabase with service role (bypass RLS)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1. Create school
    const { data: school, error: schoolError } = await supabase
      .from("schools")
      .insert({
        school_name: "My School",  // can be set via request in future
        short_code: "SCH" + Math.random().toString(36).substring(2, 6).toUpperCase(),
        admin_recovery_email: recovery_email,
        subscription_tier: "free",
        total_seats: 5,
      })
      .select()
      .single();

    if (schoolError) throw schoolError;

    // 2. Hash the password with bcrypt and pepper (from environment)
    const pepper = Deno.env.get("PASSWORD_PEPPER")!;
    const passwordHash = await bcrypt.hash(password + pepper);

    // 3. Generate salt for future offline logins (stored as base64)
    const salt = crypto.getRandomValues(new Uint8Array(32));
    const saltBase64 = btoa(String.fromCharCode(...salt));

    // 4. Create the admin teacher
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .insert({
        email,
        teacher_name: email, // can be updated later
        role: "admin",
        school_id: school.id,
        password_hash: passwordHash,
        salt: saltBase64,
        password_hash_version: 1,
        force_password_reset: false,
      })
      .select()
      .single();

    if (teacherError) throw teacherError;

    // 5. Generate a random school master key (256-bit) and wrap it with admin's password-derived key (simulated here for brevity; in production use KWP)
    const schoolKey = crypto.getRandomValues(new Uint8Array(32));
    // For now, store the raw key encrypted with a server-side secret; actual wrapping happens in Phase 2/3 of Flutter
    // Placeholder: store base64-encoded key as "wrapped" (will be properly wrapped by the client after login)
    const { error: updateError } = await supabase
      .from("schools")
      .update({ school_master_key_wrapped: btoa(String.fromCharCode(...schoolKey)) })
      .eq("id", school.id);
    if (updateError) throw updateError;

    return new Response(
      JSON.stringify({
        teacher_id: teacher.id,
        school_id: school.id,
        school_name: school.school_name,
        wrapped_school_key: btoa(String.fromCharCode(...schoolKey)), // base64
        password_hash_version: 1,
        offline_credits: 3, // Free tier
        last_credit_refill_server_time: new Date().toISOString(),
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});