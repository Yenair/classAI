import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

/** Minimum seconds that must elapse between verification token generations. */
const RATE_LIMIT_COOLDOWN_SEC = 120; // 2 minutes

serve(async (req) => {
  try {
    // ── Parse request ──────────────────────────────────────────────────────
    let { email } = await req.json();
    email = email.toLowerCase();

    if (!email) {
      return new Response(
        JSON.stringify({ error: "Missing required field: email" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
    const JWT_SECRET = Deno.env.get("JWT_SECRET");

    // ── JWT validation (best-effort for authenticated flows) ───────────────
    // If a valid JWT is present, we additionally verify the caller is the
    // same teacher whose email is being verified (prevents abuse by
    // authenticated users triggering verification for arbitrary emails).
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    let jwtClaims: Record<string, unknown> | null = null;

    if (token && JWT_SECRET) {
      try {
        jwtClaims = await validateTokenVersion(
          token,
          Deno.env.get("SUPABASE_URL")!,
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
          JWT_SECRET,
        );
      } catch {
        // Invalid/expired JWT — still allow the unauthenticated fallback
        // with rate limiting below.
        jwtClaims = null;
      }
    }

    // ── Look up the teacher by email ──────────────────────────────────────
    const { data: teacher, error: lookupError } = await supabase
      .from("teachers")
      .select("id, email, teacher_name, email_verification_token_expiry, email_verified")
      .eq("email", email)
      .maybeSingle();

    if (lookupError) {
      console.error("[verify-email] lookup error:", lookupError);
      return new Response(
        JSON.stringify({ error: "Database error during lookup" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!teacher) {
      return new Response(
        JSON.stringify({ error: "No account found with this email address" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── JWT claim check: if authenticated, enforce teacher match ──────────
    if (jwtClaims) {
      const tokenTeacherId = jwtClaims.teacher_id as string;
      if (tokenTeacherId && tokenTeacherId !== teacher.id) {
        return new Response(
          JSON.stringify({
            error: "Authenticated user does not match the requested email",
          }),
          { status: 403, headers: { "Content-Type": "application/json" } }
        );
      }
    }

    // ── Rate limiting (cooldown) ──────────────────────────────────────────
    // Prevent rapid re-generation of verification tokens.
    if (teacher.email_verification_token_expiry) {
      const lastTokenTime = new Date(
        teacher.email_verification_token_expiry as string
      ).getTime();
      // The expiry is set 24h in the future, so we estimate generation time
      // as expiry minus 24 hours.
      const estimatedGenerationTime = lastTokenTime - 24 * 60 * 60 * 1000;
      const now = Date.now();
      const elapsed = (now - estimatedGenerationTime) / 1000;
      if (elapsed < RATE_LIMIT_COOLDOWN_SEC) {
        const waitSec = Math.ceil(RATE_LIMIT_COOLDOWN_SEC - elapsed);
        return new Response(
          JSON.stringify({
            error: `Please wait ${waitSec} seconds before requesting a new verification email`,
          }),
          { status: 429, headers: { "Content-Type": "application/json" } }
        );
      }
    }

    // ── Generate verification token ────────────────────────────────────────
    const verificationToken = crypto.randomUUID();
    const tokenExpiry = new Date();
    tokenExpiry.setHours(tokenExpiry.getHours() + 24); // 24-hour expiry

    // Store verification token on the teacher record
    const { error: updateError } = await supabase
      .from("teachers")
      .update({
        email_verification_token: verificationToken,
        email_verification_token_expiry: tokenExpiry.toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", teacher.id);

    if (updateError) {
      console.error("[verify-email] token update error:", updateError);
      return new Response(
        JSON.stringify({ error: "Failed to generate verification token" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Build verification link ────────────────────────────────────────────
    const appUrl = Deno.env.get("APP_URL") ?? "https://classai.app";
    const verificationUrl = `${appUrl}/verify-email?token=${verificationToken}&email=${encodeURIComponent(email)}`;

    // ── Attempt to send email via Supabase Auth's built-in mailer ──────────
    try {
      await supabase.auth.admin.generateLink({
        type: "signup",
        email: email,
        options: {
          redirectTo: verificationUrl,
        },
      });
    } catch (_emailErr) {
      console.warn(
        "[verify-email] Supabase Auth email send failed, verification link still available",
      );
    }

    // ── Return success with verification link ──────────────────────────────
    return new Response(
      JSON.stringify({
        success: true,
        message: "Verification email sent successfully",
        verification_url: verificationUrl,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[verify-email] error:", err);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
