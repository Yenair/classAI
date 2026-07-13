import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

const PAYSTACK_BASE = "https://api.paystack.co";

// TODO: Before going live, replace these test plan codes with production
// Paystack plan codes (generated from the Paystack live dashboard).
// Currently using Paystack test-mode plan codes:

//   basic:    PLN_98ax4ita4c3i87x
//   standard: PLN_ocrkm20c1oabtz0
//   elite:    PLN_htwuhwfhjjg62wz

const PLAN_CODES: Record<string, string> = {
  basic: "PLN_yongpg4zg23uszz",
  standard: "PLN_kvlfbes9ahpn3zd",
  elite: "PLN_ry6ze753lvuyr5i",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 200,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    // ── 1. Extract JWT from x-classai-jwt header ───────────────────
    // Using x-classai-jwt to bypass the Supabase gateway's Authorization
    // header validation (verify_jwt = false is not always honoured).
    const token = (req.headers.get("x-classai-jwt") ?? "").trim();
    if (!token) {
      return jsonResponse({ error: "Missing Authorization header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const jwtSecret = Deno.env.get("JWT_SECRET");

    if (!supabaseUrl || !serviceRoleKey || !jwtSecret) {
      return jsonResponse({ error: "Server misconfiguration" }, 500);
    }

    // ── 2. Validate JWT ────────────────────────────────────────────
    let claims: Record<string, unknown>;
    try {
      claims = await validateTokenVersion(token, supabaseUrl, serviceRoleKey, jwtSecret);
    } catch (err) {
      const e = err as { error: string; code: string; status: number };
      return jsonResponse({ error: e.error, code: e.code }, e.status ?? 401);
    }

    const teacherId = claims.teacher_id as string;
    if (!teacherId) {
      return jsonResponse({ error: "Invalid token: no teacher_id" }, 401);
    }

    // ── 3. Fetch caller's role & school_id ─────────────────────────
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

    // ── 4. Parse body ──────────────────────────────────────────────
    const body = await req.json().catch(() => ({}));
    const { email, amount, plan: planName, school_id } = body;

    if (!email || !amount || !planName || !school_id) {
      return jsonResponse(
        { error: "Missing required fields: email, amount, plan, school_id" },
        400,
      );
    }

    // ── 5. Resolve plan name to Paystack plan code ────────────────
    const planCode = PLAN_CODES[planName.toLowerCase()];
    if (!planCode) {
      return jsonResponse(
        { error: `Unknown plan: ${planName}. Allowed: basic, standard, elite` },
        400,
      );
    }

    // ── 5b. Verify school_id matches the caller's school ──────────
    if (teacher.school_id !== school_id) {
      return jsonResponse({ error: "Forbidden: school mismatch" }, 403);
    }

    // ── 6. Retrieve Paystack secret key ────────────────────────────
    const paystackSecretKey = Deno.env.get("PAYSTACK_SECRET_KEY");
    if (!paystackSecretKey) {
      return jsonResponse({ error: "Paystack secret key not configured" }, 500);
    }

    // ── 7. Call Paystack initialize ────────────────────────────────
    const amountKobo = Math.round(Number(amount) * 100);
    const response = await fetch(`${PAYSTACK_BASE}/transaction/initialize`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${paystackSecretKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        amount: amountKobo,
        plan: planCode,
        currency: "NGN",
        callback_url: "classai://payment/complete",
        metadata: {
          school_id,
          plan: planName,
          source: "classai-init",
        },
      }),
    });

    if (!response.ok) {
      const errorBody = await response.text();
      return jsonResponse(
        { error: `Paystack initialization failed: ${response.statusText}`, details: errorBody },
        502,
      );
    }

    const result = await response.json();

    // ── 8. Return only client-safe fields ──────────────────────────
    return jsonResponse({
      status: result.status,
      reference: result.data?.reference ?? "",
      authorization_url: result.data?.authorization_url ?? "",
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: message }, 500);
  }
});
