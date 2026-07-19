import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

const PAYSTACK_BASE = "https://api.paystack.co";
const ALLOWED_TIERS = new Set(["basic", "standard", "elite"]);
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_PREFIX = "CLA";
const DEFAULT_DURATION_DAYS = 365;

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function normalizeTier(plan: unknown): string | null {
  if (typeof plan !== "string") return null;
  const tier = plan.trim().toLowerCase();
  return ALLOWED_TIERS.has(tier) ? tier : null;
}

function generateActivationCode(): string {
  const randomGroup = () => {
    let group = "";
    const bytes = crypto.getRandomValues(new Uint8Array(4));
    for (const byte of bytes) {
      group += CODE_ALPHABET.charAt(byte % CODE_ALPHABET.length);
    }
    return group;
  };

  return `${CODE_PREFIX}-${randomGroup()}-${randomGroup()}-${randomGroup()}`;
}

async function sendActivationCodeEmail(
  email: string,
  code: string,
  tier: string,
  expiryDate: Date,
): Promise<void> {
  const gmailUser = Deno.env.get("GMAIL_USER");
  const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");
  if (!gmailUser || !gmailAppPassword) return;

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
    subject: "ClassAI Activation Code",
    html: `
      <h2>Your ClassAI activation code</h2>
      <p>Your payment has been confirmed and your subscription has been upgraded to <strong>${tier}</strong>.</p>
      <p><strong>Activation code:</strong> ${code}</p>
      <p><strong>Expiry date:</strong> ${expiryDate.toISOString()}</p>
      <p>This code is your permanent receipt. Keep it safe.</p>
    `,
  });
}

serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    // ── 1. Extract and verify JWT ──────────────────────────────────
    const token = req.headers.get("x-classai-jwt")?.trim() ?? "";
    if (!token) {
      return jsonResponse({ error: "Missing authentication token" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const jwtSecret = Deno.env.get("JWT_SECRET");

    if (!supabaseUrl || !serviceRoleKey || !jwtSecret) {
      return jsonResponse({ error: "Server misconfiguration" }, 500);
    }

    let claims: Record<string, unknown>;
    try {
      claims = await validateTokenVersion(token, supabaseUrl, serviceRoleKey, jwtSecret);
    } catch (err) {
      const e = err as { error: string; code: string; status: number };
      return jsonResponse({ error: e.error, code: e.code }, e.status ?? 401);
    }

    const teacherId = claims.teacher_id as string;
    const jwtSchoolId = claims.school_id as string;
    if (!teacherId || !jwtSchoolId) {
      return jsonResponse({ error: "Invalid token: missing teacher_id or school_id" }, 401);
    }

    // ── 2. Verify admin role ───────────────────────────────────────
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: teacher, error: teacherError } = await supabase
      .from("teachers")
      .select("role, school_id")
      .eq("id", teacherId)
      .maybeSingle();

    if (teacherError || !teacher) {
      return jsonResponse({ error: "Teacher not found" }, 404);
    }

    if (teacher.role !== "admin") {
      return jsonResponse({ error: "Admin access required" }, 403);
    }

    // ── 3. Parse body — only reference and plan from body ──────────
    const body = await req.json().catch(() => ({}));
    const { reference, plan } = body;

    if (!reference || !plan) {
      return jsonResponse(
        { error: "Missing required fields: reference, plan" },
        400,
      );
    }

    const tier = normalizeTier(plan);
    if (!tier) {
      return jsonResponse(
        { error: "Invalid subscription tier. Use basic, standard, or elite." },
        400,
      );
    }

    // ── 4. IDEMPOTENCY CHECK: has this reference been finalized? ───
    const { data: existingCode } = await supabase
      .from("activation_codes")
      .select("code, tier, duration_days, school_id, used")
      .eq("reference", reference)
      .maybeSingle();

    if (existingCode) {
      // If the existing row has a different school_id, reject
      if (existingCode.school_id !== jwtSchoolId) {
        return jsonResponse({ error: "Reference belongs to a different school" }, 403);
      }

      // Already processed — return existing result
      const existingTier = existingCode.tier ?? tier;
      // Calculate original expiry from duration_days
      const now = new Date();
      const expiryDate = new Date(
        now.getTime() + (existingCode.duration_days ?? DEFAULT_DURATION_DAYS) * 24 * 60 * 60 * 1000,
      );

      return jsonResponse({
        success: true,
        already_processed: true,
        activation_code: existingCode.code,
        subscription_tier: existingTier,
        expiry_date: expiryDate.toISOString(),
      });
    }

    // ── 5. Paystack server-side verification ───────────────────────
    const paystackSecretKey = Deno.env.get("PAYSTACK_SECRET_KEY");
    if (!paystackSecretKey) {
      return jsonResponse({ error: "Paystack secret key not configured" }, 500);
    }

    const verifyResponse = await fetch(
      `${PAYSTACK_BASE}/transaction/verify/${encodeURIComponent(reference)}`,
      {
        headers: {
          Authorization: `Bearer ${paystackSecretKey}`,
          "Content-Type": "application/json",
        },
      },
    );

    if (!verifyResponse.ok) {
      return jsonResponse(
        { error: `Paystack verification failed: ${verifyResponse.statusText}` },
        502,
      );
    }

    const verifyData = await verifyResponse.json();
    const txStatus = verifyData?.data?.status;
    if (txStatus !== "success") {
      return jsonResponse(
        { error: `Payment not successful. Status: ${txStatus ?? "unknown"}` },
        402,
      );
    }

    // ── 6. MARK-FIRST: insert activation code with used: true immediately ──
    const now = new Date();
    const expiryDate = new Date(
      now.getTime() + DEFAULT_DURATION_DAYS * 24 * 60 * 60 * 1000,
    );

    let activationCode = "";
    let inserted = false;
    let activationRow: { code: string; duration_days: number } | null = null;

    for (let attempt = 0; attempt < 8 && !inserted; attempt++) {
      activationCode = generateActivationCode();
      const { data, error } = await supabase
        .from("activation_codes")
        .insert({
          code: activationCode,
          school_id: jwtSchoolId,
          tier,
          duration_days: DEFAULT_DURATION_DAYS,
          reference,
          used: true,  // immediately marked used
          redeemed_at: now.toISOString(),
        })
        .select("code, duration_days")
        .single();

      if (!error && data) {
        activationRow = data as { code: string; duration_days: number };
        inserted = true;
        break;
      }

      if (error && error.code !== "23505") {
        return jsonResponse(
          { error: `Failed to create activation code: ${error.message}` },
          500,
        );
      }
    }

    if (!inserted || !activationRow) {
      // ── RACE HANDLER: insert may have failed because another concurrent
      //    request inserted a row with the same `reference` between our
      //    idempotency check and our insert (Postgres unique constraint).
      const { data: raceRow } = await supabase
        .from("activation_codes")
        .select("code, tier, duration_days, school_id, used")
        .eq("reference", reference)
        .maybeSingle();

      if (raceRow) {
        // The concurrent request won the race — return the same
        // already_processed response as the idempotency check path.
        const raceTier = raceRow.tier ?? tier;
        const raceExpiry = new Date(
          Date.now() + (raceRow.duration_days ?? DEFAULT_DURATION_DAYS) * 24 * 60 * 60 * 1000,
        );
        return jsonResponse({
          success: true,
          already_processed: true,
          activation_code: raceRow.code,
          subscription_tier: raceTier,
          expiry_date: raceExpiry.toISOString(),
        });
      }

      return jsonResponse(
        { error: "Failed to generate a unique activation code" },
        500,
      );
    }

    // ── 7. Update school record ────────────────────────────────────
    const { error: updateError } = await supabase
      .from("schools")
      .update({
        subscription_tier: tier,
        expiry_date: expiryDate.toISOString(),
        activation_code: activationRow.code,
        updated_at: now.toISOString(),
      })
      .eq("id", jwtSchoolId);

    if (updateError) {
      // Rollback: delete the just-inserted activation code
      await supabase
        .from("activation_codes")
        .delete()
        .eq("code", activationRow.code);

      return jsonResponse(
        { error: `Failed to update school: ${updateError.message}` },
        500,
      );
    }

    // ── 8. Send activation email (best-effort) ─────────────────────
    // Fetch admin email for notification
    const { data: adminTeacher } = await supabase
      .from("teachers")
      .select("email")
      .eq("school_id", jwtSchoolId)
      .eq("role", "admin")
      .maybeSingle();

    const adminEmail = typeof adminTeacher?.email === "string"
      ? adminTeacher.email.toLowerCase()
      : null;

    if (adminEmail) {
      try {
        await sendActivationCodeEmail(
          adminEmail,
          activationRow.code,
          tier,
          expiryDate,
        );
      } catch (emailErr) {
        console.error(
          "[confirm-payment] activation email failed to send to",
          adminEmail,
          ":",
          emailErr instanceof Error ? emailErr.message : String(emailErr),
        );

        // Payment succeeded — include a warning but keep the 200 status
        return jsonResponse({
          success: true,
          activation_code: activationRow.code,
          subscription_tier: tier,
          expiry_date: expiryDate.toISOString(),
          warning: "Payment successful, but activation email could not be sent. Please contact support.",
        });
      }
    }

    return jsonResponse({
      success: true,
      activation_code: activationRow.code,
      subscription_tier: tier,
      expiry_date: expiryDate.toISOString(),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: message }, 500);
  }
});
