import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// confirm-payment Edge Function
//
// Called after a successful Paystack payment to:
//   1. Verify the transaction with Paystack server-to-server
//   2. Generate a unique activation code (receipt)
//   3. Update the school's subscription_tier, expiry_date, and activation_code
//   4. Return the activation code to the client
// ---------------------------------------------------------------------------

const PAYSTACK_BASE = "https://api.paystack.co";

serve(async (req) => {
  try {
    const { reference, plan, school_id } = await req.json();

    if (!reference || !plan || !school_id) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: reference, plan, school_id",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const paystackSecretKey = Deno.env.get("PAYSTACK_SECRET_KEY");
    if (!paystackSecretKey) {
      return new Response(
        JSON.stringify({ error: "Paystack secret key not configured" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 1. Verify the transaction with Paystack ─────────────────────────
    const verifyResponse = await fetch(
      `${PAYSTACK_BASE}/transaction/verify/${encodeURIComponent(reference)}`,
      {
        headers: {
          Authorization: `Bearer ${paystackSecretKey}`,
          "Content-Type": "application/json",
        },
      },
    );

    if (!verifyResponse.ok) {
      return new Response(
        JSON.stringify({
          error: `Paystack verification failed: ${verifyResponse.statusText}`,
        }),
        { status: 502, headers: { "Content-Type": "application/json" } },
      );
    }

    const verifyData = await verifyResponse.json();
    const txStatus = verifyData?.data?.status;

    if (txStatus !== "success") {
      return new Response(
        JSON.stringify({
          error: `Payment not successful. Status: ${txStatus ?? "unknown"}`,
        }),
        { status: 402, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 2. Generate activation code ─────────────────────────────────────
    // Format: CLASS-XXXX-XXXX-XXXX (uppercase alphanumeric)
    function randomGroup(length: number): string {
      const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I/O/0/1 for clarity
      let result = "";
      for (let i = 0; i < length; i++) {
        result += chars.charAt(Math.floor(Math.random() * chars.length));
      }
      return result;
    }

    const activationCode = `CLASS-${randomGroup(4)}-${randomGroup(4)}-${randomGroup(4)}`;

    // ── 3. Calculate expiry date (30 days from now) ─────────────────────
    const now = new Date();
    const expiryDate = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);

    // ── 4. Update the school record in Supabase ─────────────────────────
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { error: updateError } = await supabase
      .from("schools")
      .update({
        subscription_tier: plan,
        expiry_date: expiryDate.toISOString(),
        activation_code: activationCode,
        updated_at: now.toISOString(),
      })
      .eq("id", school_id);

    if (updateError) {
      console.error("confirm-payment: update error", updateError.message);
      return new Response(
        JSON.stringify({ error: `Failed to update school: ${updateError.message}` }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // ── 5. Return success with activation code ──────────────────────────
    return new Response(
      JSON.stringify({
        activation_code: activationCode,
        subscription_tier: plan,
        expiry_date: expiryDate.toISOString(),
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
