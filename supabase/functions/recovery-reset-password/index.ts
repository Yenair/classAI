import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as bcrypt from "https://deno.land/x/bcrypt@v0.4.1/mod.ts";

serve(async (req) => {
  try {
    const { email, recoveryCode, newPassword } = await req.json();

    if (!email || !recoveryCode || !newPassword) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: email, recoveryCode, newPassword" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── Find teacher by email ──────────────────────────────────────────────
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("id, school_id, email, password_hash_version")
      .eq("email", email)
      .maybeSingle();

    if (teacherError || !teacher) {
      return new Response(
        JSON.stringify({ error: "No account found with that email" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Find valid recovery code ──────────────────────────────────────────
    const { data: recovery, error: recoveryError } = await supabase
      .from("recovery_codes")
      .select("*")
      .eq("teacher_id", teacher.id)
      .eq("code", recoveryCode)
      .eq("used", false)
      .maybeSingle();

    if (recoveryError || !recovery) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired recovery code" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Check expiry ──────────────────────────────────────────────────────
    if (recovery.expires_at && new Date(recovery.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({ error: "Recovery code has expired" }),
        { status: 410, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Check attempt limit (3 attempts per code) ─────────────────────────
    if (recovery.attempts >= 3) {
      return new Response(
        JSON.stringify({ error: "Too many failed attempts. Request a new recovery code from your admin." }),
        { status: 429, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Increment attempts ────────────────────────────────────────────────
    await supabase
      .from("recovery_codes")
      .update({ attempts: recovery.attempts + 1 })
      .eq("id", recovery.id);

    // ── Update password in Supabase Auth ───────────────────────────────────
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
    const passwordHash = await bcrypt.hash(newPassword + pepper);

    const newVersion = (teacher.password_hash_version || 1) + 1;
    await supabase
      .from("teachers")
      .update({
        password_hash: passwordHash,
        password_hash_version: newVersion,
        force_password_reset: false,
      })
      .eq("id", teacher.id);

    // ── Mark recovery code as used ─────────────────────────────────────────
    await supabase
      .from("recovery_codes")
      .update({ used: true })
      .eq("id", recovery.id);

    // ── Fetch updated teacher and school ───────────────────────────────────
    const { data: updatedTeacher } = await supabase
      .from("teachers")
      .select("*, schools(*)")
      .eq("id", teacher.id)
      .single();

    const t = updatedTeacher;
    const school = t?.schools as Record<string, unknown> | undefined;

    return new Response(
      JSON.stringify({
        teacher: {
          id: t.id,
          email: t.email,
          name: t.teacher_name,
          role: t.role,
          school_id: t.school_id,
        },
        school: {
          id: school?.id,
          name: school?.school_name,
          subscription_tier: school?.subscription_tier,
        },
        wrapped_school_key: school?.school_master_key_wrapped ?? null,
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
