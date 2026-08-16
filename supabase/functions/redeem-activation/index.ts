import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

const CODE_PATTERN = /^CLA-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/i;

// Tier rank order — free is the implicit baseline. Higher rank = better plan.
const TIER_RANKS: Record<string, number> = {
  free: 0,
  basic: 1,
  standard: 2,
  elite: 3,
};

function tierRank(tier: string): number {
  return TIER_RANKS[tier.toLowerCase()] ?? -1;
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    // ── 1. Extract and verify JWT ──────────────────────────────────
    const token = req.headers.get("x-classai-jwt")?.trim() ?? "";
    if (!token) {
      return jsonResponse({ error: "Missing authentication token" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const jwtSecret = Deno.env.get("JWT_SECRET");

    if (!supabaseUrl || !serviceRoleKey || !jwtSecret) {
      return jsonResponse({ error: "Server misconfiguration" }, 500);
    }

    let claims: Record<string, unknown>;
    try {
      claims = await validateTokenVersion(token, supabaseUrl, serviceRoleKey, jwtSecret);
    } catch (err) {
      const e = err as { error: string; code: string; status: number };
      return jsonResponse({ error: e.error, code: e.code }, e.status ?? 401);
    }

    const teacherId = claims.teacher_id as string;
    const jwtSchoolId = claims.school_id as string;
    if (!teacherId || !jwtSchoolId) {
      return jsonResponse({ error: "Invalid token: missing teacher_id or school_id" }, 401);
    }

    // ── 2. Verify admin role ───────────────────────────────────────
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("role")
      .eq("id", teacherId)
      .maybeSingle();

    if (teacherError || !teacher) {
      return jsonResponse({ error: "Teacher not found" }, 404);
    }

    if (teacher.role !== "admin") {
      return jsonResponse({ error: "Admin access required" }, 403);
    }

    // ── 3. Parse body — only accept code from body ─────────────────
    const body = await req.json().catch(() => ({}));
    const activationCodeInput =
      body.code ?? body.activation_code ?? body.activationCode;

    if (!activationCodeInput || typeof activationCodeInput !== "string") {
      return jsonResponse(
        { error: "Missing required field: code" },
        400,
      );
    }

    const normalizedCode = activationCodeInput.trim().toUpperCase();
    if (!CODE_PATTERN.test(normalizedCode)) {
      return jsonResponse(
        { error: "Invalid activation code format" },
        400,
      );
    }

    const now = new Date();

    // ── 4. Fetch the activation code (only unused) ─────────────────
    const { data: activationRow, error: activationError } = await supabase
      .from("activation_codes")
      .select("code, school_id, tier, duration_days")
      .eq("code", normalizedCode)
      .eq("used", false)
      .maybeSingle();

    if (activationError || !activationRow) {
      return jsonResponse(
        { error: "Invalid or already used activation code." },
        400,
      );
    }

    // ── 5. Verify school_id matches the caller's school ────────────
    if (activationRow.school_id !== jwtSchoolId) {
      return jsonResponse(
        { error: "This activation code does not belong to your school." },
        403,
      );
    }

    // ── 6. DOWNGRADE GUARD: never downgrade a higher tier ──────────
    // An old lower-tier activation code (e.g., Basic) redeemed on a school
    // that already has a higher tier (e.g., Elite) must not overwrite it.
    // Reject before writing anything: no code marked used, no school update,
    // no email. Same-tier renewals/extensions and upgrades still pass.
    const { data: currentSchoolRow } = await supabase
      .from("schools")
      .select("subscription_tier")
      .eq("id", activationRow.school_id)
      .maybeSingle();

    const currentTier = typeof currentSchoolRow?.subscription_tier === "string"
      ? currentSchoolRow.subscription_tier.toLowerCase()
      : "free";
    const currentRank = tierRank(currentTier);
    const incomingRank = typeof activationRow.tier === "string"
      ? tierRank(activationRow.tier)
      : -1;

    if (incomingRank < currentRank) {
      return jsonResponse(
        {
          error: `Cannot downgrade subscription from ${currentTier} to ${activationRow.tier}. Your current ${currentTier} plan remains active.`,
          code: "DOWNGRADE_REJECTED",
          current_subscription_tier: currentTier,
        },
        409,
      );
    }

    // ── 7. MARK-FIRST: mark code used, then update school ──────────
    const durationDays = activationRow.duration_days ?? 365;
    const expiryDate = new Date(
      now.getTime() + durationDays * 24 * 60 * 60 * 1000,
    );

    // Mark code as used FIRST (conditional on used=false for concurrency safety)
    const { data: markResult, error: markUsedError } = await supabase
      .from("activation_codes")
      .update({
        used: true,
        redeemed_at: now.toISOString(),
      })
      .eq("code", activationRow.code)
      .eq("used", false)
      .select("code")
      .maybeSingle();

    if (markUsedError || !markResult) {
      return jsonResponse(
        { error: "Activation code was already redeemed by another request." },
        409,
      );
    }

    // Then update the school record
    const { error: updateSchoolError } = await supabase
      .from("schools")
      .update({
        subscription_tier: activationRow.tier,
        expiry_date: expiryDate.toISOString(),
        activation_code: activationRow.code,
        updated_at: now.toISOString(),
      })
      .eq("id", activationRow.school_id);

    if (updateSchoolError) {
      // Rollback: revert the code marking
      await supabase
        .from("activation_codes")
        .update({
          used: false,
          redeemed_at: null,
        })
        .eq("code", activationRow.code);

      return jsonResponse(
        { error: `Failed to update school: ${updateSchoolError.message}` },
        500,
      );
    }

    return jsonResponse({
      success: true,
      subscription_tier: activationRow.tier,
      expiry_date: expiryDate.toISOString(),
      activation_code: activationRow.code,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: message }, 500);
  }
});
