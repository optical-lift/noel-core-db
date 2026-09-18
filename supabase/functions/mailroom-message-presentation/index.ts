import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

Deno.serve((request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  return new Response(JSON.stringify({
    error: "Mailroom presentation endpoint retired. Use Communication Event presentation.",
  }), {
    status: 410,
    headers: {
      ...corsHeaders,
      "content-type": "application/json",
      "cache-control": "private, no-store",
    },
  });
});
