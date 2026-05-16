import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const { admin_id, teacher_id } = await req.json();
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Verify admin belongs to the same school as the teacher
    const { data: admin, error: adminError } = await supabase
      .from("teachers")
      .select("school_id, role")
      .eq("id", admin_id)
      .single();
    if (adminError || admin?.role !== "admin") {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 403 });
    }

    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("school_id")
      .eq("id", teacher_id)
      .single();
    if (teacherError || teacher.school_id !== admin.school_id) {
      return new Response(JSON.stringify({ error: "Teacher not in your school" }), { status: 403 });
    }

    // Generate a random 16-char alphanumeric code
    const code = Array.from(crypto.getRandomValues(new Uint8Array(8)))
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(); // 24 hours

    const { error: insertError } = await supabase
      .from("recovery_codes")
      .insert({
        teacher_id,
        code,
        generated_by_admin_id: admin_id,
        expires_at: expiresAt,
      });
    if (insertError) throw insertError;

    return new Response(
      JSON.stringify({ code, expires_at: expiresAt }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});