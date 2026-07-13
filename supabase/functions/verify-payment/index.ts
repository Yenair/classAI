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
    const { reference } = body;

    if (!reference) {
      return jsonResponse({ error: "Missing required field: reference" }, 400);
    }

    // ── 5. Retrieve Paystack secret key ────────────────────────────
    const paystackSecretKey = Deno.env.get("PAYSTACK_SECRET_KEY");
    if (!paystackSecretKey) {
      return jsonResponse({ error: "Paystack secret key not configured" }, 500);
    }

    // ── 6. Call Paystack verify ────────────────────────────────────
    const response = await fetch(
      `${PAYSTACK_BASE}/transaction/verify/${encodeURIComponent(reference)}`,
      {
        headers: {
          Authorization: `Bearer ${paystackSecretKey}`,
          "Content-Type": "application/json",
        },
      },
    );

    let paystackError: { message?: string; code?: string } | null = null;
    let paystackResult: Record<string, unknown> | null = null;

    if (!response.ok) {
      const errorBody = await response.text();
      try {
        const parsed = JSON.parse(errorBody);
        paystackError = {
          message: (parsed.message as string) ?? response.statusText,
          code: (parsed.code as string) ?? undefined,
        };
      } catch {
        paystackError = { message: response.statusText };
      }

      // Translate Paystack error codes into appropriate HTTP statuses:
      //   - transaction_not_found / 400 → client sent a bad reference (400)
      //   - Any other 4xx → client error (400)
      //   - 5xx → upstream Paystack failure (502)
      if (response.status === 400 || response.status === 404 ||
          paystackError.code === "transaction_not_found") {
        return jsonResponse(
          {
            error: paystackError.message ?? "Transaction reference not found",
            code: "transaction_not_found",
          },
          400,
        );
      }

      // Connectivity / upstream failure
      return jsonResponse(
        { error: `Paystack verification failed: ${paystackError.message ?? response.statusText}` },
        502,
      );
    }

    paystackResult = await response.json() as Record<string, unknown>;

    // ── 7. Return only client-safe fields ──────────────────────────
    return jsonResponse({
      status: (paystackResult.data as Record<string, unknown>)?.status as string ?? "unknown",
      reference: (paystackResult.data as Record<string, unknown>)?.reference as string ?? reference,
      amount: (paystackResult.data as Record<string, unknown>)?.amount as number ?? 0,
      paid_at: (paystackResult.data as Record<string, unknown>)?.paid_at as string | null ?? null,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: message }, 500);
  }
});
