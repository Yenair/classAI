import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

serve(async (_req) => {
  console.log("send-verification-code called");
  return new Response(
    JSON.stringify({ success: true }),
    { headers: { "Content-Type": "application/json" } }
  );
});