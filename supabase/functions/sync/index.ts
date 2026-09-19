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
  const text = await req.text();
  let body: unknown;
  try { body = JSON.parse(text); } catch { body = { raw: text.slice(0, 2048) }; }
  const { data, error } = await supabase
    .from("poc_events").insert({ payload: body }).select("id").single();
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
  return new Response(JSON.stringify({ ok: true, id: data.id, lastAcceptedSequence: data.id }), {
    status: 200, headers: { "Content-Type": "application/json" },
  });
});
