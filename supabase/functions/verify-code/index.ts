import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts";

// Convert a plain string secret into a CryptoKey for HS256 JWT verification.
function getHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
}

serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Parse body first
    const { code, email: bodyEmail, mode, device_id, platform } = await req.json();

    if (!code || typeof code !== "string" || !/^\d{6}$/.test(code)) {
      return new Response(
        JSON.stringify({ error: "A 6-digit verification code is required." }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    let email: string;
    let claims: Record<string, unknown> | undefined;

    if (mode === "signup") {
      // ── Signup mode: verify code by email (no JWT needed) ────────────
      if (!bodyEmail) {
        return new Response(
          JSON.stringify({ error: "Missing required field: email" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }
      email = bodyEmail.toLowerCase();
    } else {
      // ── Normal mode: verify JWT (from x-classai-jwt custom header) ───
      const classaiJwt = req.headers.get("x-classai-jwt");
      if (!classaiJwt) {
        return new Response(
          JSON.stringify({ error: "Missing authentication token" }),
          { status: 401, headers: { "Content-Type": "application/json" } }
        );
      }

      const jwtSecret = Deno.env.get("JWT_SECRET");
      if (!jwtSecret) {
        return new Response(
          JSON.stringify({ error: "Server misconfiguration: JWT_SECRET not set" }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }

      try {
        const cryptoKey = await getHmacKey(jwtSecret);
        claims = await verify(classaiJwt, cryptoKey, "HS256");
      } catch {
        return new Response(
          JSON.stringify({ error: "Invalid or expired JWT" }),
          { status: 401, headers: { "Content-Type": "application/json" } }
        );
      }

      if (!claims!.sub) {
        return new Response(
          JSON.stringify({ error: "Invalid token: no subject claim" }),
          { status: 401, headers: { "Content-Type": "application/json" } }
        );
      }

      const teacherId = claims!.sub as string;

      // Fetch teacher email
      const { data: teacher, error: teacherError } = await supabase
        .from("teachers")
        .select("id, email")
        .eq("id", teacherId)
        .maybeSingle();

      if (teacherError || !teacher) {
        return new Response(
          JSON.stringify({ error: "Teacher not found." }),
          { status: 404, headers: { "Content-Type": "application/json" } }
        );
      }

      email = teacher.email;
    }

    // Find the latest unused code for this email
    const { data: codeRecords, error: fetchError } = await supabase
      .from("verification_codes")
      .select("*")
      .eq("email", email)
      .eq("used", false)
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(1);

    if (fetchError) {
      console.error("[verify-code] fetch error:", fetchError);
      return new Response(
        JSON.stringify({ error: "Failed to look up verification code." }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const record = codeRecords?.[0];

    if (!record) {
      return new Response(
        JSON.stringify({ error: "No active verification code found. Please request a new code." }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Check attempts limit (max 3) ───────────────────────────────────────
    if (record.attempts >= 3) {
      await supabase
        .from("verification_codes")
        .update({ used: true })
        .eq("id", record.id);

      return new Response(
        JSON.stringify({ error: "Too many failed attempts. Please request a new code." }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Verify the code ────────────────────────────────────────────────────
    if (record.code !== code) {
      await supabase
        .from("verification_codes")
        .update({ attempts: record.attempts + 1 })
        .eq("id", record.id);

      return new Response(
        JSON.stringify({ error: "Invalid verification code. Please try again." }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Mark code as used ──────────────────────────────────────────────────
    await supabase
      .from("verification_codes")
      .update({ used: true })
      .eq("id", record.id);

    // ── For normal mode: handle device registration and email verification ─
    if (mode !== "signup") {
      const teacherId = claims!.sub as string;

      // Fetch the current teacher to check global email_verified status
      const { data: teacherData, error: teacherFetchError } = await supabase
        .from("teachers")
        .select("email_verified")
        .eq("id", teacherId)
        .maybeSingle();

      if (teacherFetchError) {
        console.error("[verify-code] teacher fetch error:", teacherFetchError);
        return new Response(
          JSON.stringify({ error: "Failed to fetch teacher details." }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }

      const isGloballyVerified = teacherData?.email_verified === true;

      if (isGloballyVerified) {
        // Teacher is already globally verified — this is a "new device"
        // verification. Do NOT change email_verified, just register the device.
        if (device_id) {
          const { error: upsertError } = await supabase
            .from("teacher_devices")
            .upsert(
              {
                teacher_id: teacherId,
                device_id: device_id,
                platform: platform || null,
                last_active: new Date().toISOString(),
                is_active: true,
              },
              { onConflict: "teacher_id, device_id" }
            );

          if (upsertError) {
            console.error("[verify-code] device upsert error:", upsertError);
            return new Response(
              JSON.stringify({ error: "Failed to register device. Please try again." }),
              { status: 500, headers: { "Content-Type": "application/json" } }
            );
          }
        }
      } else {
        // Teacher is not globally verified — mark as verified AND register device
        const { error: updateError } = await supabase
          .from("teachers")
          .update({ email_verified: true })
          .eq("id", teacherId);

        if (updateError) {
          console.error("[verify-code] teacher update error:", updateError);
          return new Response(
            JSON.stringify({ error: "Failed to verify email. Please try again." }),
            { status: 500, headers: { "Content-Type": "application/json" } }
          );
        }

        if (device_id) {
          await supabase
            .from("teacher_devices")
            .upsert(
              {
                teacher_id: teacherId,
                device_id: device_id,
                platform: platform || null,
                last_active: new Date().toISOString(),
                is_active: true,
              },
              { onConflict: "teacher_id, device_id" }
            );
        }
      }
    }

    // ── Return success ─────────────────────────────────────────────────────
    return new Response(
      JSON.stringify({
        success: true,
        message: "Email verified successfully.",
        email_verified: true,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[verify-code] error:", err);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
