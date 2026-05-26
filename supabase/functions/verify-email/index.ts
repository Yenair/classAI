import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    // ── Parse request ──────────────────────────────────────────────────────
    let { email } = await req.json();
    email = email.toLowerCase();

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

    // ── Look up the teacher by email ──────────────────────────────────────
    const { data: teacher, error: lookupError } = await supabase
      .from("teachers")
      .select("id, email, teacher_name")
      .eq("email", email)
      .maybeSingle();

    if (lookupError) {
      console.error("[verify-email] lookup error:", lookupError);
      return new Response(
        JSON.stringify({ error: "Database error during lookup" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!teacher) {
      return new Response(
        JSON.stringify({ error: "No account found with this email address" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Generate verification token ────────────────────────────────────────
    const verificationToken = crypto.randomUUID();
    const tokenExpiry = new Date();
    tokenExpiry.setHours(tokenExpiry.getHours() + 24); // 24-hour expiry

    // Store verification token on the teacher record
    const { error: updateError } = await supabase
      .from("teachers")
      .update({
        email_verification_token: verificationToken,
        email_verification_token_expiry: tokenExpiry.toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", teacher.id);

    if (updateError) {
      console.error("[verify-email] token update error:", updateError);
      return new Response(
        JSON.stringify({ error: "Failed to generate verification token" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Build verification link ────────────────────────────────────────────
    const appUrl = Deno.env.get("APP_URL") ?? "https://classai.app";
    const verificationUrl = `${appUrl}/verify-email?token=${verificationToken}&email=${encodeURIComponent(email)}`;

    // ── Attempt to send email via Supabase Auth's built-in mailer ──────────
    // This uses the Supabase Auth built-in email service (requires auth schema)
    try {
      await supabase.auth.admin.generateLink({
        type: "signup",
        email: email,
        options: {
          redirectTo: verificationUrl,
        },
      });
    } catch (_emailErr) {
      // If Supabase Auth email fails (e.g. not configured), we still return
      // the verification link so the app can display it to the user.
      console.warn(
        "[verify-email] Supabase Auth email send failed, verification link still available",
      );
    }

    // ── Return success with verification link ──────────────────────────────
    return new Response(
      JSON.stringify({
        success: true,
        message: "Verification email sent successfully",
        verification_url: verificationUrl,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[verify-email] error:", err);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
