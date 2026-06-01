import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import nodemailer from "npm:nodemailer";
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts";

/** Convert a plain string secret into a CryptoKey for HS256 JWT signing. */
function getHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

serve(async (req) => {
  try {
    const JWT_SECRET = Deno.env.get("JWT_SECRET");
    if (!JWT_SECRET) {
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: JWT_SECRET not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    let { school_name, admin_email, admin_password, recovery_email } =
      await req.json();
    admin_email = admin_email.toLowerCase();

    // ── Validate required fields ──────────────────────────────────────────
    if (!school_name || !admin_email || !admin_password) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: school_name, admin_email, admin_password",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (typeof admin_password !== "string" || admin_password.length < 8) {
      return new Response(
        JSON.stringify({ error: "Password must be at least 8 characters" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── Check if email already exists ────────────────────────────────────
    const { data: existingTeacher } = await supabase
      .from("teachers")
      .select("id")
      .eq("email", admin_email)
      .maybeSingle();

    if (existingTeacher) {
      return new Response(
        JSON.stringify({ error: "An account with this email already exists" }),
        { status: 409, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Hash password with bcrypt + pepper ─────────────────────────────────
    const pepper = Deno.env.get("PASSWORD_PEPPER");
    if (!pepper) {
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: PASSWORD_PEPPER not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
    const passwordHash = await bcrypt.hash(admin_password + pepper, 10);

    // Generate random 32-byte salt (base64)
    const salt = crypto.getRandomValues(new Uint8Array(32));
    const saltBase64 = btoa(String.fromCharCode(...salt));

    // ── Generate school short code ─────────────────────────────────────────
    const shortCode =
      "SCH" +
      Math.random().toString(36).substring(2, 6).toUpperCase() +
      Math.random().toString(36).substring(2, 4).toUpperCase();

    // ── Create the school ──────────────────────────────────────────────────
    const { data: school, error: schoolError } = await supabase
      .from("schools")
      .insert({
        school_name,
        short_code: shortCode,
        subscription_tier: "free",
        total_seats: 5,
        admin_recovery_email: recovery_email ?? null,
        admin_recovery_email_verified: false,
      })
      .select()
      .single();

    if (schoolError) {
      console.error("[signup] school insert error:", schoolError);
      throw schoolError;
    }

    // ── Create the admin teacher ───────────────────────────────────────────
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .insert({
        email: admin_email,
        teacher_name: school_name, // use school name as initial teacher name
        role: "admin",
        school_id: school.id,
        password_hash: passwordHash,
        salt: saltBase64,
        password_hash_version: 1,
        force_password_reset: false,
        is_active: true,
        email_verified: false, // must verify email on first login
      })
      .select()
      .single();

    if (teacherError) {
      console.error("[signup] teacher insert error:", teacherError);
      // Rollback: delete the school we just created
      await supabase.from("schools").delete().eq("id", school.id);
      throw teacherError;
    }

    // ── Recovery email: create recovery admin & send credentials ─────────
    if (recovery_email && recovery_email.toLowerCase() !== admin_email) {
      try {
        // Generate temporary password (same pattern as add-teacher)
        const charset = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%&";
        const tempPassword = Array.from(crypto.getRandomValues(new Uint8Array(12)))
          .map((b) => charset[b % charset.length])
          .join("");

        const recoveryPasswordHash = await bcrypt.hash(tempPassword + pepper, 10);

        const recoverySalt = crypto.getRandomValues(new Uint8Array(32));
        const recoverySaltBase64 = btoa(String.fromCharCode(...recoverySalt));

        // Create the recovery admin teacher under the same school
        const { error: recoveryError } = await supabase
          .from("teachers")
          .insert({
            email: recovery_email.toLowerCase(),
            teacher_name: `${school_name} (Recovery Admin)`,
            role: "admin",
            school_id: school.id,
            password_hash: recoveryPasswordHash,
            salt: recoverySaltBase64,
            password_hash_version: 1,
            force_password_reset: true,
            is_active: true,
            email_verified: false,
            temp_password: tempPassword,
          });

        if (recoveryError) {
          console.error("[signup] recovery teacher insert error:", recoveryError);
        } else {
          console.log("[signup] Recovery admin created for", recovery_email);

          // Send credentials to the recovery email via Gmail SMTP
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
                to: recovery_email,
                subject: `ClassAI – Recovery Admin Account Created for ${school_name}`,
                html: `
                  <h2>Recovery Admin Account Created</h2>
                  <p>An admin account has been created for you as a recovery contact for <strong>${school_name}</strong>.</p>
                  <p><strong>Email:</strong> ${recovery_email}</p>
                  <p><strong>Temporary Password:</strong> ${tempPassword}</p>
                  <p>You will be required to change your password on first login.</p>
                  <p>This account has <strong>admin</strong> privileges under the same school.</p>
                  <p><strong>If you don't see this email, please check your spam/junk folder.</strong></p>
                  <p>Best regards,<br/>The ClassAI Team</p>
                `,
              });
              console.log("[signup] Recovery email sent to", recovery_email);
            } catch (emailErr) {
              console.error("[signup] Gmail SMTP error for recovery email:", emailErr);
            }
          } else {
            console.warn(
              "[signup] GMAIL_USER or GMAIL_APP_PASSWORD not set; skipping recovery email for",
              recovery_email
            );
          }
        }
      } catch (recoveryErr) {
        // Non-fatal: school and admin were created, recovery is best-effort
        console.error("[signup] recovery email flow error:", recoveryErr);
      }
    }

    // ── Generate JWT ──────────────────────────────────────────────────────
    const cryptoKey = await getHmacKey(JWT_SECRET);
    const jwt = await create(
      { alg: "HS256", typ: "JWT" },
      {
        sub: teacher.id,
        teacher_id: teacher.id,
        school_id: teacher.school_id,
        is_admin: true,
        exp: getNumericDate(60 * 60 * 24), // 24 hours
      },
      cryptoKey
    );

    // ── Return AuthResult-compatible payload ──────────────────────────────
    return new Response(
      JSON.stringify({
        jwt,
        teacher: {
          id: teacher.id,
          email: teacher.email,
          name: teacher.teacher_name,
          role: teacher.role,
          school_id: teacher.school_id,
          email_verified: false,
          theme_mode: "system",
        },
        school: {
          id: school.id,
          name: school.school_name,
          subscription_tier: school.subscription_tier,
        },
        wrapped_school_key: school.school_master_key_wrapped ?? null,
        salt: teacher.salt,
        password_hash_version: teacher.password_hash_version,
        offline_credits: 3,
        last_credit_refill_server_time: new Date().toISOString(),
        email_verified: false,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[signup] error:", err);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
