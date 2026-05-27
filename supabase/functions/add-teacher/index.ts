import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import nodemailer from "npm:nodemailer";
import { validateTokenVersion } from "../_shared/validate_token.ts";

serve(async (req) => {
  try {
    // ── 1. Extract and verify admin JWT ──────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid Authorization header" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    const jwtSecret = Deno.env.get("JWT_SECRET");
    if (!jwtSecret) {
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: JWT_SECRET not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.replace("Bearer ", "");

    // Validate token and check token_version
    let claims: Record<string, unknown>;
    try {
      claims = await validateTokenVersion(
        token,
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        jwtSecret,
      );
    } catch (err) {
      const { error, code, status } = err as { error: string; code: string; status: number };
      return new Response(
        JSON.stringify({ error, code }),
        { status, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 2. Verify caller is an admin ─────────────────────────────────────
    if (!claims.is_admin) {
      return new Response(
        JSON.stringify({ error: "Admin privileges required" }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }

    const adminTeacherId = claims.teacher_id as string;
    const schoolId = claims.school_id as string;

    // ── 3. Parse request body once ────────────────────────────────────────
    const body = await req.json();
    let { email, teacher_name, role, resend } = body;
    email = email.toLowerCase();

    if (!email || !teacher_name) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: email, teacher_name" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const teacherRole = role === "admin" ? "admin" : "teacher";

    // ── 4. Check if email already exists ─────────────────────────────────
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: existingTeacher } = await supabase
      .from("teachers")
      .select("id, teacher_name")
      .eq("email", email)
      .maybeSingle();

    if (existingTeacher) {
      // If resend flag is set, regenerate their password instead of erroring
      if (resend === true) {
        // Generate a new temporary password
        const charset = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%&";
        const newTempPassword = Array.from(crypto.getRandomValues(new Uint8Array(12)))
          .map((b) => charset[b % charset.length])
          .join("");

        // Hash the new password
        const pepper = Deno.env.get("PASSWORD_PEPPER")!;
        const newPasswordHash = await bcrypt.hash(newTempPassword + pepper, 10);

        // Update the teacher's password and temp_password
        const { error: updateError } = await supabase
          .from("teachers")
          .update({
            password_hash: newPasswordHash,
            force_password_reset: true,
            temp_password: newTempPassword,
          })
          .eq("email", email);

        if (updateError) {
          console.error("[add-teacher] resend update error:", updateError);
          throw updateError;
        }

        // Send email with new password
        const gmailUser = Deno.env.get("GMAIL_USER");
        const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");
        if (gmailUser && gmailAppPassword) {
          try {
            const schoolName = await getSchoolName(supabase, schoolId);
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
              subject: `ClassAI – Your Temporary Password Has Been Reset`,
              html: `
                <h2>Your temporary password has been reset</h2>
                <p>Your new temporary password for ClassAI is below.</p>
                <p><strong>Email:</strong> ${email}</p>
                <p><strong>Temporary Password:</strong> ${newTempPassword}</p>
                <p>You will be required to change your password on first login.</p>
                <p><strong>If you don't see this email, please check your spam/junk folder.</strong></p>
                <p>Best regards,<br/>The ClassAI Team</p>
              `,
            });
            console.log("[add-teacher] Resend email sent to", email);
          } catch (emailErr) {
            console.error("[add-teacher] Gmail SMTP error on resend:", emailErr);
          }
        }

        return new Response(
          JSON.stringify({
            success: true,
            teacher: {
              id: existingTeacher.id,
              email,
              name: existingTeacher.teacher_name,
              role: teacherRole,
            },
            temp_password: newTempPassword,
            message: "A new temporary password has been emailed to the teacher.",
          }),
          { headers: { "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ error: "A teacher with this email already exists" }),
        { status: 409, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 5. Generate temporary password (12 random chars) ─────────────────
    const charset = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%&";
    const tempPassword = Array.from(crypto.getRandomValues(new Uint8Array(12)))
      .map((b) => charset[b % charset.length])
      .join("");

    // ── 6. Hash password with bcrypt + pepper ────────────────────────────
    const pepper = Deno.env.get("PASSWORD_PEPPER")!;
    const passwordHash = await bcrypt.hash(tempPassword + pepper, 10);

    // Generate random 32-byte salt (base64)
    const salt = crypto.getRandomValues(new Uint8Array(32));
    const saltBase64 = btoa(String.fromCharCode(...salt));

    // ── 7. Insert teacher with force_password_reset = true and temp_password ──
    const { data: newTeacher, error: insertError } = await supabase
      .from("teachers")
      .insert({
        email,
        teacher_name,
        role: teacherRole,
        school_id: schoolId,
        password_hash: passwordHash,
        salt: saltBase64,
        password_hash_version: 1,
        force_password_reset: true,
        is_active: true,
        temp_password: tempPassword,
      })
      .select()
      .single();

    if (insertError) {
      console.error("[add-teacher] insert error:", insertError);
      throw insertError;
    }

    // ── 8. Send email via Gmail SMTP ────────────────────────────────────
    const gmailUser = Deno.env.get("GMAIL_USER");
    const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");
    if (gmailUser && gmailAppPassword) {
      try {
        const schoolName = await getSchoolName(supabase, schoolId);
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
          subject: `Welcome to ClassAI – Your Temporary Password`,
          html: `
            <h2>Welcome to ${schoolName}!</h2>
            <p>An account has been created for you on the ClassAI platform.</p>
            <p><strong>Email:</strong> ${email}</p>
            <p><strong>Temporary Password:</strong> ${tempPassword}</p>
            <p>You will be required to change your password on first login.</p>
            <p><strong>If you don't see this email, please check your spam/junk folder.</strong></p>
            <p>Best regards,<br/>The ClassAI Team</p>
          `,
        });
        console.log("[add-teacher] Welcome email sent to", email);
      } catch (emailErr) {
        console.error("[add-teacher] Gmail SMTP error:", emailErr);
        // Non-fatal: teacher was created, email delivery failed
      }
    } else {
      console.warn(
        "[add-teacher] GMAIL_USER or GMAIL_APP_PASSWORD not set; skipping email for",
        email
      );
    }

    // ── 9. Return success with temp_password ─────────────────────────────
    return new Response(
      JSON.stringify({
        success: true,
        teacher: {
          id: newTeacher.id,
          email: newTeacher.email,
          name: newTeacher.teacher_name,
          role: newTeacher.role,
        },
        temp_password: tempPassword,
        message: "Teacher created successfully. A welcome email has been sent.",
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[add-teacher] error:", err);
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
