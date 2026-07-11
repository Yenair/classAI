import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

/** Derive a human-readable tier display name from the requested_tier string. */
function tierDisplay(tier: string): string {
  if (!tier || tier.length === 0) return "";
  return tier.charAt(0).toUpperCase() + tier.slice(1).toLowerCase();
}

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

serve(async (req) => {
  console.log(
    `[request-upgrade] ${req.method} ${new URL(req.url).toString()}`,
  );

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    // ── 1. Read JWT from the Authorization header ──────────────────────
    // When deployed with verify_jwt=true, the Supabase runtime verifies
    // the signature and expiry before this handler runs. We additionally
    // call validateTokenVersion below for the custom claims (teacher_id, etc.).
    const authHeader = req.headers.get("authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!token) {
      return jsonResponse({ error: "Missing Authorization header" }, 401);
    }

    // ── 2. Validate JWT with the shared helper ─────────────────────────
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const jwtSecret = Deno.env.get("JWT_SECRET");

    if (!supabaseUrl || !serviceRoleKey || !jwtSecret) {
      console.error("[request-upgrade] missing server configuration");
      return jsonResponse(
        { error: "Server misconfiguration" },
        500,
      );
    }

    let claims: Record<string, unknown>;
    try {
      claims = await validateTokenVersion(
        token,
        supabaseUrl,
        serviceRoleKey,
        jwtSecret,
      );
    } catch (err) {
      const e = err as { error: string; code: string; status: number };
      console.error("[request-upgrade] JWT validation failed:", e.error, e.code);
      return jsonResponse({ error: e.error, code: e.code }, e.status ?? 401);
    }

    const teacherId = claims.teacher_id as string;
    const schoolId = claims.school_id as string;
    if (!teacherId || !schoolId) {
      return jsonResponse(
        { error: "Invalid token: missing teacher_id or school_id" },
        401,
      );
    }

    // ── 3. Parse body ──────────────────────────────────────────────────
    const body = await req.json().catch(() => ({}));
    const requestedTier = (body.requested_tier as string ?? "").toLowerCase();
    if (!["free", "basic", "standard", "elite"].includes(requestedTier)) {
      return jsonResponse(
        { error: "Invalid or missing requested_tier. Must be one of: free, basic, standard, elite" },
        400,
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // ── 4. Look up the teacher ────────────────────────────────────────
    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("id, email, teacher_name, school_id")
      .eq("id", teacherId)
      .single();

    if (teacherError || !teacher) {
      console.error("[request-upgrade] teacher lookup error:", teacherError);
      return jsonResponse({ error: "Teacher not found" }, 404);
    }

    const teacherName = teacher.teacher_name as string;
    const teacherEmail = teacher.email as string;

    // ── 5. Insert upgrade request (DB-level UNIQUE constraint guards duplicates) ──
    //    request_date uses UTC (Postgres CURRENT_DATE / now()::date are UTC).
    const { error: insertError } = await supabase
      .from("upgrade_requests")
      .insert({
        teacher_id: teacherId,
        requested_tier: requestedTier,
      });

    if (insertError) {
      // Check for unique constraint violation (teacher_id + request_date)
      const isDuplicate =
        insertError.code === "23505" || // PostgreSQL unique violation
        (insertError.message &&
          insertError.message.includes("duplicate key value violates unique constraint"));

      if (isDuplicate) {
        console.log(
          "[request-upgrade] duplicate request for teacher",
          teacherId,
          "on",
          new Date().toISOString().split("T")[0],
        );
        return jsonResponse({ already_requested: true });
      }

      console.error("[request-upgrade] insert error:", insertError);
      return jsonResponse({ error: "Failed to submit upgrade request" }, 500);
    }

    console.log(
      "[request-upgrade] upgrade request inserted for teacher",
      teacherId,
      "tier:",
      requestedTier,
    );

    // ── 6. Look up school admins ───────────────────────────────────────
    const { data: admins, error: adminsError } = await supabase
      .from("teachers")
      .select("email, teacher_name")
      .eq("school_id", schoolId)
      .eq("role", "admin");

    if (adminsError) {
      console.error("[request-upgrade] admin lookup error:", adminsError);
      // Non-fatal: request was already inserted, just skip the email
    }

    const adminEmails: string[] = [];
    if (admins && admins.length > 0) {
      for (const admin of admins) {
        const email = admin.email as string;
        if (email) adminEmails.push(email);
      }
    }

    if (adminEmails.length === 0) {
      console.error(
        "[request-upgrade] no admin found for school",
        schoolId,
        "— upgrade request recorded but email not sent",
      );
      return jsonResponse({
        success: true,
        no_admin: true,
        message: "Request recorded, but no admin email found for notification",
      });
    }

    // ── 7. Look up school name ─────────────────────────────────────────
    const { data: school, error: schoolError } = await supabase
      .from("schools")
      .select("school_name")
      .eq("id", schoolId)
      .single();

    if (schoolError) {
      console.error("[request-upgrade] school lookup error:", schoolError);
    }

    const schoolName = school?.school_name as string ?? "your school";

    // ── 8. Send email(s) via Gmail SMTP ────────────────────────────────
    const gmailUser = Deno.env.get("GMAIL_USER");
    const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");

    if (!gmailUser || !gmailAppPassword) {
      console.warn(
        "[request-upgrade] GMAIL_USER or GMAIL_APP_PASSWORD not set; skipping email notification",
      );
      return jsonResponse({
        success: true,
        email_skipped: true,
        message: "Request recorded, but email notification skipped (Gmail not configured)",
      });
    }

    const nodemailer = await import("npm:nodemailer");
    const transporter = nodemailer.default.createTransport({
      service: "gmail",
      auth: {
        user: gmailUser,
        pass: gmailAppPassword,
      },
    });

    // Build email body with the gentle template
    const displayTier = tierDisplay(requestedTier);
    const emailText = [
      `Hello ${schoolName},`,
      `I hope this mail finds you well.`,
      ``,
      `This is a reminder that ${teacherName} (${teacherEmail}) has requested an upgrade to the ${displayTier} plan.`,
      ``,
      `You can review and manage your subscription from the admin dashboard.`,
      `Thank you,`,
      ``,
      `The ClassAI Team,`,
      `PrimeClass Technologies`,
    ].join("\n");

    const emailSubject = "ClassAI – A Teacher Requested an Upgrade";

    let sentCount = 0;
    for (const adminEmail of adminEmails) {
      try {
        await transporter.sendMail({
          from: gmailUser,
          to: adminEmail,
          subject: emailSubject,
          text: emailText,
        });
        sentCount++;
        console.log(
          "[request-upgrade] notification email sent to",
          adminEmail,
        );
      } catch (emailErr) {
        console.error(
          "[request-upgrade] failed to send email to",
          adminEmail,
          ":",
          emailErr,
        );
      }
    }

    console.log(
      "[request-upgrade] sent",
      sentCount,
      "of",
      adminEmails.length,
      "notification emails",
    );

    return jsonResponse({
      success: true,
      already_requested: false,
      message: "Upgrade request sent to school admin",
    });
  } catch (err) {
    console.error("[request-upgrade] unexpected error:", err);
    return jsonResponse(
      {
        error: err instanceof Error ? err.message : "Internal server error",
      },
      500,
    );
  }
});
