import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── In-memory session store for OTPs (for demo/Phase 8 purposes) ────────
// In production, store OTPs in a database table.
const otpStore = new Map<string, { otp: string; phone: string; expiresAt: Date }>();

/** Generate a random 6-digit OTP. */
function generateOtp(): string {
  return String(Math.floor(100000 + Math.random() * 900000));
}

/**
 * Africa's Talking USSD handler.
 *
 * Expected POST body:
 *   { sessionId, serviceCode, phoneNumber, text }
 *
 * - `text` is the full concatenated user input (e.g., "", "1", "1*08012345678")
 * - Response is plain text beginning with CON (continue) or END (terminate)
 */
serve(async (req) => {
  try {
    const { sessionId, phoneNumber, text } = await req.json();

    if (!sessionId || !phoneNumber || text === undefined) {
      return new Response(
        "END Invalid request. Missing sessionId, phoneNumber, or text.",
        { status: 400, headers: { "Content-Type": "text/plain" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const parts = text === "" ? [] : text.split("*");

    // ── Main menu (initial request) ───────────────────────────────────────
    if (parts.length === 0) {
      return new Response(
        "CON Welcome to ClassAI Recovery\n\n" +
          "1. Reset Password\n" +
          "2. Check Account Status\n\n" +
          "Reply with option number:",
        { headers: { "Content-Type": "text/plain" } }
      );
    }

    const option = parts[0];

    // ── Option 1: Reset Password ──────────────────────────────────────────
    if (option === "1") {
      // Step 1: Ask for phone number
      if (parts.length === 1) {
        return new Response(
          "CON Enter your registered phone number:",
          { headers: { "Content-Type": "text/plain" } }
        );
      }

      // Step 2: Phone number provided — look up teacher and send OTP
      if (parts.length === 2) {
        const enteredPhone = parts[1];

        // Look up teacher by phone number
        const { data: teacher, error } = await supabase
          .from("teachers")
          .select("id, email, school_id, phone")
          .eq("phone", enteredPhone)
          .maybeSingle();

        if (error || !teacher) {
          return new Response(
            "CON Phone number not found in our records.\n" +
              "Please check and try again, or contact your school admin.",
            { headers: { "Content-Type": "text/plain" } }
          );
        }

        // Generate and store OTP
        const otp = generateOtp();
        otpStore.set(sessionId, {
          otp,
          phone: enteredPhone,
          expiresAt: new Date(Date.now() + 5 * 60 * 1000), // 5 minutes
        });

        // In a real deployment, send the OTP via SMS (Termii/BulkSMS Nigeria).
        // For Phase 8, log it so the user can see it.
        console.log(
          `[USSD] OTP for ${enteredPhone} (teacher ${teacher.id}): ${otp}`
        );

        // Also store OTP in a pending_recovery_requests table if it exists
        const { error: insertError } = await supabase
          .from("pending_recovery_requests")
          .upsert(
            {
              teacher_id: teacher.id,
              phone: enteredPhone,
              otp,
              expires_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
              used: false,
            },
            { onConflict: "teacher_id" }
          )
          .maybeSingle();

        if (insertError) {
          // Table may not exist yet — non-critical, log and continue
          console.warn(
            `[USSD] Could not store OTP in pending_recovery_requests: ${insertError.message}`
          );
        }

        return new Response(
          "CON An OTP has been sent to your phone via SMS.\n\n" +
            "Enter the 6-digit OTP:",
          { headers: { "Content-Type": "text/plain" } }
        );
      }

      // Step 3: OTP provided — verify and return recovery info
      if (parts.length === 3) {
        const enteredOtp = parts[2];
        const session = otpStore.get(sessionId);

        if (!session) {
          return new Response(
            "END Session expired or invalid. Please start again by dialing the USSD code.",
            { headers: { "Content-Type": "text/plain" } }
          );
        }

        if (new Date() > session.expiresAt) {
          otpStore.delete(sessionId);
          return new Response(
            "END OTP expired. Please start again by dialing the USSD code.",
            { headers: { "Content-Type": "text/plain" } }
          );
        }

        if (enteredOtp !== session.otp) {
          return new Response(
            "CON Invalid OTP. Please try again, or dial the USSD code to start over.",
            { headers: { "Content-Type": "text/plain" } }
          );
        }

        // OTP verified — generate a recovery code
        const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        let recoveryCode = "";
        for (let i = 0; i < 12; i++) {
          recoveryCode += chars.charAt(
            Math.floor(Math.random() * chars.length)
          );
        }

        // Look up teacher again to get their ID
        const { data: teacher } = await supabase
          .from("teachers")
          .select("id, email")
          .eq("phone", session.phone)
          .maybeSingle();

        if (teacher) {
          const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
          await supabase.from("recovery_codes").insert({
            teacher_id: teacher.id,
            email: teacher.email,
            code: recoveryCode,
            generated_by_admin_id: null,
            expires_at: expiresAt.toISOString(),
            used: false,
            attempts: 0,
          });
        }

        // Clean up session
        otpStore.delete(sessionId);

        return new Response(
          "END Password reset initiated successfully.\n\n" +
            "Your recovery code: " + recoveryCode + "\n\n" +
            "Use this code in the ClassAI app to reset your password.\n" +
            "The code expires in 24 hours.\n\n" +
            "Thank you for using ClassAI Recovery.",
          { headers: { "Content-Type": "text/plain" } }
        );
      }

      // More input than expected
      return new Response(
        "END Invalid input. Please start again by dialing the USSD code.",
        { headers: { "Content-Type": "text/plain" } }
      );
    }

    // ── Option 2: Check Account Status ────────────────────────────────────
    if (option === "2") {
      // Step 1: Ask for phone number
      if (parts.length === 1) {
        return new Response(
          "CON Enter your registered phone number to check account status:",
          { headers: { "Content-Type": "text/plain" } }
        );
      }

      // Step 2: Look up account
      if (parts.length === 2) {
        const enteredPhone = parts[1];

        const { data: teacher } = await supabase
          .from("teachers")
          .select("id, email, role, is_active, school_id")
          .eq("phone", enteredPhone)
          .maybeSingle();

        if (!teacher) {
          return new Response(
            "CON Phone number not found. Please check and try again.",
            { headers: { "Content-Type": "text/plain" } }
          );
        }

        // Look up school name
        const { data: school } = await supabase
          .from("schools")
          .select("school_name, subscription_tier")
          .eq("id", teacher.school_id)
          .maybeSingle();

        const status = teacher.is_active ? "Active" : "Inactive";
        const schoolName = school?.school_name ?? "Unknown";
        const tier = school?.subscription_tier ?? "Unknown";

        return new Response(
          "END Account Status:\n\n" +
            "Name: " + (teacher.email ?? "N/A") + "\n" +
            "Role: " + teacher.role + "\n" +
            "Status: " + status + "\n" +
            "School: " + schoolName + "\n" +
            "Plan: " + tier + "\n\n" +
            "Thank you for using ClassAI.",
          { headers: { "Content-Type": "text/plain" } }
        );
      }

      return new Response(
        "END Invalid input. Please start again.",
        { headers: { "Content-Type": "text/plain" } }
      );
    }

    // ── Invalid option ────────────────────────────────────────────────────
    return new Response(
      "CON Invalid option. Please choose:\n\n" +
        "1. Reset Password\n" +
        "2. Check Account Status",
      { headers: { "Content-Type": "text/plain" } }
    );
  } catch (err) {
    console.error("[USSD] Error:", err.message);
    return new Response(
      "END An error occurred. Please try again later.",
      { status: 500, headers: { "Content-Type": "text/plain" } }
    );
  }
});
