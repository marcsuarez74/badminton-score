import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleNamesGet, handleNamesPost, type NamesDb } from "./handler.ts";

// Service role : lecture/écriture devices (noms, format) — table sans accès
// anon (le hash de clé y est stocké, il ne doit jamais sortir).
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const db: NamesDb = {
  async getDeviceHash(expected) {
    const { data, error } = await supabase.from("devices")
      .select("id").eq("device_key_hash", await sha256Hex(expected)).maybeSingle();
    if (error) return { deviceId: null, error: String(error.message) };
    return { deviceId: data ? String(data.id) : null, error: null };
  },
  async getNames(channel) {
    const { data, error } = await supabase.from("devices")
      .select("format, name1, name1b, name2, name2b").eq("channel", channel).maybeSingle();
    if (error || !data) return null;
    return {
      format: String(data.format ?? "simple"),
      name1: String(data.name1 ?? ""),
      name1b: String(data.name1b ?? ""),
      name2: String(data.name2 ?? ""),
      name2b: String(data.name2b ?? ""),
    };
  },
  async upsertNames(deviceId, fields) {
    const { error } = await supabase.from("devices").update({
      format: fields.format,
      name1: fields.name1,
      name1b: fields.name1b,
      name2: fields.name2,
      name2b: fields.name2b,
    }).eq("id", deviceId);
    return { error: error ? String(error.message) : null };
  },
};

async function sha256Hex(s: string): Promise<string> {
  const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// CORS : la page portail (GitHub Pages) et l'overlay appellent cette fonction
// cross-origin — sans ces en-têtes, le preflight OPTIONS échoue et le navigateur
// rapporte « réseau indisponible ».
const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "X-Device-Key, Content-Type",
  "Access-Control-Allow-Methods": "GET, POST",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  const res = req.method === "GET" ? await handleNamesGet(req, db) : await handleNamesPost(req, db);
  for (const [k, v] of Object.entries(CORS)) res.headers.set(k, v);
  return res;
});
