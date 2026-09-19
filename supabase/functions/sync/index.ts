import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Les Edge Functions reçoivent automatiquement SUPABASE_URL et
// SUPABASE_SERVICE_ROLE_KEY (https://supabase.com/docs/guides/functions).
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }
  let body: unknown;
  try { body = await req.json(); } catch { body = { raw: "unparseable" }; }
  const { data, error } = await supabase
    .from("poc_events").insert({ payload: body }).select("id").single();
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
  return new Response(JSON.stringify({ ok: true, id: data.id }), {
    status: 200, headers: { "Content-Type": "application/json" },
  });
});
