import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts";

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function getHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
}

function serializeError(err: unknown): Record<string, unknown> {
  if (err instanceof Error) {
    return {
      error: err.message,
      stack: err.stack ?? null,
      name: err.name,
    };
  }

  if (typeof err === "object" && err !== null) {
    return {
      error: JSON.stringify(err),
      stack: null,
    };
  }

  return {
    error: String(err),
    stack: null,
  };
}

serve(async (req) => {
  console.log(
    `[send-verification-code] ${req.method} ${new URL(req.url).toString()}`,
  );

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    // Parse body first to check mode
    const body = await req.json().catch(() => ({}));
    const { email: requestedEmail, mode } = body;

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse(
        {
          error:
            "Server misconfiguration: Supabase credentials are not configured",
        },
        500,
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    let email: string;

    if (mode === "signup") {
      // ── Signup mode: no JWT required, use email from body ────────────
      if (!requestedEmail) {
        return jsonResponse({ error: "Missing required field: email" }, 400);
      }
      email = requestedEmail.toLowerCase();
      console.log("[send-verification-code] signup mode, email:", email);
    } else {
      // ── Normal mode: require JWT ─────────────────────────────────────
      const authHeader = req.headers.get("Authorization");
      if (!authHeader || !authHeader.startsWith("Bearer ")) {
        return jsonResponse({ error: "Missing token" }, 401);
      }

      const jwtSecret = Deno.env.get("JWT_SECRET");
      if (!jwtSecret) {
        return jsonResponse(
          { error: "Server misconfiguration: JWT_SECRET not set" },
          500,
        );
      }

      const token = authHeader.replace("Bearer ", "");
      let claims: Record<string, unknown>;
      try {
        claims = await verify(token, await getHmacKey(jwtSecret), "HS256");
      } catch (err) {
        console.error("[send-verification-code] JWT verification failed:", err);
        return jsonResponse({ error: "Invalid or expired JWT" }, 401);
      }

      const teacherId = claims.sub;
      if (typeof teacherId !== "string" || teacherId.length === 0) {
        return jsonResponse({ error: "Invalid token: no subject claim" }, 401);
      }

      const { data: teacher, error: teacherError } = await supabase
        .from("teachers")
        .select("id, email, teacher_name")
        .eq("id", teacherId)
        .maybeSingle();

      if (teacherError) {
        console.error("[send-verification-code] teacher lookup error:", teacherError);
        return jsonResponse(
          { error: "Failed to look up teacher account" },
          500,
        );
      }

      if (!teacher) {
        return jsonResponse({ error: "Teacher not found" }, 404);
      }

      const teacherEmail = teacher.email as string | null;
      if (!teacherEmail) {
        return jsonResponse({ error: "Teacher email not found" }, 404);
      }

      if (requestedEmail && requestedEmail !== teacherEmail) {
        console.warn(
          "[send-verification-code] requested email did not match teacher email",
          {
            teacherId,
            requestedEmail,
            email: teacherEmail,
          },
        );
        return jsonResponse(
          { error: "Email does not match the authenticated account" },
          403,
        );
      }

      email = teacherEmail;
    }

    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();

    console.log("[send-verification-code] generated code", {
      teacherId,
      email,
      expiresAt,
    });

    const { error: expireOldCodesError } = await supabase
      .from("verification_codes")
      .update({ used: true })
      .eq("email", email)
      .eq("used", false);

    if (expireOldCodesError) {
      console.error(
        "[send-verification-code] failed to expire old codes:",
        expireOldCodesError,
      );
      return jsonResponse(
        {
          ...serializeError(expireOldCodesError),
          step: "expire_old_codes",
        },
        500,
      );
    }

    const { error: insertError } = await supabase
      .from("verification_codes")
      .insert({
        email,
        code,
        expires_at: expiresAt,
        used: false,
      });

    if (insertError) {
      console.error("[send-verification-code] insert error:", insertError);
      return jsonResponse(
        {
          ...serializeError(insertError),
          step: "insert_code",
        },
        500,
      );
    }

    const gmailUser = Deno.env.get("GMAIL_USER");
    const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");
    if (!gmailUser || !gmailAppPassword) {
      console.error(
        "[send-verification-code] missing Gmail credentials in environment",
      );
      return jsonResponse(
        { error: "Email service is not configured" },
        500,
      );
    }

    const nodemailer = await import("npm:nodemailer");
    const transporter = nodemailer.default.createTransport({
      service: "gmail",
      auth: {
        user: gmailUser,
        pass: gmailAppPassword,
      },
    });

    await transporter.sendMail({
      from: gmailUser,
      to: email,
      subject: "ClassAI – Email Verification Code",
      text:
        `Hello,

Thank you for signing up with ClassAI. To complete your account setup, please use the verification code below:

${code}

This code is valid for 15 minutes. If you did not request this verification, no action is needed—simply ignore this message.

If you experience any issues, check your spam/junk folder or contact our support team.

Best regards,
The ClassAI Team`,
    });

    console.log("[send-verification-code] verification email sent", {
      teacherId,
      email,
    });

    return jsonResponse({
      success: true,
      message: "Verification code sent successfully",
    });
  } catch (err) {
    console.error("[send-verification-code] error:", err);
    return jsonResponse(serializeError(err), 500);
  }
});
