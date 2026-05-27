import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

serve(async (req) => {
  try {
    // ── 1. Validate JWT and token_version ──────────────────────────────────
    const jwtSecret = Deno.env.get("JWT_SECRET");
    if (!jwtSecret) {
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: JWT_SECRET not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const classaiJwt = req.headers.get("x-classai-jwt");
    if (!classaiJwt) {
      return new Response(
        JSON.stringify({ error: "Missing authentication token" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    let claims: Record<string, unknown>;
    try {
      claims = await validateTokenVersion(
        classaiJwt,
        supabaseUrl,
        serviceRoleKey,
        jwtSecret,
      );
    } catch (err) {
      const { error, code, status } = err as { error: string; code: string; status: number };
      return new Response(
        JSON.stringify({ error, code }),
        { status, headers: { "Content-Type": "application/json" } }
      );
    }

    const teacherId = claims.teacher_id as string;
    if (!teacherId) {
      return new Response(
        JSON.stringify({ error: "Invalid token: no teacher_id claim" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 2. Parse optional device_id from body ──────────────────────────────
    let deviceId: string | undefined;
    try {
      const body = await req.json();
      deviceId = body.device_id as string | undefined;
    } catch {
      // No body — that's fine, device check is optional
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // ── 3. Fetch teacher with school data ──────────────────────────────────
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("*, schools(id, school_name, school_master_key_wrapped, subscription_tier)")
      .eq("id", teacherId)
      .maybeSingle();

    if (teacherError || !teacher) {
      return new Response(
        JSON.stringify({ error: "Teacher not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 4. If device_id provided, check device is registered ───────────────
    if (deviceId) {
      const { data: device } = await supabase
        .from("teacher_devices")
        .select("id")
        .eq("teacher_id", teacherId)
        .eq("device_id", deviceId)
        .eq("is_active", true)
        .maybeSingle();

      if (!device) {
        return new Response(
          JSON.stringify({
            valid: false,
            error: "Device not registered",
            code: "device_not_registered",
          }),
          { status: 401, headers: { "Content-Type": "application/json" } }
        );
      }
    }

    // ── 5. Return teacher info ─────────────────────────────────────────────
    const school = teacher.schools;
    return new Response(
      JSON.stringify({
        valid: true,
        teacher: {
          id: teacher.id,
          email: teacher.email,
          name: teacher.teacher_name,
          role: teacher.role,
          school_id: teacher.school_id,
          email_verified: teacher.email_verified ?? false,
        },
        school: {
          id: school.id,
          name: school.school_name,
          subscription_tier: school.subscription_tier,
        },
        wrapped_school_key: school.school_master_key_wrapped,
        force_password_reset: teacher.force_password_reset ?? false,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[validate-session] error:", err);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
