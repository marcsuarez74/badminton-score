import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleNamesGet, handleNamesPost, type NamesDb } from "./handler.ts";

// Clés : KEY = device marc ; KEY2 = device ami (comme sync).
const KEY = "devkey-marc-0123456789abcdef";
const KEY2 = "devkey-ami--0123456789abcdef";
const sha256Hex = async (s: string): Promise<string> => {
  const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, "0")).join("");
};

interface DeviceRow { deviceId: string; hash: string; channel: string; format: string; name1: string; name1b: string; name2: string; name2b: string }

function makeDb(devices: DeviceRow[]): NamesDb & { namesUpserts: { deviceId: string; format: string; name1: string; name1b: string; name2: string; name2b: string }[] } {
  const upserts: { deviceId: string; format: string; name1: string; name1b: string; name2: string; name2b: string }[] = [];
  return {
    async getDeviceHash(expected: string) {
      const expectedHash = await sha256Hex(expected);
      const d = devices.find((x) => x.hash === expectedHash);
      return d ? { deviceId: d.deviceId, error: null } : { deviceId: null, error: null };
    },
    async getNames(channel: string) {
      const d = devices.find((x) => x.channel === channel);
      if (!d) return null;
      return { format: d.format, name1: d.name1, name1b: d.name1b, name2: d.name2, name2b: d.name2b };
    },
    async upsertNames(deviceId, fields) {
      upserts.push({ deviceId, ...fields });
      return { error: null };
    },
    get namesUpserts() { return upserts; },
  } as NamesDb & { namesUpserts: { deviceId: string; format: string; name1: string; name1b: string; name2: string; name2b: string }[] };
}

const marc: DeviceRow = { deviceId: "f1592de682c46bc5", hash: await sha256Hex(KEY), channel: "marc", format: "simple", name1: "MOI", name1b: "", name2: "LUI", name2b: "" };

const URL_NAMES = "https://fn.test/names";

function req(method: string, url: string, headers: Record<string, string> = {}, body?: unknown): Request {
  return new Request(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

// ---- GET (lecture publique pour l'overlay / la page) ----

Deno.test("GET sans channel → 400", async () => {
  const res = await handleNamesGet(req("GET", URL_NAMES), makeDb([marc]));
  assertEquals(res.status, 400);
});

Deno.test("GET canal inconnu → 404", async () => {
  const res = await handleNamesGet(req("GET", URL_NAMES + "?channel=inconnu"), makeDb([marc]));
  assertEquals(res.status, 404);
});

Deno.test("GET canal existant → JSON noms", async () => {
  const res = await handleNamesGet(req("GET", URL_NAMES + "?channel=marc"), makeDb([marc]));
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body, { channel: "marc", format: "simple", name1: "MOI", name1b: "", name2: "LUI", name2b: "" });
});

// ---- POST (écriture protégée par la clé device) ----

Deno.test("POST sans X-Device-Key → 401", async () => {
  const res = await handleNamesPost(req("POST", URL_NAMES, {}, { format: "simple", name1: "A", name2: "B" }), makeDb([marc]));
  assertEquals(res.status, 401);
});

Deno.test("POST mauvaise clé → 401", async () => {
  const res = await handleNamesPost(req("POST", URL_NAMES, { "X-Device-Key": "paslabonne" }, { format: "simple", name1: "A", name2: "B" }), makeDb([marc]));
  assertEquals(res.status, 401);
});

Deno.test("POST format invalide → 400", async () => {
  const res = await handleNamesPost(req("POST", URL_NAMES, { "X-Device-Key": KEY }, { format: "quadruple", name1: "A", name2: "B" }), makeDb([marc]));
  assertEquals(res.status, 400);
});

Deno.test("POST double sans partenaire → 400", async () => {
  const res = await handleNamesPost(req("POST", URL_NAMES, { "X-Device-Key": KEY }, { format: "double", name1: "A", name2: "B" }), makeDb([marc]));
  assertEquals(res.status, 400);
});

Deno.test("POST simple valide → 200, name1b/name2b vidés", async () => {
  const db = makeDb([marc]);
  const res = await handleNamesPost(req("POST", URL_NAMES, { "X-Device-Key": KEY }, { format: "simple", name1: "MARC", name1b: "INUTILE", name2: "PAUL", name2b: "OUBLIE" }), db);
  assertEquals(res.status, 200);
  const ups = db.namesUpserts;
  assertEquals(ups.length, 1);
  assertEquals(ups[0].deviceId, "f1592de682c46bc5");
  assertEquals(ups[0].format, "simple");
  assertEquals(ups[0].name1, "MARC");
  assertEquals(ups[0].name1b, "");
  assertEquals(ups[0].name2, "PAUL");
  assertEquals(ups[0].name2b, "");
});

Deno.test("POST double valide → 200 avec 4 noms", async () => {
  const db = makeDb([marc]);
  const res = await handleNamesPost(req("POST", URL_NAMES, { "X-Device-Key": KEY }, { format: "double", name1: "MARC", name1b: "JULES", name2: "PAUL", name2b: "HUGO" }), db);
  assertEquals(res.status, 200);
  const ups = db.namesUpserts;
  assertEquals(ups[0].format, "double");
  assertEquals(ups[0].name1b, "JULES");
  assertEquals(ups[0].name2b, "HUGO");
});

Deno.test("POST nom trop long → 400", async () => {
  const res = await handleNamesPost(req("POST", URL_NAMES, { "X-Device-Key": KEY }, { format: "simple", name1: "0123456789012345678901234", name2: "B" }), makeDb([marc]));
  assertEquals(res.status, 400);
});

Deno.test("POST d'un autre device n'écrase que lui", async () => {
  const ami: DeviceRow = { deviceId: "ami-device-0001", hash: await sha256Hex(KEY2), channel: "ami", format: "simple", name1: "MOI", name1b: "", name2: "LUI", name2b: "" };
  const db = makeDb([marc, ami]);
  await handleNamesPost(req("POST", URL_NAMES, { "X-Device-Key": KEY2 }, { format: "simple", name1: "AMI", name2: "RIVAL" }), db);
  assertEquals(db.namesUpserts[0].deviceId, "ami-device-0001");
});
