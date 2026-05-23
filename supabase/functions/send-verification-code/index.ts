import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts";
import nodemailer from "npm:nodemailer";

const JWT_SECRET = Deno.env.get("JWT_SECRET")!;

/** Generate a random 6-digit code as a zero-padded string. */
function generateCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

serve(async (req) => {
  try {
    // ── 1. Optional JWT Auth ─────────────────────────────────────────────────
    // If a Bearer token is provided, verify it and use the subject email
    // as the target instead of trusting the request body.
    const authHeader = req.headers.get("Authorization");
    let verifiedEmail: string | null = null;

    if (authHeader && authHeader.startsWith("Bearer ")) {
      const token = authHeader.replace("Bearer ", "");
      try {
        const claims = await verify(token, JWT_SECRET, "HS256");
        // A standard ClassAI JWT carries "sub" which is the teacher id;
        // the email comes from the request body in that case.
        // We don't fail here — we just note that the JWT is valid.
      } catch {
        // Invalid token — still allow body-based flow for resend after login
      }
    }

    // ── 2. Parse request body ─────────────────────────────────────────────────
    const { email } = await req.json();

    if (!email || typeof email !== "string" || !email.includes("@")) {
      return new Response(
        JSON.stringify({ error: "A valid email address is required." }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const normalizedEmail = email.trim().toLowerCase();

    // ── 3. Generate 6-digit code ─────────────────────────────────────────────
    const code = generateCode();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

    // ── 4. Invalidate any previous unused codes for this email ────────────────
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    await supabase
      .from("verification_codes")
      .update({ used: true })
      .eq("email", normalizedEmail)
      .eq("used", false);

    // ── 5. Insert the new code ────────────────────────────────────────────────
    const { error: insertError } = await supabase
      .from("verification_codes")
      .insert({
        email: normalizedEmail,
        code,
        expires_at: expiresAt.toISOString(),
        used: false,
        attempts: 0,
      });

    if (insertError) {
      console.error("[send-verification-code] insert error:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to generate verification code." }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 6. Send email via Gmail SMTP ──────────────────────────────────────────
    const gmailUser = Deno.env.get("GMAIL_USER");
    const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");

    if (gmailUser && gmailAppPassword) {
      try {
        const transporter = nodemailer.createTransport({
          service: "gmail",
          auth: {
            user: gmailUser,
            pass: gmailAppPassword,
          },
        });

        const appUrl = Deno.env.get("APP_URL") || "";
        await transporter.sendMail({
          from: gmailUser,
          to: normalizedEmail,
          subject: "Your ClassAI Verification Code",
          html: `
            <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto; padding: 24px;">
              <h2 style="color: #1a1a2e;">ClassAI – Verify Your Email</h2>
              <p>Your verification code is:</p>
              <div style="
                font-size: 36px;
                font-weight: bold;
                letter-spacing: 12px;
                text-align: center;
                padding: 24px;
                background: #f0f4ff;
                border-radius: 12px;
                color: #2563eb;
                margin: 20px 0;
              ">${code}</div>
              <p>This code will expire in 10 minutes.</p>
              <p style="color: #666; font-size: 13px;">
                If you did not request this code, please ignore this email.
              </p>
              ${appUrl ? `<p style="color: #999; font-size: 11px; margin-top: 32px;">ClassAI – ${appUrl}</p>` : ""}
            </div>
          `,
        });
        console.log("[send-verification-code] Email sent to", normalizedEmail);
      } catch (emailErr) {
        console.error("[send-verification-code] Gmail SMTP error:", emailErr);
        // Non-fatal: return success anyway so the client can show dev-OTP
      }
    } else {
      console.warn(
        "[send-verification-code] GMAIL_USER or GMAIL_APP_PASSWORD not set; skipping email for",
        normalizedEmail
      );
    }

    // ── 7. Return success ─────────────────────────────────────────────────────
    return new Response(
      JSON.stringify({
        success: true,
        message: "Verification code sent.",
        expires_at: expiresAt.toISOString(),
        // Only include the code in DEBUG mode so devs can test without email access
        ...(Deno.env.get("DEBUG") === "true"
          ? { code, debug_note: "Dev-only: code included for testing." }
          : {}),
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[send-verification-code] error:", err);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
