import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");

interface DiagramRequest {
  description: string;
  style?: string; // e.g. "educational", "scientific", "simplified"
}

interface DiagramResult {
  index: number;
  description: string;
  base64: string | null;
  error?: string;
}

serve(async (req) => {
  try {
    // ── 1. Validate JWT ────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid Authorization header" }),
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

    const token = authHeader.replace("Bearer ", "");
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

    // ── 2. Parse request ───────────────────────────────────────────────
    if (!GEMINI_API_KEY) {
      return new Response(
        JSON.stringify({ error: "Gemini API key not configured" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const { diagrams } = await req.json() as { diagrams: DiagramRequest[] };

    if (!Array.isArray(diagrams) || diagrams.length === 0) {
      return new Response(
        JSON.stringify({ error: "Request must include a `diagrams` array with at least one entry" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (diagrams.length > 5) {
      return new Response(
        JSON.stringify({ error: "Maximum of 5 diagrams per request" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── 3. Generate each diagram via Gemini Imagen 4 Fast ───────────────
    const results: DiagramResult[] = [];

    for (let i = 0; i < diagrams.length; i++) {
      const { description, style = "educational" } = diagrams[i];

      try {
        // Build prompt for educational diagram
        const prompt = `Create a clear, ${style} diagram for classroom use: ${description}. ` +
          "Use simple labels, appropriate colors, and ensure the diagram is easy to understand " +
          "for secondary school students. Format as a clean visual diagram.";

        const response = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/imagen-4-fast:generateImages?key=${GEMINI_API_KEY}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              instances: [{ prompt }],
              parameters: {
                sampleCount: 1,
                aspectRatio: "4:3",
              },
            }),
          }
        );

        if (!response.ok) {
          const errText = await response.text();
          console.error(`[generate-diagram] Gemini API error for index ${i}:`, errText);
          results.push({
            index: i,
            description,
            base64: null,
            error: `Gemini API returned status ${response.status}`,
          });
          continue;
        }

        const geminiResult = await response.json();
        const imageData = geminiResult?.predictions?.[0]?.bytesBase64Encoded as string | undefined;

        if (!imageData) {
          console.warn(`[generate-diagram] No image data for index ${i}:`, JSON.stringify(geminiResult));
          results.push({
            index: i,
            description,
            base64: null,
            error: "No image data returned from Gemini",
          });
          continue;
        }

        results.push({
          index: i,
          description,
          base64: imageData,
        });
      } catch (genErr) {
        console.error(`[generate-diagram] Exception for index ${i}:`, genErr);
        results.push({
          index: i,
          description,
          base64: null,
          error: genErr instanceof Error ? genErr.message : "Unknown error",
        });
      }
    }

    // ── 4. Return results ──────────────────────────────────────────────
    return new Response(
      JSON.stringify({ results }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[generate-diagram] Fatal error:", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : "Internal server error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
