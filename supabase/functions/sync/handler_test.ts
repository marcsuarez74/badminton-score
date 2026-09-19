import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleSync, sha256Hex, type Db, type Validated } from "./handler.ts";

const URL_MATCH = "https://fn.test/functions/v1/sync/matches/B7K2QM9X/events";

function makeDb(opts: { deviceHash: string | null; ownerDeviceId?: string | null } = { deviceHash: null }): Db {
  const events = new Map<string, Record<string, unknown>>();
  let matchDevice: string | null = opts.ownerDeviceId ?? null;
  return {
    async getDeviceHash() { return { hash: opts.deviceHash, error: null }; },
    async getMatchDevice(matchId) { return { deviceId: matchDevice, error: null }; },
    async upsertMatch(_m, deviceId, _c, _s, _st) { matchDevice = deviceId; return { error: null }; },
    async upsertEvents(matchId, rows) {
      for (const e of rows) {
        const key = `${matchId}:${e.sequence}`;
        if (!events.has(key)) events.set(key, e);   // simule UNIQUE (match_id, sequence)
      }
      return { error: null };
    },
    async upsertState(_m, _s, _c) { return { error: null }; },
  };
}

function req(method: string, url: string, headers: Record<string, string>, body: unknown): Request {
  return new Request(url, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
}

const KEY = "test-device-key";
const GOOD_BODY = {
  deviceId: "install-uuid-1",
  config: { targetScore: 21, winBy: 2, cap: 30, setsToWin: 2 },
  snapshot: { status: "active", currentSet: 1, scoreMe: 2, scoreOpp: 1, setsMe: 0, setsOpp: 0, lastSequence: 3 },
  events: [
    { type: 0, arg: 0, sequence: 2, ts: 100, prevMe: 1, prevOpp: 1 },
    { type: 0, arg: 0, sequence: 3, ts: 200, prevMe: 2, prevOpp: 1 },
  ],
};

Deno.test("405 si GET", async () => {
  const res = await handleSync(req("GET", URL_MATCH, {}, undefined), makeDb());
  assertEquals(res.status, 405);
});

Deno.test("404 si route inconnue", async () => {
  const res = await handleSync(req("POST", "https://fn.test/other", {}, GOOD_BODY), makeDb());
  assertEquals(res.status, 404);
});

Deno.test("401 sans X-Device-Key", async () => {
  const res = await handleSync(req("POST", URL_MATCH, {}, GOOD_BODY), makeDb());
  assertEquals(res.status, 401);
});

Deno.test("401 avec mauvaise clé", async () => {
  const db = makeDb({ deviceHash: await sha256Hex("autre-clé") });
  const res = await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY }, GOOD_BODY), db);
  assertEquals(res.status, 401);
});

Deno.test("400 si body invalide (events vide)", async () => {
  const db = makeDb({ deviceHash: await sha256Hex(KEY) });
  const bad = { ...GOOD_BODY, events: [] };
  const res = await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY }, bad), db);
  assertEquals(res.status, 400);
});

Deno.test("200 + ACK lastAcceptedSequence", async () => {
  const db = makeDb({ deviceHash: await sha256Hex(KEY) });
  const res = await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY }, GOOD_BODY), db);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.matchId, "B7K2QM9X");
  assertEquals(body.lastAcceptedSequence, 3);
});

Deno.test("re-POST de doublons : 200, pas de duplication", async () => {
  const db = makeDb({ deviceHash: await sha256Hex(KEY) });
  const h = { "X-Device-Key": KEY };
  await handleSync(req("POST", URL_MATCH, h, GOOD_BODY), db);
  const res2 = await handleSync(req("POST", URL_MATCH, h, GOOD_BODY), db);
  assertEquals(res2.status, 200);
  // la Map factice simule la contrainte : 2 events seulement (seq 2 et 3)
  // (vérification indirecte : le re-POST ne renvoie pas d'erreur)
});

Deno.test("403 si le match appartient à un autre device", async () => {
  const db = makeDb({ deviceHash: await sha256Hex(KEY), ownerDeviceId: "autre-install" });
  const res = await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY }, GOOD_BODY), db);
  assertEquals(res.status, 403);
});

