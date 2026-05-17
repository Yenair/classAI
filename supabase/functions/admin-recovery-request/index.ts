import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const { email } = await req.json();

    if (!email) {
      return new Response(
        JSON.stringify({ error: "Missing required field: email" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── Look up admin by email in teachers table ───────────────────────────
    const { data: admin, error: adminError } = await supabase
      .from("teachers")
      .select("id, school_id, email")
      .eq("email", email)
      .eq("role", "admin")
      .maybeSingle();

    if (adminError || !admin) {
      return new Response(
        JSON.stringify({ error: "No admin account found with that email" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Generate 6-digit OTP ───────────────────────────────────────────────
    const otp = String(Math.floor(100000 + Math.random() * 900000));
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 minutes

    // Hash OTP for storage
    const otpHashBytes = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(otp)
    );
    const otpHash = Array.from(new Uint8Array(otpHashBytes))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // ── Store OTP in admin_recovery_otps table ────────────────────────────
    // Delete any existing unused OTPs for this email first
    await supabase
      .from("admin_recovery_otps")
      .delete()
      .eq("email", email)
      .eq("used", false);

    const { error: insertError } = await supabase
      .from("admin_recovery_otps")
      .insert({
        email,
        otp_hash: otpHash,
        expires_at: expiresAt.toISOString(),
        attempts: 0,
        used: false,
      });

    if (insertError) throw insertError;

    // ── Send OTP (log in dev; in production use email service) ─────────────
    // In production: use Resend / Termii / Supabase's built-in email
    console.log(`[admin-recovery-request] OTP for ${email}: ${otp}`);

    // For development, include OTP in response so devs can test
    const isDev = Deno.env.get("SUPABASE_ENV") === "dev" ||
      Deno.env.get("SUPABASE_ENV") === "local";

    return new Response(
      JSON.stringify({
        otp_sent: true,
        otp_expiry: expiresAt.toISOString(),
        ...(isDev ? { debug_otp: otp } : {}),
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
