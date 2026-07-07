import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

    const paystackSecretKey = Deno.env.get("PAYSTACK_SECRET_KEY");
    if (!paystackSecretKey) {
      return jsonResponse({ error: "Paystack secret key not configured" }, 500);
    }

    const { reference, plan, school_id, email } = await req.json();

    if (!reference || !plan || !school_id) {
      return jsonResponse(
        { error: "Missing required fields: reference, plan, school_id" },
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
        {
          error: `Paystack verification failed: ${verifyResponse.statusText}`,
        },
        502,
      );
    }

    const verifyData = await verifyResponse.json();
    const txStatus = verifyData?.data?.status;
    if (txStatus !== "success") {
      return jsonResponse(
        {
          error: `Payment not successful. Status: ${txStatus ?? "unknown"}`,
        },
        402,
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: school, error: schoolError } = await supabase
      .from("schools")
      .select("id, school_name")
      .eq("id", school_id)
      .maybeSingle();

    if (schoolError || !school) {
      return jsonResponse({ error: "School not found" }, 404);
    }

    const { data: adminTeacher } = await supabase
      .from("teachers")
      .select("email")
      .eq("school_id", school_id)
      .eq("role", "admin")
      .maybeSingle();

    const adminEmail = typeof adminTeacher?.email === "string"
      ? adminTeacher.email.toLowerCase()
      : null;
    const activationEmail =
      typeof email === "string" && email.trim().length > 0
        ? email.trim().toLowerCase()
        : adminEmail;

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
          school_id,
          tier,
          duration_days: DEFAULT_DURATION_DAYS,
          used: false,
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
      return jsonResponse(
        { error: "Failed to generate a unique activation code" },
        500,
      );
    }

    const { error: updateError } = await supabase
      .from("schools")
      .update({
        subscription_tier: tier,
        expiry_date: expiryDate.toISOString(),
        activation_code: activationRow.code,
        updated_at: now.toISOString(),
      })
      .eq("id", school_id);

    if (updateError) {
      return jsonResponse(
        { error: `Failed to update school: ${updateError.message}` },
        500,
      );
    }

    const { error: markUsedError } = await supabase
      .from("activation_codes")
      .update({
        used: true,
        redeemed_at: now.toISOString(),
      })
      .eq("code", activationRow.code)
      .eq("used", false);

    if (markUsedError) {
      return jsonResponse(
        {
          error: `Failed to finalize activation code: ${markUsedError.message}`,
        },
        500,
      );
    }

    if (activationEmail) {
      try {
        await sendActivationCodeEmail(
          activationEmail,
          activationRow.code,
          tier,
          expiryDate,
        );
      } catch {
        // Email delivery is best-effort; the payment and activation already succeeded.
      }
    }

    return jsonResponse({
      success: true,
      activation_code: activationRow.code,
      subscription_tier: tier,
      expiry_date: expiryDate.toISOString(),
      code: activationRow.code,
      tier,
      expiry: expiryDate.toISOString(),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: message }, 500);
  }
});
