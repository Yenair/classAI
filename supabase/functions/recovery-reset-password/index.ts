import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as bcrypt from "https://deno.land/x/bcrypt@v0.4.1/mod.ts";

serve(async (req) => {
  try {
    const { email, recovery_code, new_password } = await req.json();
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Find teacher by email
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("id, school_id")
      .eq("email", email)
      .maybeSingle();
    if (teacherError || !teacher) {
      return new Response(JSON.stringify({ error: "Invalid email" }), { status: 404 });
    }

    // Find valid recovery code
    const { data: recovery, error: recoveryError } = await supabase
      .from("recovery_codes")
      .select("*")
      .eq("teacher_id", teacher.id)
      .eq("code", recovery_code)
      .eq("used", false)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (recoveryError || !recovery) {
      return new Response(JSON.stringify({ error: "Invalid or expired recovery code" }), { status: 401 });
    }

    // Check attempt limit (3 attempts/hour)
    if (recovery.attempts >= 3) {
      return new Response(JSON.stringify({ error: "Too many attempts. Try again later." }), { status: 429 });
    }

    // Increment attempts
    await supabase
      .from("recovery_codes")
      .update({ attempts: recovery.attempts + 1 })
      .eq("id", recovery.id);

    // Hash new password
    const pepper = Deno.env.get("PASSWORD_PEPPER")!;
    const passwordHash = await bcrypt.hash(new_password + pepper);

    // Update teacher's password and mark recovery code as used
    await supabase
      .from("teachers")
      .update({
        password_hash: passwordHash,
        password_hash_version: teacher.password_hash_version + 1,
        force_password_reset: false,
      })
      .eq("id", teacher.id);

    await supabase
      .from("recovery_codes")
      .update({ used: true })
      .eq("id", recovery.id);

    return new Response(
      JSON.stringify({ message: "Password reset successful" }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});