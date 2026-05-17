import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

serve(async (req) => {
  try {
    // ── Auth check: requires a valid user JWT (automatically added by Supabase client) ──
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: missing JWT" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    const { prompt } = await req.json();
    if (!prompt) {
      return new Response(
        JSON.stringify({ error: "Missing required field: prompt" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const apiKey = Deno.env.get("DEEPSEEK_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "DEEPSEEK_API_KEY not configured" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── Call DeepSeek API ─────────────────────────────────────────────────
    const response = await fetch("https://api.deepseek.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "deepseek-chat",
        messages: [
          {
            role: "system",
            content: "You are a lesson and exam generator for Nigerian secondary school teachers. Return ONLY valid JSON without markdown formatting.",
          },
          { role: "user", content: prompt },
        ],
        temperature: 0.7,
        max_tokens: 4096,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`[deepseek-proxy] API error ${response.status}: ${errorText}`);
      return new Response(
        JSON.stringify({ error: `DeepSeek API error: ${response.status}` }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }

    const data = await response.json();
    const generatedText = data.choices?.[0]?.message?.content || "";

    // Try to parse as JSON
    let generatedJson: Record<string, unknown>;
    try {
      generatedJson = JSON.parse(generatedText);
    } catch {
      // If the response isn't valid JSON, return the raw text
      generatedJson = { text: generatedText };
    }

    return new Response(
      JSON.stringify({ generatedJson }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error(`[deepseek-proxy] Error: ${err.message}`);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
