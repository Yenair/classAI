import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

serve(async (req) => {
  try {
    // ── 1. Authenticate ──────────────────────────────────────────────────
    const jwt = req.headers.get("x-classai-jwt");
    if (!jwt) {
      return new Response(
        JSON.stringify({ error: "Missing authentication token" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const jwtSecret = Deno.env.get("JWT_SECRET") ?? "";

    let claims: Record<string, unknown>;
    try {
      claims = await validateTokenVersion(jwt, supabaseUrl, serviceRoleKey, jwtSecret);
    } catch (err) {
      const error = err as { error?: string; code?: string; status?: number };
      return new Response(
        JSON.stringify({ error: error.error ?? "Invalid token", code: error.code }),
        { status: error.status ?? 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const teacherId = claims.teacher_id as string;
    const schoolId = claims.school_id as string;

    // ── 2. Fetch school credit info ──────────────────────────────────────
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Get the teacher record for last_credit_refill_date
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("last_credit_refill_date")
      .eq("id", teacherId)
      .maybeSingle();

    if (teacherError || !teacher) {
      return new Response(
        JSON.stringify({ error: "Teacher not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 3. Return current credit state ───────────────────────────────────
    // Currently credits are a flat 3 allowance per device.
    // This will be extended with a proper credit table later.
    //
    // R1: also return the school's subscription tier so clients can derive
    // the correct daily credit allowance. Legacy fields are kept for
    // backward compatibility with older clients (plan R2 removes them).
    const { data: school, error: schoolError } = await supabase
      .from("schools")
      .select("subscription_tier")
      .eq("id", schoolId)
      .maybeSingle();

    if (schoolError || !school) {
      return new Response(
        JSON.stringify({ error: "School not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({
        offline_credits: 3,
        credit_server_counter: 0,
        spent_ids: "[]",
        subscription_tier: school.subscription_tier ?? "free",
        last_credit_refill_server_time: teacher.last_credit_refill_date?.toISOString() ?? new Date().toISOString(),
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: `Internal error: ${err instanceof Error ? err.message : String(err)}` }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
