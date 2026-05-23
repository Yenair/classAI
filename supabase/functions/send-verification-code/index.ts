import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts";
import nodemailer from "npm:nodemailer";

const JWT_SECRET = Deno.env.get("JWT_SECRET")!;

serve(async (req) => {
  // ── 1. Parse JWT and extract teacher_id + email ───────────────────────────
  let teacherId: string | null = null;
  let emailFromToken: string | null = null;

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid token." }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const claims = await verify(token, JWT_SECRET, "HS256");

    teacherId   = (claims as Record<string, unknown>).teacher_id as string;
    emailFromToken = (claims as Record<string, unknown>).sub as string;

    if (!teacherId || !emailFromToken) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid token." }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }
  } catch {
    return new Response(
      JSON.stringify({ error: "Missing or invalid token." }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  // ── 2. Generate 6-digit code ──────────────────────────────────────────────
  let code: string;
  try {
    code = crypto.randomInt(100000, 1000000).toString(); // 6-digit: 000000–999999
  } catch {
    console.error("[send-verification-code] crypto.randomInt failed:", new Error("crypto.randomInt threw"));
    return new Response(
      JSON.stringify({ error: "Failed to generate random code." }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const targetEmail    = emailFromToken.trim().toLowerCase();
  const expiresAt      = new Date(Date.now() + 15 * 60 * 1000); // +15 min
  const expiresAtISO   = expiresAt.toISOString();
  const supabase       = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // ── 3. Insert into verification_codes ────────────────────────────────────
  try {
    // Invalidate any previous unused codes for this email first
    await supabase
      .from("verification_codes")
      .update({ used: true })
      .eq("email", targetEmail)
      .eq("used", false);

    const { error: insertError } = await supabase
      .from("verification_codes")
      .insert({
        email:      targetEmail,
        code,
        expires_at: expiresAtISO,
        used:       false,
        attempts:   0,
      });

    if (insertError) {
      console.error(
        "[send-verification-code] Supabase insert error:",
        insertError
      );
      return new Response(
        JSON.stringify({
          error:    "Failed to store verification code.",
          detail:   insertError.message,
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  } catch (dbErr) {
    console.error(
      "[send-verification-code] Supabase connection or query error:",
      dbErr
    );
    return new Response(
      JSON.stringify({
        error:  "Failed to store verification code.",
        detail: (dbErr as Error).message,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // ── 4. Send email via Gmail SMTP ─────────────────────────────────────────
  {
    const gmailUser        = Deno.env.get("GMAIL_USER");
    const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");

    if (!gmailUser || !gmailAppPassword) {
      console.error(
        "[send-verification-code] GMAIL_USER or GMAIL_APP_PASSWORD not set in environment"
      );
      return new Response(
        JSON.stringify({ error: "Email credentials not configured." }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    let transporter: ReturnType<typeof nodemailer.createTransport>;

    try {
      transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: gmailUser,
          pass: gmailAppPassword,
        },
      });
    } catch (transportErr) {
      console.error(
        "[send-verification-code] Failed to create nodemailer transporter:",
        transportErr
      );
      return new Response(
        JSON.stringify({
          error:  "Failed to send email.",
          detail: (transportErr as Error).message,
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const appUrl = Deno.env.get("APP_URL") || "";

    try {
      await transporter.sendMail({
        from: gmailUser,
        to:   targetEmail,
        subject: "ClassAI Verification Code",
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
            <p>This code will expire in 15 minutes.</p>
            <p><strong>Please check your spam/junk folder if you don't see it in your inbox.</strong></p>
            ${appUrl ? `<p style="color: #999; font-size: 11px; margin-top: 32px;">ClassAI – ${appUrl}</p>` : ""}
          </div>
        `,
      });
      console.log(
        "[send-verification-code] Verification email sent to",
        targetEmail
      );
    } catch (emailErr) {
      console.error(
        "[send-verification-code] Failed to send email via Gmail SMTP:",
        emailErr
      );
      return new Response(
        JSON.stringify({
          error:  "Failed to send email.",
          detail: (emailErr as Error).message,
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // ── 5. Success ───────────────────────────────────────────────────────────
  return new Response(
    JSON.stringify({
      success:      true,
      teacher_id:   teacherId,
      email:        targetEmail,
      message:      "Verification code sent successfully.",
      expires_at:   expiresAtISO,
      ...(Deno.env.get("DEBUG") === "true"
        ? {
            code,
            debug_note:
              "Dev-only: code returned for testing (expires in 15 minutes).",
          }
        : {}),
    }),
    { headers: { "Content-Type": "application/json" } }
  );
});
