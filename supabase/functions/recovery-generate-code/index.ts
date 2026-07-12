import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

serve(async (req) => {
  try {
    // ── 1. Extract and verify admin JWT ──────────────────────────────
    const authHeader = req.headers.get("Authorization") || "";
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

    const adminId = claims.teacher_id as string;
    const adminSchoolId = claims.school_id as string;
    if (!adminId || !adminSchoolId) {
      return new Response(
        JSON.stringify({ error: "Invalid token: missing teacher_id or school_id" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 2. Verify admin has admin role ────────────────────────────────
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: admin, error: adminError } = await supabase
      .from("teachers")
      .select("id, role")
      .eq("id", adminId)
      .eq("role", "admin")
      .maybeSingle();

    if (adminError || !admin) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: admin privileges required" }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 3. Parse body — only teacherEmail (NOT teacherId/adminId) ─────
    const body = await req.json().catch(() => ({}));
    const teacherEmail = body.teacher_email as string;

    if (!teacherEmail) {
      return new Response(
        JSON.stringify({ error: "Missing required field: teacher_email" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 4. Look up teacher by email, verify same school ───────────────
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("id, school_id, email")
      .eq("email", teacherEmail.toLowerCase())
      .maybeSingle();

    if (teacherError || !teacher) {
      return new Response(
        JSON.stringify({ error: "Teacher not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    if (teacher.school_id !== adminSchoolId) {
      return new Response(
        JSON.stringify({ error: "Teacher is not in your school" }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 5. Generate 12-character alphanumeric recovery code ───────────
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I, O, 0, 1 to avoid confusion
    let code = "";
    for (let i = 0; i < 12; i++) {
      code += chars.charAt(Math.floor(Math.random() * chars.length));
    }

    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours

    // ── 6. Store in recovery_codes table ──────────────────────────────
    const { error: insertError } = await supabase
      .from("recovery_codes")
      .insert({
        teacher_id: teacher.id,
        email: teacher.email,
        code,
        generated_by_admin_id: adminId,
        expires_at: expiresAt.toISOString(),
        used: false,
        attempts: 0,
      });

    if (insertError) throw insertError;

    return new Response(
      JSON.stringify({ recovery_code: code, expires_at: expiresAt.toISOString() }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
