import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateTokenVersion } from "../_shared/validate_token.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const REPLICATE_API_TOKEN = Deno.env.get("REPLICATE_API_TOKEN");

// Latest confirmed version of openai/gpt-image-2 on Replicate
const GPT_IMAGE_2_VERSION = "225c978a7f938acc350564c4548ddc2476bfb33364bec6b5422227f55ce56bd3";
const REPLICATE_BASE = "https://api.replicate.com/v1";

interface DiagramRequest {
  description: string;
  style?: string; // e.g. "educational", "scientific", "simplified"
}

interface DiagramResult {
  index: number;
  description: string;
  imageUrl: string | null;
  error?: string;
}

serve(async (req) => {
  try {
    // ── 1. Validate JWT ────────────────────────────────────────────────
    const classaiJwt = req.headers.get("x-classai-jwt");
    if (!classaiJwt) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid JWT header" }),
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

    // ── 2. Parse request ───────────────────────────────────────────────
    if (!GEMINI_API_KEY) {
      return new Response(
        JSON.stringify({ error: "Gemini API key not configured" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const { diagrams, lessonId, oldUrl } = await req.json() as {
      diagrams: DiagramRequest[];
      lessonId?: string;
      oldUrl?: string;
    };

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

    // ── 2b. Initialise Supabase admin client for Storage ──────────────
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const BUCKET_NAME = "diagrams";

    // ── 3. Generate each diagram via Replicate/gpt-image-2, fallback to Gemini ──
    const results: DiagramResult[] = [];

    for (let i = 0; i < diagrams.length; i++) {
      const { description, style = "educational" } = diagrams[i];
      const prompt = `Create a clear, ${style} diagram for classroom use: ${description}. ` +
        "Use simple labels, appropriate colors, and ensure the diagram is easy to understand " +
        "for secondary school students. Format as a clean visual diagram.";

      let providerUsed = "none";
      let imageBytes: Uint8Array | null = null;
      let lastError: string | undefined;

      // ── 3a. Try Replicate/gpt-image-2 (primary) ──────────────────────
      if (REPLICATE_API_TOKEN) {
        try {
          const replicateResult = await generateViaReplicate(prompt);
          if (replicateResult) {
            imageBytes = replicateResult;
            providerUsed = "replicate";
          } else {
            lastError = "Replicate returned no output";
            console.warn(`[generate-diagram] Index ${i}: Replicate returned no output, will fall back to Gemini`);
          }
        } catch (repErr) {
          lastError = repErr instanceof Error ? repErr.message : "Replicate error";
          console.warn(`[generate-diagram] Index ${i}: Replicate failed (${lastError}), falling back to Gemini`);
        }
      } else {
        console.log(`[generate-diagram] Index ${i}: REPLICATE_API_TOKEN not set, using Gemini directly`);
      }

      // ── 3b. Fallback to Gemini Imagen 4 Fast ─────────────────────────
      if (!imageBytes) {
        try {
          const geminiResult = await generateViaGemini(prompt);
          if (geminiResult) {
            imageBytes = geminiResult;
            providerUsed = "gemini_fallback";
          } else {
            if (!lastError) lastError = "Gemini returned no image data";
            console.warn(`[generate-diagram] Index ${i}: Gemini fallback also returned no output`);
          }
        } catch (gemErr) {
          const geminiError = gemErr instanceof Error ? gemErr.message : "Gemini fallback error";
          lastError = lastError ? `${lastError}; Gemini also failed: ${geminiError}` : geminiError;
          console.error(`[generate-diagram] Index ${i}: Gemini fallback also failed: ${geminiError}`);
        }
      }

      console.log(`[generate-diagram] Index ${i} served by: ${providerUsed}`);

      if (imageBytes) {
        // ── Upload to Supabase Storage ───────────────────────────────
        try {
          const timestamp = Date.now(); // millisecond precision
          const lessonPart = lessonId ?? `unknown_${i}`;
          const fileName = `${lessonPart}_${timestamp}.png`;

          const { data: uploadData, error: uploadError } = await supabase
            .storage
            .from(BUCKET_NAME)
            .upload(fileName, imageBytes, {
              contentType: "image/png",
              upsert: false,
            });

          if (uploadError) {
            throw new Error(`Storage upload failed: ${uploadError.message}`);
          }

          // Get the public URL
          const { data: publicUrlData } = supabase
            .storage
            .from(BUCKET_NAME)
            .getPublicUrl(fileName);

          const imageUrl = publicUrlData.publicUrl;

          // ── Clean up old object AFTER successful upload ────────────
          if (oldUrl && oldUrl.trim().length > 0) {
            // Extract the object path from the old URL
            const oldPath = extractStoragePath(oldUrl, BUCKET_NAME);
            if (oldPath) {
              const { error: deleteError } = await supabase
                .storage
                .from(BUCKET_NAME)
                .remove([oldPath]);

              if (deleteError) {
                // Log but don't fail — orphaned old file is minor cleanup
                console.warn(
                  `[generate-diagram] Index ${i}: failed to delete old object "${oldPath}": ${deleteError.message}`,
                );
              } else {
                console.log(
                  `[generate-diagram] Index ${i}: deleted old object "${oldPath}"`,
                );
              }
            }
          }

          results.push({
            index: i,
            description,
            imageUrl,
          });
        } catch (uploadErr) {
          // Upload failed (e.g. image >5MB, Storage error, etc.)
          const uploadMsg = uploadErr instanceof Error ? uploadErr.message : "Storage upload failed";
          console.error(`[generate-diagram] Index ${i}: ${uploadMsg}`);
          results.push({
            index: i,
            description,
            imageUrl: null,
            error: uploadMsg,
          });
        }
      } else {
        results.push({
          index: i,
          description,
          imageUrl: null,
          error: lastError ?? "All image providers failed",
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

// ---------------------------------------------------------------------------
// Replicate / gpt-image-2 helper
// ---------------------------------------------------------------------------
async function generateViaReplicate(prompt: string): Promise<Uint8Array | null> {
  // Step 1: Create the prediction
  const createResponse = await fetch(`${REPLICATE_BASE}/predictions`, {
    method: "POST",
    headers: {
      "Authorization": `Token ${REPLICATE_API_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      version: GPT_IMAGE_2_VERSION,
      input: {
        prompt,
        quality: "low",
        aspect_ratio: "1:1",
        output_format: "png",
        number_of_images: 1,
      },
    }),
  });

  if (!createResponse.ok) {
    const errBody = await createResponse.text();
    throw new Error(`Replicate API returned ${createResponse.status}: ${errBody}`);
  }

  let prediction = await createResponse.json();

  // Step 2: Poll until completion (30-second wall-clock budget)
  const startTime = Date.now();
  const POLL_TIMEOUT_MS = 30_000;
  const POLL_INTERVAL_MS = 1_000;

  while (prediction.status === "starting" || prediction.status === "processing") {
    if (Date.now() - startTime > POLL_TIMEOUT_MS) {
      throw new Error("Replicate prediction timed out after 30s");
    }

    await sleep(POLL_INTERVAL_MS);

    const getResponse = await fetch(`${REPLICATE_BASE}/predictions/${prediction.id}`, {
      headers: {
        "Authorization": `Token ${REPLICATE_API_TOKEN}`,
      },
    });

    if (!getResponse.ok) {
      const errBody = await getResponse.text();
      throw new Error(`Replicate poll returned ${getResponse.status}: ${errBody}`);
    }

    prediction = await getResponse.json();
  }

  // Step 3: Check outcome
  if (prediction.status === "failed") {
    throw new Error(`Replicate prediction failed: ${prediction.error ?? "unknown error"}`);
  }

  if (prediction.status !== "succeeded") {
    throw new Error(`Replicate prediction ended with unexpected status: ${prediction.status}`);
  }

  // Step 4: Extract and fetch the output image
  const outputUrls = prediction.output as string[] | null;
  if (!outputUrls || outputUrls.length === 0) {
    return null;
  }

  const imageUrl = outputUrls[0];
  const imageResponse = await fetch(imageUrl);

  if (!imageResponse.ok) {
    throw new Error(`Failed to fetch Replicate output image: ${imageResponse.status}`);
  }

  // Return raw bytes — no base64 encoding needed
  const imageBytes = await imageResponse.arrayBuffer();
  return new Uint8Array(imageBytes);
}

// ---------------------------------------------------------------------------
// Gemini Imagen 4 Fast helper
// ---------------------------------------------------------------------------
async function generateViaGemini(prompt: string): Promise<Uint8Array | null> {
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
    throw new Error(`Gemini API returned ${response.status}: ${errText}`);
  }

  const geminiResult = await response.json();
  const base64Image = geminiResult?.predictions?.[0]?.bytesBase64Encoded as string | null;
  if (!base64Image) return null;

  // Decode base64 to raw bytes for Storage upload
  const binaryStr = atob(base64Image);
  const bytes = new Uint8Array(binaryStr.length);
  for (let i = 0; i < binaryStr.length; i++) {
    bytes[i] = binaryStr.charCodeAt(i);
  }
  return bytes;
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Extract the object path from a Supabase Storage public URL.
 * e.g. "https://<project>.supabase.co/storage/v1/object/public/diagrams/abc.png"
 *      -> "abc.png"
 */
function extractStoragePath(publicUrl: string, bucketName: string): string | null {
  try {
    const marker = `/object/public/${bucketName}/`;
    const idx = publicUrl.indexOf(marker);
    if (idx === -1) return null;
    return publicUrl.substring(idx + marker.length);
  } catch {
    return null;
  }
}
