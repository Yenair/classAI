import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CODE_PATTERN = /^CLA-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/i;

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

    const body = await req.json();
    const activationCodeInput =
      body.code ?? body.activation_code ?? body.activationCode;
    const emailInput = body.email;
    const schoolNameInput = body.school_name;

    if (
      !activationCodeInput || typeof activationCodeInput !== "string" ||
      !emailInput || typeof emailInput !== "string" ||
      !schoolNameInput || typeof schoolNameInput !== "string"
    ) {
      return jsonResponse(
        {
          error:
            "Missing required fields: code, email, school_name",
        },
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

    const normalizedEmail = emailInput.trim().toLowerCase();
    const normalizedSchoolName = schoolNameInput.trim();
    const now = new Date();

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

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

    const { data: school, error: schoolError } = await supabase
      .from("schools")
      .select("id, school_name")
      .eq("id", activationRow.school_id)
      .maybeSingle();

    if (
      schoolError || !school ||
      school.school_name.trim().toLowerCase() !== normalizedSchoolName.toLowerCase()
    ) {
      return jsonResponse(
        { error: "This activation code does not match the provided school." },
        403,
      );
    }

    const { data: adminTeacher, error: adminError } = await supabase
      .from("teachers")
      .select("id, school_id, email, role")
      .eq("email", normalizedEmail)
      .eq("role", "admin")
      .maybeSingle();

    if (adminError || !adminTeacher) {
      return jsonResponse(
        { error: "Admin account not found for the provided email." },
        404,
      );
    }

    if (adminTeacher.school_id !== activationRow.school_id) {
      return jsonResponse(
        { error: "This admin does not belong to the activation code school." },
        403,
      );
    }

    const durationDays = activationRow.duration_days ?? 365;
    const expiryDate = new Date(
      now.getTime() + durationDays * 24 * 60 * 60 * 1000,
    );

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
      return jsonResponse(
        { error: `Failed to update school: ${updateSchoolError.message}` },
        500,
      );
    }

    const { error: markUsedError } = await supabase
      .from("activation_codes")
      .update({
        used: true,
        redeemed_at: now.toISOString(),
      })
      .eq("code", activationRow.code)
      .eq("used", false);

    if (markUsedError) {
      return jsonResponse(
        {
          error: `Failed to finalize activation code: ${markUsedError.message}`,
        },
        500,
      );
    }

    return jsonResponse({
      success: true,
      subscription_tier: activationRow.tier,
      expiry_date: expiryDate.toISOString(),
      activation_code: activationRow.code,
      tier: activationRow.tier,
      expiry: expiryDate.toISOString(),
      code: activationRow.code,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: message }, 500);
  }
});
