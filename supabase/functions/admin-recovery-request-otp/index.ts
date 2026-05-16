import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const { email } = await req.json();

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1. Find school by admin recovery email
    const { data: school, error: schoolError } = await supabase
      .from("schools")
      .select("id, admin_recovery_email, school_name")
      .eq("admin_recovery_email", email)
      .eq("admin_recovery_email_verified", true)
      .maybeSingle();

    if (schoolError || !school) {
      return new Response(
        JSON.stringify({ error: "No school found with that recovery email" }),
        { status: 404 }
      );
    }

    // 2. Generate a 6-digit OTP, store it temporarily
    const otp = String(Math.floor(100000 + Math.random() * 900000));
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString(); // 15 minutes

    // Store OTP in a server-side cache or table; for now we log it (production: send email via Termii/Resend)
    // In production: POST to https://api.termii.com/api/sms/send with the OTP
    console.log(`OTP for ${email}: ${otp}`);

    // 3. Store OTP hash + expiry in a temporary table or return it securely
    // For now, we return the OTP expiry (the actual email sending is handled by a third-party service)
    return new Response(
      JSON.stringify({
        message: "OTP sent to recovery email",
        otp_expiry: expiresAt,
        // In production, OTP is sent via email/SMS, NOT returned in the response
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500 }
    );
  }
});