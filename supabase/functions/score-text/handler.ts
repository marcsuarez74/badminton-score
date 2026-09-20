// Edge Function score-text — logique pure testable (Db injecté), même
// discipline que sync (ADR-007). Lecture seule publique (RLS SELECT anon) :
// renvoie le score du match actif le plus récent du canal, en texte pour un
// bot Twitch (commande custom API de StreamElements/Nightbot).
export interface ScoreRow {
  status: string;
  currentSet: number;
  scoreMe: number;
  scoreOpp: number;
  setsMe: number;
  setsOpp: number;
  config: { targetScore: number; winBy: number; cap: number; setsToWin: number } | null;
}

export interface Db {
  // Match actif le plus récent du canal ; fallback : le plus récent tout statut.
  latestMatch(channel: string, activeOnly: boolean): Promise<ScoreRow | null>;
}

export function plain(status: number, text: string): Response {
  return new Response(text, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function normalizeSet(v: unknown): number | null {
  return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null;
}

// "Marc 5-3 Paul · SET 2 · Sets 1-0" — compact, lisible dans un chat Twitch.
export function formatScore(row: ScoreRow, name1: string, name2: string): string {
  const sets = `Sets ${row.setsMe}-${row.setsOpp}`;
  const base = `${name1} ${row.scoreMe}-${row.scoreOpp} ${name2} · SET ${row.currentSet} · ${sets}`;
  return row.status === "match_finished" ? `${base} · Terminé` : base;
}

export async function handleScoreText(req: Request, db: Db): Promise<Response> {
  if (req.method !== "GET") return plain(405, "method");
  const u = new URL(req.url);
  const channel = (u.searchParams.get("channel") || "marc").slice(0, 32);
  if (!/^[A-Za-z0-9_-]+$/.test(channel)) return plain(400, "channel");
  const name1 = (u.searchParams.get("name1") || "MOI").slice(0, 24);
  const name2 = (u.searchParams.get("name2") || "LUI").slice(0, 24);

  const active = await db.latestMatch(channel, true);
  if (active) {
    const sane = [active.currentSet, active.scoreMe, active.scoreOpp, active.setsMe, active.setsOpp].every((v) => v !== null);
    if (sane) return plain(200, formatScore(active as ScoreRow, name1, name2));
  }
  const any = await db.latestMatch(channel, false);
  if (any) {
    const sane = [any.currentSet, any.scoreMe, any.scoreOpp, any.setsMe, any.setsOpp].every((v) => v !== null);
    if (sane) return plain(200, formatScore(any as ScoreRow, name1, name2));
  }
  return plain(200, "Pas de match en cours");
}

// Garde-fou de forme utilisé par les tests : rejette les lignes incomplètes.
export function isValidRow(r: Record<string, unknown>): boolean {
  return normalizeSet(r.currentSet) !== null && normalizeSet(r.scoreMe) !== null &&
         normalizeSet(r.scoreOpp) !== null && normalizeSet(r.setsMe) !== null &&
         normalizeSet(r.setsOpp) !== null && typeof r.status === "string";
}
