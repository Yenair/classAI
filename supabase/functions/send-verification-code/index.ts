import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts";
import nodemailer from "npm:nodemailer";

serve(async (req) => {
  // ── a) Parse JWT and extract teacher_id, email ─────────────────────────────
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
    console.log("Received token:", token.substring(0, 30) + "...");

    const jwtSecret = Deno.env.get("JWT_SECRET");
    if (!jwtSecret) {
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: JWT_SECRET not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    let payload;
    try {
      payload = await verify(token, jwtSecret, "HS256");
    } catch (error: any) {
      return new Response(
        JSON.stringify({ error: "Invalid JWT", detail: error.message }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    console.log("JWT verified for teacher:", (payload as Record<string, unknown>).teacher_id);

    teacherId = (payload as Record<string, unknown>).teacher_id as string;
    emailFromToken = (payload as Record<string, unknown>).sub as string;

    if (!teacherId || !emailFromToken) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid token." }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }
  } catch (error: any) {
    return new Response(
      JSON.stringify({ error: "Invalid or expired token.", detail: error.message }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  // ── b) Generate 6-digit code ─────────────────────────────────────────────
  let code: string;
  try {
    code = crypto.randomInt(100000, 1000000).toString().padStart(6, "0");
  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: "Failed to generate random code.", detail: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const targetEmail = emailFromToken.trim().toLowerCase();
  const expiresAtISO = new Date(Date.now() + 15 * 60 * 1000).toISOString();

  // ── c) Insert into verification_codes table ───────────────────────────────
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

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
        email: targetEmail,
        code,
        expires_at: expiresAtISO,
        used: false,
        attempts: 0,
      });

    if (insertError) {
      throw new Error(insertError.message);
    }
  } catch (dbErr: any) {
    return new Response(
      JSON.stringify({
        error: "Failed to store verification code.",
        detail: dbErr.message,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // ── d) Send email via Gmail SMTP ─────────────────────────────────────────
  const gmailUser = Deno.env.get("GMAIL_USER");
  const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");

  if (!gmailUser || !gmailAppPassword) {
    return new Response(
      JSON.stringify({ error: "Email credentials not configured." }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const appUrl = Deno.env.get("APP_URL") || "";

  try {
    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: gmailUser,
        pass: gmailAppPassword,
      },
    });

    await transporter.sendMail({
      from: gmailUser,
      to: targetEmail,
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
  } catch (emailErr: any) {
    return new Response(
      JSON.stringify({
        error: "Failed to send email.",
        detail: emailErr.message,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // ── e) Return success ─────────────────────────────────────────────────────
  return new Response(
    JSON.stringify({ success: true }),
    { headers: { "Content-Type": "application/json" } }
  );
});