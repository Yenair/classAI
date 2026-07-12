import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

const PAYSTACK_BASE = "https://api.paystack.co";

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
    // ── 1. Extract JWT ──────────────────────────────────────────────
    const authHeader = req.headers.get("authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
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
    const { email, amount, plan, school_id } = body;

    if (!email || !amount || !plan || !school_id) {
      return jsonResponse(
        { error: "Missing required fields: email, amount, plan, school_id" },
        400,
      );
    }

    // ── 5. Verify school_id matches the caller's school ────────────
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
        plan,
        currency: "NGN",
        callback_url: "classai://payment/complete",
        metadata: {
          school_id,
          plan,
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
