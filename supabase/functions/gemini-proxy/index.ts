import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { validateTokenVersion } from "../_shared/validate_token.ts";

/** Tries to recover JSON from model output that is not strict JSON (e.g.
 *  fenced with ```json or wrapped in prose). Returns null when nothing
 *  parseable is found. */
function extractJsonBlock(text: string): Record<string, unknown> | null {
  const trimmed = text.trim();
  const fence = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidate = fence ? fence[1].trim() : trimmed;

  const firstBrace = candidate.indexOf("{");
  const lastBrace = candidate.lastIndexOf("}");
  if (firstBrace !== -1 && lastBrace > firstBrace) {
    try {
      const parsed = JSON.parse(candidate.slice(firstBrace, lastBrace + 1));
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      // not a JSON object — try an array below
    }
  }

  const firstBracket = candidate.indexOf("[");
  const lastBracket = candidate.lastIndexOf("]");
  if (firstBracket !== -1 && lastBracket > firstBracket) {
    try {
      const parsed = JSON.parse(candidate.slice(firstBracket, lastBracket + 1));
      if (Array.isArray(parsed)) {
        // A bare weeks array — wrap it in the shape the app expects.
        return { weeks: parsed };
      }
    } catch {
      // not a JSON array either
    }
  }
  return null;
}

serve(async (req) => {
  try {
    // ── Auth check: validate custom JWT ─────────────────────────────────
    const classaiJwt = req.headers.get("x-classai-jwt");
    if (!classaiJwt) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: missing JWT" }),
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

    const token = classaiJwt;
    try {
      await validateTokenVersion(
        token,
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        jwtSecret,
      );
    } catch (err) {
      const { error, code, status } = err as { error: string; code: string; status: number };
      return new Response(
        JSON.stringify({ error, code }),
        { status, headers: { "Content-Type": "application/json" } }
      );
    }

    const { prompt } = await req.json();
    if (!prompt) {
      return new Response(
        JSON.stringify({ error: "Missing required field: prompt" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "GEMINI_API_KEY not configured" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Call Gemini API ────────────────────────────────────────────────────
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [
            {
              role: "user",
              parts: [
                {
                  text: `You are a lesson and exam generator for Nigerian secondary school teachers. Return ONLY valid JSON without markdown formatting.\n\n${prompt}`,
                },
              ],
            },
          ],
          generationConfig: {
            temperature: 0.7,
            maxOutputTokens: 4096,
          },
        }),
      }
    );

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`[gemini-proxy] API error ${response.status}: ${errorText}`);
      return new Response(
        JSON.stringify({ error: `Gemini API error: ${response.status}` }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }

    const data = await response.json();
    const generatedText =
      data?.candidates?.[0]?.content?.parts?.[0]?.text || "";

    // Try to parse as JSON
    let generatedJson: Record<string, unknown>;
    try {
      generatedJson = JSON.parse(generatedText);
    } catch {
      // If the response isn't valid JSON, recover an embedded JSON block
      // (markdown fences / prose wrapping) before falling back to raw text.
      generatedJson = extractJsonBlock(generatedText) ?? { text: generatedText };
    }

    return new Response(
      JSON.stringify({ generatedJson }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error(`[gemini-proxy] Error: ${err.message}`);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
