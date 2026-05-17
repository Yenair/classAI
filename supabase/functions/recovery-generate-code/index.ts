import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    // Expect auth context from JWT (function is called by an authenticated admin)
    const authHeader = req.headers.get("Authorization") || "";
    const { teacherId, adminId } = await req.json();

    if (!teacherId || !adminId) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: teacherId, adminId" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── Verify admin exists and has admin role ─────────────────────────────
    const { data: admin, error: adminError } = await supabase
      .from("teachers")
      .select("id, school_id, role")
      .eq("id", adminId)
      .single();

    if (adminError || !admin || admin.role !== "admin") {
      return new Response(
        JSON.stringify({ error: "Unauthorized: admin privileges required" }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Verify teacher exists and belongs to same school ───────────────────
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("id, school_id, email")
      .eq("id", teacherId)
      .single();

    if (teacherError || !teacher) {
      return new Response(
        JSON.stringify({ error: "Teacher not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    if (teacher.school_id !== admin.school_id) {
      return new Response(
        JSON.stringify({ error: "Teacher is not in your school" }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Generate 12-character alphanumeric recovery code ──────────────────
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I, O, 0, 1 to avoid confusion
    let code = "";
    for (let i = 0; i < 12; i++) {
      code += chars.charAt(Math.floor(Math.random() * chars.length));
    }

    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours

    // ── Store in recovery_codes table ──────────────────────────────────────
    // Check if the existing server-side recovery_codes has email column
    const { error: insertError } = await supabase
      .from("recovery_codes")
      .insert({
        teacher_id: teacherId,
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
