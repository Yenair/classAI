import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// redeem-activation Edge Function
//
// Validates and redeems an activation code for a school.
// Called by school admins to manually activate a subscription.
//
// Request body:
//   activation_code (string, required) – The code to redeem
//
// Response:
//   success: true
//   subscription_tier: string
//   expiry_date: string (ISO 8601)
//
// The caller's JWT is used to determine which school to update.
// ---------------------------------------------------------------------------

serve(async (req) => {
  try {
    const { activation_code } = await req.json();

    if (!activation_code || typeof activation_code !== "string") {
      return new Response(
        JSON.stringify({ error: "Missing required field: activation_code" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 1. Validate activation code format: CLASS-XXXX-XXXX-XXXX ────────────
    const codePattern = /^CLASS-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/;
    if (!codePattern.test(activation_code.trim().toUpperCase())) {
      return new Response(
        JSON.stringify({ error: "Invalid activation code format" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const normalizedCode = activation_code.trim().toUpperCase();

    // ── 2. Get the caller's school_id from the JWT ─────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace("Bearer ", "");

    if (!jwt) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    // Decode the JWT payload (base64) to extract the school_id.
    let schoolId: string;
    try {
      const parts = jwt.split(".");
      if (parts.length !== 3) {
        throw new Error("Invalid JWT format");
      }
      const payload = JSON.parse(
        new TextDecoder().decode(
          Uint8Array.from(atob(parts[1]), (c) => c.charCodeAt(0)),
        ),
      );
      schoolId = payload.school_id;
      if (!schoolId) {
        throw new Error("No school_id in token");
      }
    } catch {
      return new Response(
        JSON.stringify({ error: "Unable to extract school_id from token" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 3. Look up the school ──────────────────────────────────────────────
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: school, error: schoolError } = await supabase
      .from("schools")
      .select("id, subscription_tier, activation_code")
      .eq("id", schoolId)
      .single();

    if (schoolError || !school) {
      return new Response(
        JSON.stringify({ error: "School not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 4. Check if already activated at the same or higher tier ────────────
    if (school.activation_code === normalizedCode) {
      return new Response(
        JSON.stringify({
          error: "This activation code has already been redeemed for this school",
        }),
        { status: 409, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 5. Apply the subscription upgrade (premium, 365 days from now) ──────
    const now = new Date();
    const expiryDate = new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000);

    const { error: updateError } = await supabase
      .from("schools")
      .update({
        subscription_tier: "premium",
        expiry_date: expiryDate.toISOString(),
        activation_code: normalizedCode,
        updated_at: now.toISOString(),
      })
      .eq("id", schoolId);

    if (updateError) {
      console.error("redeem-activation: update error", updateError.message);
      return new Response(
        JSON.stringify({ error: `Failed to update school: ${updateError.message}` }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 6. Return success ──────────────────────────────────────────────────
    return new Response(
      JSON.stringify({
        success: true,
        subscription_tier: "premium",
        expiry_date: expiryDate.toISOString(),
        activation_code: normalizedCode,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
