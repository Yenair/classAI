import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer";

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

    // Fetch school name for the email subject
    const schoolName = await getSchoolName(supabase, admin.school_id);

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

    // ── Send OTP via Gmail SMTP ────────────────────────────────────────────
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
        await transporter.sendMail({
          from: gmailUser,
          to: email,
          subject: "ClassAI Admin Recovery OTP",
          html: `
            <h2>ClassAI Admin Recovery</h2>
            <p>A password recovery request was made for the <strong>${schoolName}</strong> admin account associated with this email.</p>
            <p>Your OTP is:</p>
            <h1 style="letter-spacing: 6px; font-size: 32px; background: #f4f4f4; padding: 12px 24px; border-radius: 8px; text-align: center;">${otp}</h1>
            <p>This code expires in <strong>15 minutes</strong>.</p>
            <p>If you did not request this recovery, please ignore this email.</p>
            <p><strong>If you don't see this email, please check your spam/junk folder.</strong></p>
            <p>Best regards,<br/>The ClassAI Team</p>
          `,
        });
        console.log("[admin-recovery-request] OTP email sent to", email);
      } catch (emailErr) {
        console.error("[admin-recovery-request] Gmail SMTP error:", emailErr);
        // Non-fatal: OTP was stored, email delivery failed
      }
    } else {
      console.warn(
        "[admin-recovery-request] GMAIL_USER or GMAIL_APP_PASSWORD not set; skipping email for",
        email
      );
    }

    // Log OTP to console regardless (useful for debugging)
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

/// Helper: fetch the school name for the email subject.
async function getSchoolName(
  supabase: ReturnType<typeof createClient>,
  schoolId: string
): Promise<string> {
  const { data } = await supabase
    .from("schools")
    .select("school_name")
    .eq("id", schoolId)
    .single();
  return data?.school_name ?? "ClassAI";
}
