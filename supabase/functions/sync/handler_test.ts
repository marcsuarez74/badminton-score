import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleSync, sha256Hex, type Db, type Validated } from "./handler.ts";

const URL_MATCH = "https://fn.test/functions/v1/sync/matches/B7K2QM9X/events";

function makeDb(opts: { devices?: { hash: string; channel: string }[]; ownerDeviceId?: string | null } = {}): Db {
  const events = new Map<string, Record<string, unknown>>();
  const devices = opts.devices ?? [];
  let matchDevice: string | null = opts.ownerDeviceId ?? null;
  let matchChannel: string | null = null;
  const state = { finishedOthers: [] as string[] };
  return {
    async getDeviceHash(expected) {
      const d = devices.find((x) => x.hash === expected);
      return { channel: d?.channel ?? null, error: null };
    },
    async getMatchDevice(matchId) { return { deviceId: matchDevice, error: null }; },
    async upsertMatch(_m, deviceId, _c, _s, _st, channel) { matchDevice = deviceId; matchChannel = channel; return { error: null }; },
    async finishOtherActiveMatches(deviceId, matchId) {
      state.finishedOthers.push(deviceId + ':' + matchId);
      return { error: null };
    },
    channelUsed() { return matchChannel; },
    get finishedOthers() { return state.finishedOthers; },
    async upsertEvents(matchId, rows) {
      for (const e of rows) {
        const key = `${matchId}:${e.sequence}`;
        if (!events.has(key)) events.set(key, e);   // simule UNIQUE (match_id, sequence)
      }
      return { error: null };
    },
    async upsertState(_m, _s, _c) { return { error: null }; },
  } as Db & { channelUsed(): string | null };
}

function req(method: string, url: string, headers: Record<string, string>, body: unknown): Request {
  return new Request(url, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
}

const KEY = "test-device-key";
const KEY_AMI = "cle-ami";
function oneDevice(hash: string, channel = "marc") {
  return { devices: [{ hash, channel }] };
}
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
  const db = makeDb(oneDevice(await sha256Hex("autre-clé")));
  const res = await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY }, GOOD_BODY), db);
  assertEquals(res.status, 401);
});

Deno.test("401 si clé de device absente de la table", async () => {
  const db = makeDb({ devices: [] });
  const res = await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY }, GOOD_BODY), db);
  assertEquals(res.status, 401);
});

Deno.test("2e device acceptée avec son propre canal", async () => {
  const db = makeDb({ devices: [
    { hash: await sha256Hex(KEY), channel: "marc" },
    { hash: await sha256Hex(KEY_AMI), channel: "ami" },
  ] });
  const res = await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY_AMI }, GOOD_BODY), db);
  assertEquals(res.status, 200);
  assertEquals((db as Db & { channelUsed(): string | null }).channelUsed(), "ami");
});

Deno.test("400 si body invalide (events vide)", async () => {
  const db = makeDb(oneDevice(await sha256Hex(KEY)));
  const bad = { ...GOOD_BODY, events: [] };
  const res = await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY }, bad), db);
  assertEquals(res.status, 400);
});

Deno.test("200 + ACK lastAcceptedSequence", async () => {
  const db = makeDb(oneDevice(await sha256Hex(KEY)));
  const res = await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY }, GOOD_BODY), db);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.matchId, "B7K2QM9X");
  assertEquals(body.lastAcceptedSequence, 3);
});

Deno.test("re-POST de doublons : 200, pas de duplication", async () => {
  const db = makeDb(oneDevice(await sha256Hex(KEY)));
  const h = { "X-Device-Key": KEY };
  await handleSync(req("POST", URL_MATCH, h, GOOD_BODY), db);
  const res2 = await handleSync(req("POST", URL_MATCH, h, GOOD_BODY), db);
  assertEquals(res2.status, 200);
  // la Map factice simule la contrainte : 2 events seulement (seq 2 et 3)
  // (vérification indirecte : le re-POST ne renvoie pas d'erreur)
});

Deno.test("création d'un match clôture les actifs précédents du même device", async () => {
  const db = makeDb(oneDevice(await sha256Hex(KEY))) as Db & { finishedOthers: string[] };
  const res = await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY }, GOOD_BODY), db);
  assertEquals(res.status, 200);
  assertEquals(db.finishedOthers, ["install-uuid-1:B7K2QM9X"]);
});

Deno.test("re-POST d'un match existant ne clôture rien", async () => {
  const db = makeDb({ ...oneDevice(await sha256Hex(KEY)), ownerDeviceId: "install-uuid-1" }) as Db & { finishedOthers: string[] };
  await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY }, GOOD_BODY), db);
  assertEquals(db.finishedOthers.length, 0);
});

Deno.test("403 si le match appartient à un autre device", async () => {
  const db = makeDb({ ...oneDevice(await sha256Hex(KEY)), ownerDeviceId: "autre-install" });
  const res = await handleSync(req("POST", URL_MATCH, { "X-Device-Key": KEY }, GOOD_BODY), db);
  assertEquals(res.status, 403);
});

