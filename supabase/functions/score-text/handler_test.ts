import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { formatScore, handleScoreText, type Db, type ScoreRow } from "./handler.ts";

function row(over: Partial<ScoreRow> = {}): ScoreRow {
  return {
    status: "active", currentSet: 2, scoreMe: 5, scoreOpp: 3, setsMe: 1, setsOpp: 0,
    config: { targetScore: 21, winBy: 2, cap: 30, setsToWin: 2 },
    ...over,
  };
}

function makeDb(rows: ScoreRow[]): Db {
  return {
    async latestMatch(_channel, activeOnly) {
      return rows.find((r) => !activeOnly || r.status === "active") ?? null;
    },
  };
}

function get(url: string, db: Db): Promise<Response> {
  return handleScoreText(new Request(url, { method: "GET" }), db);
}

Deno.test("405 si POST", async () => {
  const res = await handleScoreText(new Request("https://fn.test/score-text", { method: "POST" }), makeDb([]));
  assertEquals(res.status, 405);
});

Deno.test("400 si canal invalide", async () => {
  const res = await get("https://fn.test/score-text?channel=..%2Fetc", makeDb([]));
  assertEquals(res.status, 400);
});

Deno.test("200 + texte du match actif", async () => {
  const res = await get("https://fn.test/score-text?channel=marc", makeDb([row()]));
  assertEquals(res.status, 200);
  assertEquals(await res.text(), "MOI 5-3 LUI · SET 2 · Sets 1-0");
});

Deno.test("noms personnalisés via URL", async () => {
  const res = await get("https://fn.test/score-text?channel=marc&name1=Marc&name2=Paul", makeDb([row()]));
  assertEquals(await res.text(), "Marc 5-3 Paul · SET 2 · Sets 1-0");
});

Deno.test("fallback sur le dernier match fini si aucun actif", async () => {
  const res = await get("https://fn.test/score-text", makeDb([row({ status: "match_finished", scoreMe: 21, scoreOpp: 15 })]));
  assertEquals(await res.text(), "MOI 21-15 LUI · SET 2 · Sets 1-0 · Terminé");
});

Deno.test("aucun match : message d'attente", async () => {
  const res = await get("https://fn.test/score-text", makeDb([]));
  assertEquals(await res.text(), "Pas de match en cours");
});

Deno.test("formatScore : ligne complète avec sets", async () => {
  assertEquals(formatScore(row({ setsMe: 2, setsOpp: 1, status: "match_finished", currentSet: 3, scoreMe: 21, scoreOpp: 15 }), "A", "B"),
    "A 21-15 B · SET 3 · Sets 2-1 · Terminé");
});
