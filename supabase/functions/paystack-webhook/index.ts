import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

async function createHmacHex(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
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
      <p>Your payment was confirmed on Paystack and your subscription tier was recorded as <strong>${tier}</strong>.</p>
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

    // ── Verify Paystack signature ──────────────────────────────────
    const bodyText = await req.text();
    const signature = req.headers.get("x-paystack-signature") ?? "";
    if (!signature) {
      return jsonResponse({ error: "Missing Paystack signature" }, 401);
    }

    const computedSignature = await createHmacHex(bodyText, paystackSecretKey);
    if (computedSignature !== signature.toLowerCase()) {
      return jsonResponse({ error: "Invalid Paystack signature" }, 401);
    }

    const payload = JSON.parse(bodyText) as {
      event?: string;
      data?: {
        reference?: string;
        metadata?: {
          plan?: string;
          school_id?: string;
          email?: string;
          source?: string;
        };
      };
    };

    const eventType = payload.event ?? "unknown";
    const eventReference = payload.data?.reference ?? "unknown";
    const now = new Date();

    // ── Log every webhook event ────────────────────────────────────
    console.log(
      `[paystack-webhook] event=${eventType} reference=${eventReference} timestamp=${now.toISOString()}`,
    );

    if (eventType !== "charge.success") {
      // ── Check for charge.failed after a prior charge.success ────
      if (eventType === "charge.failed" && eventReference !== "unknown") {
        try {
          const supabase = createClient(
            Deno.env.get("SUPABASE_URL") ?? "",
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
          );
          const { data: priorCode } = await supabase
            .from("activation_codes")
            .select("used")
            .eq("reference", eventReference)
            .maybeSingle();

          if (priorCode && priorCode.used === true) {
            console.warn(
              `[paystack-webhook] WARNING: charge.failed for reference=${eventReference} which previously succeeded and was finalized. Possible reversal/chargeback.`,
            );
          }
        } catch (logErr) {
          console.error(
            `[paystack-webhook] error checking prior charge.success for reference=${eventReference}:`,
            logErr,
          );
        }
      }

      return jsonResponse({ success: true });
    }

    // ── Extract metadata and reference ────────────────────────────
    const metadata = payload.data?.metadata ?? {};
    const reference = payload.data?.reference ?? "";
    const tier = normalizeTier(metadata.plan);
    const schoolId = typeof metadata.school_id === "string"
      ? metadata.school_id.trim()
      : "";
    const email = typeof metadata.email === "string"
      ? metadata.email.trim().toLowerCase()
      : "";

    if (!tier || !schoolId || !email) {
      return jsonResponse(
        { error: "Missing required Paystack metadata: plan, school_id, email" },
        400,
      );
    }

    if (!reference) {
      return jsonResponse(
        { error: "Missing transaction reference in Paystack payload" },
        400,
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "Server misconfiguration" }, 500);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // ── IDEMPOTENCY CHECK: has this reference been finalized? ─────
    const { data: existingCode } = await supabase
      .from("activation_codes")
      .select("code")
      .eq("reference", reference)
      .maybeSingle();

    if (existingCode) {
      // Already processed by another path (e.g., confirm-payment) — safe no-op
      return jsonResponse({ success: true, already_processed: true });
    }

    const { data: school, error: schoolError } = await supabase
      .from("schools")
      .select("id, school_name")
      .eq("id", schoolId)
      .maybeSingle();

    if (schoolError || !school) {
      return jsonResponse({ error: "School not found" }, 404);
    }

    const now = new Date();
    const expiryDate = new Date(
      now.getTime() + DEFAULT_DURATION_DAYS * 24 * 60 * 60 * 1000,
    );

    // ── Generate and insert activation code (with reference, used: true) ──
    let activationCode = "";
    let inserted = false;
    let activationRow: { code: string } | null = null;

    for (let attempt = 0; attempt < 8 && !inserted; attempt++) {
      activationCode = generateActivationCode();
      const { data, error } = await supabase
        .from("activation_codes")
        .insert({
          code: activationCode,
          school_id: schoolId,
          tier,
          duration_days: DEFAULT_DURATION_DAYS,
          reference,
          used: true,
          redeemed_at: now.toISOString(),
        })
        .select("code")
        .single();

      if (!error && data) {
        activationRow = data as { code: string };
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
        .select("code")
        .eq("reference", reference)
        .maybeSingle();

      if (raceRow) {
        // The concurrent request won the race — safe no-op, same as
        // the idempotency check path at the top of this handler.
        return jsonResponse({ success: true, already_processed: true });
      }

      return jsonResponse(
        { error: "Failed to generate a unique activation code" },
        500,
      );
    }

    // ── Update school record ──────────────────────────────────────
    const { error: updateError } = await supabase
      .from("schools")
      .update({
        subscription_tier: tier,
        expiry_date: expiryDate.toISOString(),
        activation_code: activationRow.code,
        updated_at: now.toISOString(),
      })
      .eq("id", schoolId);

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

    // ── Send activation email (best-effort) ───────────────────────
    try {
      await sendActivationCodeEmail(email, activationRow.code, tier, expiryDate);
    } catch {
      // Email delivery is best-effort; keep the webhook acknowledgement successful.
    }

    return jsonResponse({
      success: true,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: message }, 500);
  }
});
