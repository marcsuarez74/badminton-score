// Edge Function names — réglages d'affichage d'un canal : type de match
// (simple/double/mixte) et noms des joueurs (2 en simple, 4 en double/mixte).
// - GET ?channel=X : lecture publique (l'overlay et la page portail en
//   dépendent, tout est public par design — cf. Confidentialité du guide).
// - POST (header X-Device-Key) : chaque device ne modifie que SES noms.
import { json } from "../sync/handler.ts";

export interface Names {
  format: string;
  name1: string;
  name1b: string;
  name2: string;
  name2b: string;
}

export interface NamesDb {
  // Empreinte de la clé attendue ; renvoie le device propriétaire si trouvé.
  getDeviceHash(expected: string): Promise<{ deviceId: string | null; error: string | null }>;
  getNames(channel: string): Promise<Names | null>;
  upsertNames(deviceId: string, fields: Names): Promise<{ error: string | null }>;
}

const FORMATS = ["simple", "double", "mixte"];

function validName(s: unknown): boolean {
  return typeof s === "string" && s.trim().length >= 1 && s.trim().length <= 24;
}

export async function handleNamesGet(req: Request, db: NamesDb): Promise<Response> {
  if (req.method !== "GET") return json(405, { error: "method" });
  const u = new URL(req.url);
  const channel = (u.searchParams.get("channel") || "").slice(0, 32);
  if (!/^[A-Za-z0-9_-]+$/.test(channel)) return json(400, { error: "channel" });
  const names = await db.getNames(channel);
  if (!names) return json(404, { error: "canal inconnu" });
  return json(200, { channel, ...names });
}

export async function handleNamesPost(req: Request, db: NamesDb): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method" });
  const key = req.headers.get("x-device-key");
  if (typeof key !== "string" || key.length < 16) return json(401, { error: "unauthorized" });
  const dev = await db.getDeviceHash(key);
  if (dev.error || !dev.deviceId) return json(401, { error: "unauthorized" });

  let b: Record<string, unknown>;
  try { b = await req.json() as Record<string, unknown>; } catch { return json(400, { error: "body" }); }
  const format = b.format;
  if (typeof format !== "string" || !FORMATS.includes(format)) return json(400, { error: "format" });

  // Simple : 2 joueurs ; double/mixte : 4 (les partenaires sont requis).
  const name1 = (b.name1 as string)?.trim();
  const name2 = (b.name2 as string)?.trim();
  const name1b = (b.name1b as string)?.trim() ?? "";
  const name2b = (b.name2b as string)?.trim() ?? "";
  if (!validName(name1) || !validName(name2)) return json(400, { error: "name" });
  if (format === "simple") {
    if (!validNamesOpt([name1b, name2b])) return json(400, { error: "name" });
  } else if (!validName(name1b) || !validName(name2b)) {
    return json(400, { error: "partenaires requis" });
  }
  const fields: Names = {
    format,
    name1: name1!,
    name1b: format === "simple" ? "" : name1b!,
    name2: name2!,
    name2b: format === "simple" ? "" : name2b!,
  };
  const up = await db.upsertNames(dev.deviceId, fields);
  if (up.error) return json(500, { error: "db" });
  return json(200, { ok: true });
}

// En simple les champs partenaires sont facultatifs mais, s'ils sont fournis,
// ils doivent rester des noms valides.
function validNamesOpt(names: string[]): boolean {
  return names.every((n) => n === "" || validName(n));
}
