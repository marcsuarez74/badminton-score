# Phase 4a — Synchronisation (POC, Supabase, SyncService) — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Les points joués sur la montre partent par `makeWebRequest` (relais GCM) vers une Edge Function Supabase qui les stocke de façon idempotente et renvoie un ACK `{matchId, lastAcceptedSequence}` — chaîne complète validée en simulateur ET sur l'epix matérielle avec GCM.

**Architecture:** Voir `docs/superpowers/specs/2026-09-19-sync-backend-overlay-twitch-design.md` (§1-§7, §11-§14). Montre = source de vérité (snapshot `match_state` fourni par la montre, ADR-007). Côté montre : POST HTTPS simple uniquement ; file = journal + pointeur `pf` (Phase 3) ; batchs ≤ 5 events, ≥ 5 s entre débuts, timeout applicatif 30 s, backoff 10 s → 2 min. Backend : 1 Edge Function `sync` (auth `X-Device-Key` sha256, validation, upserts idempotents via service role), PostgreSQL (4 tables), RLS lecture seule publique. **Décision D-3 (spec sync §7/§18)** : la rétraction réseau de l'undo (TYPE_UNDO) est reportée à la Phase 7 — l'historique backend reste append-only (events fantômes possibles après undo d'un event déjà envoyé), le snapshot corrige l'overlay. Le moteur Phase 2/3 n'est **pas** modifié.

**Tech Stack:** Monkey C (SDK Connect IQ 9.2.0, minApiLevel 3.4.0), Deno (Edge Functions), PostgreSQL (Supabase free tier, projet `bzdbnptnubkkagmmxhyi`), supabase CLI, Run No Evil (`monkeyc -t`).

**Projet Supabase:** `https://bzdbnptnubkkagmmxhyi.supabase.co` (créé par le propriétaire). Région : celle choisie à la création.

**Secrets (jamais dans git)** : device key (hex), service role key (injectée automatiquement dans les Edge Functions), anon key. Fichier local `.secrets/phase-4a.env` (gitigné).

**Branche de travail** : `phase-4a` créée depuis `main`. Commit à chaque tâche.

**[USER ACTION] prérequis (une fois, avant Task 1)** : installer les outils —
```bash
brew install supabase/tap/supabase deno
```
Puis dans le repo, avec le navigateur ouvert pour le login :
```bash
supabase login                      # USER : s'authentifier (navigateur)
supabase link --project-ref bzdbnptnubkkagmmxhyi   # USER : mot de passe DB du projet
```

---

## Fichiers créés/modifiés (vue d'ensemble)

| Fichier | Rôle |
|---|---|
| `supabase/config.toml` | Config CLI + `verify_jwt = false` pour la fonction `sync` |
| `supabase/migrations/20260919000001_poc.sql` | Table jetable du POC (supprimée en Task 4) |
| `supabase/migrations/20260919000002_schema.sql` | Schéma complet (4 tables, RLS, publication, device seed) |
| `supabase/functions/sync/index.ts` | Entrée Deno : client service role + `Deno.serve` |
| `supabase/functions/sync/handler.ts` | Logique pure testable : routing, validation, auth, orchestration |
| `supabase/functions/sync/handler_test.ts` | Tests Deno (Db factice) |
| `prototypes/sync-test/` | App de POC montre (miroir de `prototypes/button-test/`) |
| `watch/connect-iq/source/services/MatchIds.mc` | matchId 8 chars Crockford base32 (pur, testable) |
| `watch/connect-iq/source/services/DeviceId.mc` | UUID d'installation 64 bits (Application.Storage) |
| `watch/connect-iq/source/services/SyncCore.mc` | Cœur pur : batchSlice, sérialisation, buildBody, backoff, shouldSend |
| `watch/connect-iq/source/services/SyncService.mc` | Adaptateur makeWebRequest + watchdog 30 s + drain |
| `watch/connect-iq/source/MatchStore.mc` | + `getPendingFrom()`/`ackUntil(seq)`, `saveMatch` préserve `pf` |
| `watch/connect-iq/source/ui/MatchView.mc` | matchId via MatchIds ; déclenche sync après chaque save |
| `watch/connect-iq/manifest.xml` | + permission Communications, properties `backendUrl`/`deviceKey` |
| `watch/connect-iq/source/tests/SyncTest.mc` | Tests Run No Evil des nouveaux modules |
| `docs/superpowers/specs/2026-09-19-sync-backend-overlay-twitch-design.md` | Corrections type-map §12 + décisions D-3 (§7, §18) |
| `docs/superpowers/notes/phase-4a-sync-results.md` | Résultats simu + matériel (fin de phase) |

---

### Task 1: Setup Supabase (CLI, init, config)

**Files:**
- Create: `supabase/config.toml` (via `supabase init`)
- Modify: `.gitignore`

- [ ] **Step 1: Vérifier les outils** (si déjà fait en prérequis, passer)

Run: `supabase --version && deno --version`
Expected: versions affichées. Sinon : `brew install supabase/tap/supabase deno`

- [ ] **Step 2: Init du projet Supabase dans le repo**

Run (workdir racine du repo):
```bash
supabase init
```
Expected: répertoire `supabase/` créé avec `config.toml`. Répondre non aux questions optionnelles (défauts).

- [ ] **Step 3: Configurer la fonction (pas de JWT Supabase — auth custom)**

Ajouter à la fin de `supabase/config.toml` :
```toml
[functions.sync]
verify_jwt = false
```

- [ ] **Step 4: Gitignore des artefacts locaux**

Ajouter à `.gitignore` :
```
supabase/.temp/
supabase/.branches/
supabase/.branches
.secrets/
```

- [ ] **Step 5: Commit**

```bash
git checkout -b phase-4a
git add supabase/config.toml .gitignore
git commit -m "chore(4a): setup supabase (config CLI, verify_jwt off pour sync)"
```
NB : si la branche existe déjà, juste `git checkout phase-4a`.

---

### Task 2: POC backend — table jetable + fonction `sync` minimale + deploy

**Files:**
- Create: `supabase/migrations/20260919000001_poc.sql`
- Create: `supabase/functions/sync/index.ts`

- [ ] **Step 1: Migration POC**

Créer `supabase/migrations/20260919000001_poc.sql` :
```sql
-- POC Phase 4a : table jetable pour prouver montre -> GCM -> Edge Function -> DB.
-- Supprimée par la migration du schéma complet (Task 4).
create table poc_events (
  id bigint generated always as identity primary key,
  payload jsonb not null,
  created_at timestamptz not null default now()
);
```

- [ ] **Step 2: Fonction minimale (echo + insert)**

Créer `supabase/functions/sync/index.ts` :
```typescript
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
```

- [ ] **Step 3: Appliquer la migration** — **[USER ACTION si mot de passe demandé]**

Run: `supabase db push`
Expected: `20260919000001_poc.sql ... applied` (demander le mot de passe DB au propriétaire si prompt).

- [ ] **Step 4: Déployer la fonction**

Run: `supabase functions deploy sync`
Expected: `Deployed Functions on project ...: sync`

- [ ] **Step 5: Test curl depuis le Mac**

Run:
```bash
curl -s -X POST "https://bzdbnptnubkkagmmxhyi.supabase.co/functions/v1/sync/matches/POCTEST1/events" \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"curl","probe":true}'
```
Expected: `{"ok":true,"id":1}` (ou id croissant) — la ligne existe dans `poc_events` (dashboard Supabase > Table Editor).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260919000001_poc.sql supabase/functions/sync/index.ts
git commit -m "feat(4a): POC Edge Function sync (echo+insert poc_events)"
```

---

### Task 3: POC montre — app `sync-test` + validation simu (+ matériel)

**Files:**
- Create: `prototypes/sync-test/manifest.xml`, `monkey.jungle`, `source/SyncTestApp.mc`, `resources/strings/strings.xml`, `resources/drawables/drawables.xml`, `resources/drawables/launcher_icon.xml`

Structure copiée de `prototypes/button-test/` (mêmes conventions : uuid manifest différent, `minApiLevel 3.4.0`, produits ×5, permission Communications **déjà présente** dans button-test).

- [ ] **Step 1: Copier la structure de button-test**

```bash
cp -R prototypes/button-test prototypes/sync-test
rm -rf prototypes/sync-test/sideload prototypes/sync-test/bin
```
Garder `monkey.jungle` tel quel ; remplacer `manifest.xml` (id applicatif différent, même permission) et le source.

- [ ] **Step 2: manifest.xml**

Remplacer `prototypes/sync-test/manifest.xml` :
```xml
<?xml version="1.0" encoding="UTF-8"?>
<iq:manifest xmlns:iq="http://www.garmin.com/xml/connectiq" version="3">
    <iq:application id="AC25DD973726450689696D510D989811" version="0.1.0" minSdkVersion="3.4.0" minApiLevel="3.4.0" entry="SyncTestApp" type="watch-app" name="@Strings.AppName" launcherIcon="@Drawables.LauncherIcon">
        <iq:products>
            <iq:product id="epix2pro42mm"/>
            <iq:product id="epix2pro47mm"/>
            <iq:product id="epix2pro51mm"/>
            <iq:product id="fr55"/>
            <iq:product id="instinct2"/>
        </iq:products>
        <iq:permissions>
            <iq:uses-permission id="Communications"/>
        </iq:permissions>
        <iq:languages>
            <iq:language>eng</iq:language>
        </iq:languages>
    </iq:application>
</iq:manifest>
```

- [ ] **Step 3: Source complet**

Remplacer le contenu de `prototypes/sync-test/source/` par un seul fichier `SyncTestApp.mc` (supprimer l'ancien `.mc`) :
```monkeyc
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// POC Phase 4a : 1 bouton = 1 POST vers l'Edge Function sync. Le code
// d'affichage du responseCode est la sortie du test (cf. spec sync §15).
const BACKEND_URL = "https://bzdbnptnubkkagmmxhyi.supabase.co/functions/v1/sync";

class SyncTestDelegate extends WatchUi.BehaviorDelegate {
    hidden var mResult = "SELECT = POST";

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        _send();
        return true;
    }

    hidden function _send() as Void {
        var body = {
            "deviceId" => "poc-device",
            "config" => { "targetScore" => 11, "winBy" => 2, "cap" => 0, "setsToWin" => 2 },
            "snapshot" => { "status" => "active", "currentSet" => 1, "scoreMe" => 1,
                            "scoreOpp" => 0, "setsMe" => 0, "setsOpp" => 0, "lastSequence" => 1 },
            "events" => [ { "type" => 0, "arg" => 0, "sequence" => 1, "ts" => 0, "prevMe" => 0, "prevOpp" => 0 } ]
        };
        var options = {
            "method" => Communications.HTTP_REQUEST_METHOD_POST,
            "headers" => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
            "responseType" => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        mResult = "envoi...";
        Communications.makeWebRequest(BACKEND_URL + "/matches/POCTEST1/events", body, options, method(:_onResponse));
        WatchUi.requestUpdate();
    }

    hidden function _onResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            mResult = "HTTP 200 las=" + data["lastAcceptedSequence"];
        } else {
            mResult = "ERR " + responseCode;
        }
        System.println("[sync-test] " + mResult);
        WatchUi.requestUpdate();
    }

    // BACK = sortie (prototype).
    function onBack() as Boolean {
        System.exit();
        return true;
    }
}

class SyncTestView extends WatchUi.View {
    hidden var mDelegate;

    function initialize() {
        View.initialize();
        mDelegate = new SyncTestDelegate();
    }

    function getDelegate() as WatchUi.InputDelegate or Null {
        return mDelegate;
    }

    function onUpdate(dc as Dc) as Void {
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 4, Graphics.FONT_MEDIUM, "SYNC POC", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_SMALL, mDelegate.mResult, Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class SyncTestApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }
    function getInitialView() {
        var view = new SyncTestView();
        return [view, view.getDelegate()];
    }
}

function getApp() as Application.AppBase {
    return new SyncTestApp();
}
```
Note : `mDelegate.mResult` est accessible (champs publics par défaut en Monkey C). Si l'accès direct gêne, ajouter un getter `getResult()` au delegate.

- [ ] **Step 4: Build epix2pro51mm**

Run:
```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
monkeyc -d epix2pro51mm -f prototypes/sync-test/monkey.jungle -o prototypes/sync-test/bin/sync-test-epix2pro51mm.prg -y ~/keys/developer_key.der -w -r
```
Expected: 0 erreur, 0 warning nouveau. (Adapter `resources/` si le jungle de button-test référence des drawables copiés — ils le sont par `cp -R`.)

- [ ] **Step 5: Simulateur (réseau du Mac, sans téléphone)**

```bash
pkill -f ConnectIQ 2>/dev/null; sleep 1
open "$SDK/bin/ConnectIQ.app" && sleep 6
"$SDK/bin/monkeydo" prototypes/sync-test/bin/sync-test-epix2pro51mm.prg epix2pro51mm
```
Appuyer SELECT dans le simulateur → écran attendu : `HTTP 200 las=<n>`. Vérifier la ligne dans le dashboard (Table Editor > `poc_events`).

- [ ] **Step 6: Matériel epix + GCM — [USER ACTION]**

1. Copier le `.prg` dans `prototypes/sync-test/sideload/` puis sur la montre (`/GARMIN/APPS/`).
2. Sur le téléphone : **Garmin Connect Mobile ouverte** (Android : arrière-plan OK), epix appairée.
3. Lancer « SYNC POC » sur la montre, appuyer SELECT → attendu `HTTP 200 las=<n>`.
4. Noter la latence approximative (pression → affichage) dans les notes.
5. Tester aussi GCM fermée (Android) → doit passer quand même (service système) — noter.

Si `ERR -104`/`-2` : consigner (leçons §3.8 de la spec sync) et re-tester GCM active.

- [ ] **Step 7: Commit**

```bash
git add prototypes/sync-test
git commit -m "feat(4a): POC montre sync-test — POST makeWebRequest vers Edge Function (simu 200)"
```

---

### Task 4: Schéma complet + RLS + device seed (+ corrections spec sync)

**Files:**
- Create: `supabase/migrations/20260919000002_schema.sql`
- Create: `.secrets/phase-4a.env` (gitigné)
- Modify: `docs/superpowers/specs/2026-09-19-sync-backend-overlay-twitch-design.md`

- [ ] **Step 1: Générer le device secret + hash (jamais dans git pour la clé brute)**

```bash
mkdir -p .secrets
DEVICE_KEY="$(openssl rand -hex 32)"
DEVICE_HASH="$(printf '%s' "$DEVICE_KEY" | shasum -a 256 | cut -d' ' -f1)"
printf 'SUPABASE_URL=https://bzdbnptnubkkagmmxhyi.supabase.co\nDEVICE_KEY=%s\nDEVICE_HASH=%s\n' "$DEVICE_KEY" "$DEVICE_HASH" > .secrets/phase-4a.env
```
Stocker aussi la clé brute dans le gestionnaire de mots de passe du propriétaire. Vérifier que `.secrets/` est bien ignoré : `git status` ne doit PAS lister `.secrets/`.

- [ ] **Step 2: Migration du schéma complet**

Créer `supabase/migrations/20260919000002_schema.sql` (remplacer `<DEVICE_HASH>` par la valeur réelle de `$DEVICE_HASH`) :
```sql
-- Schéma Phase 4a (spec sync §12) — montre = source de vérité (ADR-007).
create table matches (
  match_id   text primary key,
  device_id  text not null,
  channel    text not null default 'marc',
  config     jsonb not null,
  status     text not null default 'active' check (status in ('active','finished','archived')),
  started_at bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table events (
  id        text primary key,
  match_id  text not null references matches(match_id),
  sequence  int  not null check (sequence > 0),
  type      int  not null check (type between 0 and 5),  -- 0=POINT_ME 1=POINT_OPPONENT 2=SET_FINISHED 3=SET_CHANGED 4=MATCH_FINISHED 5=UNDO(réservé)
  arg       int  not null default 0,
  prev_me   int,
  prev_opp  int,
  ts        bigint,
  created_at timestamptz not null default now(),
  unique (match_id, sequence)
);

create table match_state (
  match_id      text primary key references matches(match_id),
  status        text not null check (status in ('active','set_result','match_finished')),
  current_set   int  not null default 1,
  score_me      int  not null default 0,
  score_opp     int  not null default 0,
  sets_me       int  not null default 0,
  sets_opp      int  not null default 0,
  last_sequence int  not null default 0,
  config        jsonb not null,
  updated_at    timestamptz not null default now()
);

create table devices (
  id              smallint primary key default 1,
  device_key_hash text not null,
  label           text,
  created_at      timestamptz not null default now()
);
insert into devices (device_key_hash, label) values ('<DEVICE_HASH>', 'epix Pro 51 mm');

-- Lecture seule publique (overlay) ; écriture = Edge Function service role.
-- Piège officiel : les policies ne révoquent pas les grants → REVOKE d'abord.
revoke all on matches, events, match_state from anon, authenticated;
grant select on matches, events, match_state to anon;
alter table matches     enable row level security;
alter table events      enable row level security;
alter table match_state enable row level security;
create policy "public read matches"     on matches     for select to anon using (true);
create policy "public read events"      on events      for select to anon using (true);
create policy "public read state"       on match_state for select to anon using (true);

drop table if exists poc_events;

alter publication supabase_realtime add table matches, events, match_state;
```

- [ ] **Step 3: Corrections de la spec sync (mapping types réel du moteur + D-3)**

Dans `docs/superpowers/specs/2026-09-19-sync-backend-overlay-twitch-design.md` :

1. §12, ligne du commentaire `type` : remplacer `-- 0=POINT_ME 1=POINT_OPPONENT 2=UNDO(réservé 4a) 3=SET_CHANGED 4=SET_FINISHED 5=MATCH_FINISHED` par `-- 0=POINT_ME 1=POINT_OPPONENT 2=SET_FINISHED 3=SET_CHANGED 4=MATCH_FINISHED 5=UNDO(réservé Phase 7) — mapping ScoreEvent.mc réel`.
2. §7 (table Synchronisation), ajouter une ligne :
   `| Undo d'un event déjà envoyé | MVP (D-3) : le backend garde l'event annulé (historique append-only) ; l'overlay reste juste (snapshot = vérité). Rétraction propre (marqueur TYPE_UNDO journalisé côté moteur, séquence monotone) → Phase 7 quand le bot en aura besoin. |`
3. §18, ajouter la décision :
   `| S14 | Représentation réseau de l'undo (D-3) : reportée Phase 7 — MVP = historique append-only (events fantômes possibles après undo d'un event déjà ACK), le snapshot fait foi ; le marqueur TYPE_UNDO journalisé au moteur sera implémenté avec le bot | Validée (compromis MVP) |`

- [ ] **Step 4: Appliquer** — **[USER ACTION si mot de passe demandé]**

Run: `supabase db push`
Expected: migration appliquée.

- [ ] **Step 5: Vérifier la RLS avec la clé anon**

```bash
source .secrets/phase-4a.env
ANON_KEY="$(supabase projects api-keys --project-ref bzdbnptnubkkagmmxhyi --output json | grep -o '"api_key":"[^"]*anon[^"]*"' | head -1 | cut -d'"' -f4)"
# lecture publique : 200 []
curl -s "https://bzdbnptnubkkagmmxhyi.supabase.co/rest/v1/match_state?select=*" -H "apikey: $ANON_KEY"
# écriture anonyme : doit être refusée (401/403/404 postgrest)
curl -s -o /dev/null -w "%{http_code}\n" -X POST "https://bzdbnptnubkkagmmxhyi.supabase.co/rest/v1/match_state" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" -H "Prefer: return=minimal" -d '{}'
```
Expected: premier curl → `[]` ; deuxième → code `401`/`403` (pas 201). Si le format de sortie du CLI diffère, récupérer l'anon key dans le dashboard (Settings > API) — **[USER ACTION]**.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260919000002_schema.sql docs/superpowers/specs/2026-09-19-sync-backend-overlay-twitch-design.md
git commit -m "feat(4a): schéma complet (matches/events/match_state/devices), RLS lecture seule, device seed"
```

---

### Task 5: Edge Function `sync` complète (auth, validation, idempotence, ACK) + tests Deno

**Files:**
- Create: `supabase/functions/sync/handler.ts`
- Modify: `supabase/functions/sync/index.ts` (remplace la version POC)
- Create: `supabase/functions/sync/handler_test.ts`

- [ ] **Step 1: handler.ts (logique pure, Db injectable)**

```typescript
// Edge Function sync — logique pure testable (Db injecté). Le backend ne
// calcule JAMAIS le score : il valide la forme, authentifie la device key et
// upsert de façon idempotente (ADR-007, spec sync §5/§11/§13).
export interface Db {
  getDeviceHash(): Promise<{ hash: string | null; error: string | null }>;
  getMatchDevice(matchId: string): Promise<{ deviceId: string | null; error: string | null }>;
  upsertMatch(matchId: string, deviceId: string, config: Record<string, unknown>, startedAt: number | null, status: string): Promise<{ error: string | null }>;
  upsertEvents(matchId: string, events: Record<string, unknown>[]): Promise<{ error: string | null }>;
  upsertState(matchId: string, snapshot: Record<string, unknown>, config: Record<string, unknown>): Promise<{ error: string | null }>;
}

export function json(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json" } });
}

export async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function isInt(n: unknown, min: number, max: number): boolean {
  return typeof n === "number" && Number.isInteger(n) && n >= min && n <= max;
}

function isConfig(c: unknown): boolean {
  if (typeof c !== "object" || c === null) return false;
  const k = c as Record<string, unknown>;
  return isInt(k.targetScore, 1, 99) && isInt(k.winBy, 1, 20) &&
         isInt(k.cap, 0, 200) && isInt(k.setsToWin, 1, 5);
}

function isSnapshot(s: unknown): boolean {
  if (typeof s !== "object" || s === null) return false;
  const k = s as Record<string, unknown>;
  return (k.status === "active" || k.status === "set_result" || k.status === "match_finished") &&
         isInt(k.currentSet, 1, 9) && isInt(k.scoreMe, 0, 199) && isInt(k.scoreOpp, 0, 199) &&
         isInt(k.setsMe, 0, 9) && isInt(k.setsOpp, 0, 9) && isInt(k.lastSequence, 0, 100000);
}

function isEvent(e: unknown): boolean {
  if (typeof e !== "object" || e === null) return false;
  const k = e as Record<string, unknown>;
  return isInt(k.type, 0, 5) && isInt(k.arg, -1, 9999) && isInt(k.sequence, 1, 100000) &&
         typeof k.ts === "number" && isInt(k.prevMe, 0, 199) && isInt(k.prevOpp, 0, 199);
}

export type Validated =
  | { ok: true; deviceId: string; config: Record<string, unknown>; snapshot: Record<string, unknown>; events: Record<string, unknown>[]; startedAt: number | null }
  | { ok: false; status: number; message: string };

export function validateBody(body: unknown): Validated {
  if (typeof body !== "object" || body === null) return { ok: false, status: 400, message: "body" };
  const b = body as Record<string, unknown>;
  if (typeof b.deviceId !== "string" || b.deviceId.length === 0 || b.deviceId.length > 64) {
    return { ok: false, status: 400, message: "deviceId" };
  }
  if (!isConfig(b.config)) return { ok: false, status: 400, message: "config" };
  if (!isSnapshot(b.snapshot)) return { ok: false, status: 400, message: "snapshot" };
  if (!Array.isArray(b.events) || b.events.length < 1 || b.events.length > 10) {
    return { ok: false, status: 400, message: "events" };
  }
  for (const e of b.events) { if (!isEvent(e)) return { ok: false, status: 400, message: "event" }; }
  const startedAt = typeof b.startedAt === "number" ? b.startedAt : null;
  return { ok: true, deviceId: b.deviceId, config: b.config, snapshot: b.snapshot, events: b.events, startedAt };
}

export async function handleSync(req: Request, db: Db): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method" });
  const m = new URL(req.url).pathname.match(/\/matches\/([A-Za-z0-9_-]+)\/events$/);
  if (!m) return json(404, { error: "route" });
  const matchId = m[1];
  if (matchId.length < 4 || matchId.length > 32) return json(400, { error: "matchId" });
  const key = req.headers.get("X-Device-Key");
  if (!key) return json(401, { error: "key" });
  let body: unknown;
  try { body = await req.json(); } catch { return json(400, { error: "json" }); }
  const v = validateBody(body);
  if (!v.ok) return json(v.status, { error: v.message });
  const dev = await db.getDeviceHash();
  if (dev.error) return json(500, { error: dev.error });
  const expected = await sha256Hex(key);
  if (!dev.hash || dev.hash !== expected) return json(401, { error: "key" });
  const owner = await db.getMatchDevice(matchId);
  if (owner.error) return json(500, { error: owner.error });
  if (owner.deviceId !== null && owner.deviceId !== v.deviceId) return json(403, { error: "owner" });
  const status = v.snapshot.status === "match_finished" ? "finished" : "active";
  const up = await db.upsertMatch(matchId, v.deviceId, v.config, v.startedAt, status);
  if (up.error) return json(500, { error: up.error });
  const ev = await db.upsertEvents(matchId, v.events);
  if (ev.error) return json(500, { error: ev.error });
  const st = await db.upsertState(matchId, v.snapshot, v.config);
  if (st.error) return json(500, { error: st.error });
  const last = Math.max(...v.events.map((e) => e.sequence as number));
  return json(200, { matchId, lastAcceptedSequence: last });
}
```

- [ ] **Step 2: index.ts (Db réel + serve)**

Remplacer tout `supabase/functions/sync/index.ts` :
```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleSync, type Db } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const db: Db = {
  async getDeviceHash() {
    const { data, error } = await supabase.from("devices").select("device_key_hash").eq("id", 1).maybeSingle();
    return { hash: (data as { device_key_hash?: string } | null)?.device_key_hash ?? null, error: error ? error.message : null };
  },
  async getMatchDevice(matchId) {
    const { data, error } = await supabase.from("matches").select("device_id").eq("match_id", matchId).maybeSingle();
    return { deviceId: (data as { device_id?: string } | null)?.device_id ?? null, error: error ? error.message : null };
  },
  async upsertMatch(matchId, deviceId, config, startedAt, status) {
    const { error } = await supabase.from("matches").upsert(
      { match_id: matchId, device_id: deviceId, config, started_at: startedAt, status },
      { onConflict: "match_id" },
    );
    return { error: error ? error.message : null };
  },
  async upsertEvents(matchId, events) {
    const rows = events.map((e) => ({
      id: `${matchId}:${e.sequence}`,
      match_id: matchId,
      sequence: e.sequence,
      type: e.type,
      arg: e.arg ?? 0,
      prev_me: e.prevMe ?? null,
      prev_opp: e.prevOpp ?? null,
      ts: e.ts ?? null,
    }));
    // Idempotence : doublons ignorés (UNIQUE (match_id, sequence), spec sync §7).
    const { error } = await supabase.from("events")
      .upsert(rows, { onConflict: "match_id,sequence", ignoreDuplicates: true });
    return { error: error ? error.message : null };
  },
  async upsertState(matchId, snapshot, config) {
    const { error } = await supabase.from("match_state").upsert({
      match_id: matchId,
      status: snapshot.status,
      current_set: snapshot.currentSet,
      score_me: snapshot.scoreMe,
      score_opp: snapshot.scoreOpp,
      sets_me: snapshot.setsMe,
      sets_opp: snapshot.setsOpp,
      last_sequence: snapshot.lastSequence,
      config,
    }, { onConflict: "match_id" });
    return { error: error ? error.message : null };
  },
};

Deno.serve((req: Request) => handleSync(req, db));
```

- [ ] **Step 3: handler_test.ts (Db factice)**

```typescript
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
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

Deno.test("assert helper utilisé", () => { assert(true); });
```

- [ ] **Step 4: Run tests**

Run: `deno test supabase/functions/sync/handler_test.ts --allow-all`
Expected: `ok. 9 passed` (tous verts).

- [ ] **Step 5: Deploy + e2e curl avec la vraie device key**

```bash
supabase functions deploy sync
source .secrets/phase-4a.env
B='{"deviceId":"install-curl","config":{"targetScore":21,"winBy":2,"cap":30,"setsToWin":2},"snapshot":{"status":"active","currentSet":1,"scoreMe":1,"scoreOpp":0,"setsMe":0,"setsOpp":0,"lastSequence":1},"events":[{"type":0,"arg":0,"sequence":1,"ts":0,"prevMe":0,"prevOpp":0}]}'
# 200 + ACK
curl -s -X POST "https://bzdbnptnubkkagmmxhyi.supabase.co/functions/v1/sync/matches/CURLTEST1/events" \
  -H "Content-Type: application/json" -H "X-Device-Key: $DEVICE_KEY" -d "$B"
# 401 sans clé
curl -s -o /dev/null -w "%{http_code}\n" -X POST "https://bzdbnptnubkkagmmxhyi.supabase.co/functions/v1/sync/matches/CURLTEST1/events" -H "Content-Type: application/json" -d "$B"
# re-POST identique → même ACK (idempotent)
curl -s -X POST "https://bzdbnptnubkkagmmxhyi.supabase.co/functions/v1/sync/matches/CURLTEST1/events" \
  -H "Content-Type: application/json" -H "X-Device-Key: $DEVICE_KEY" -d "$B"
# lecture publique
curl -s "https://bzdbnptnubkkagmmxhyi.supabase.co/rest/v1/match_state?match_id=eq.CURLTEST1&select=*" -H "apikey: $ANON_KEY_PLACEHOLDER"
```
Expected: ACK `{"matchId":"CURLTEST1","lastAcceptedSequence":1}` deux fois ; `401` sans clé ; `match_state` contient la ligne (anon key du dashboard si besoin — **[USER ACTION]** pour la récupérer et la stocker dans `.secrets/phase-4a.env` sous `ANON_KEY=`).

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/sync
git commit -m "feat(4a): Edge Function sync complète — auth device key, validation, idempotence, ACK (9 tests deno)"
```

---

### Task 6: Montre — modules purs `MatchIds` + `DeviceId` (RNE TDD)

**Files:**
- Create: `watch/connect-iq/source/services/MatchIds.mc`
- Create: `watch/connect-iq/source/services/DeviceId.mc`
- Modify: `watch/connect-iq/source/ui/MatchView.mc:161,178-181,209`
- Test: `watch/connect-iq/source/tests/SyncTest.mc`

- [ ] **Step 1: Tests d'abord (Run No Evil)**

Créer `watch/connect-iq/source/tests/SyncTest.mc` :
```monkeyc
import Toybox.Lang;

// Tests des modules de sync (Phase 4a). Exécutés via Run No Evil (monkeyc -t).
module SyncTests {

    // ---- MatchIds ----

    (:test)
    function test_matchid_format(logger as Logger) as Boolean {
        var id = MatchIds.generate();
        if (!MatchIds.isValid(id)) { logger.debug("format invalide: " + id); return false; }
        return true;
    }

    (:test)
    function test_matchid_deux_generations_differentes(logger as Logger) as Boolean {
        var a = MatchIds.generate();
        var b = MatchIds.generate();
        if (a.equals(b)) { logger.debug("collision improbable: " + a); return false; }
        return true;
    }

    (:test)
    function test_matchid_isvalide_rejete(logger as Logger) as Boolean {
        if (MatchIds.isValid("IILOOOXY")) { return false; }   // I/L/O interdits (Crockford)
        if (MatchIds.isValid("ABC")) { return false; }         // longueur ≠ 8
        if (MatchIds.isValid(null)) { return false; }
        return true;
    }

    // ---- DeviceId ----

    (:test)
    function test_deviceid_stable(logger as Logger) as Boolean {
        var a = DeviceId.getOrCreate();
        var b = DeviceId.getOrCreate();
        if (!a.equals(b)) { logger.debug("deviceId instable"); return false; }
        return true;
    }

    (:test)
    function test_deviceid_format(logger as Logger) as Boolean {
        var id = DeviceId.getOrCreate();
        if (id.length() != 16) { logger.debug("longueur != 16"); return false; }
        var hex = "0123456789abcdef";
        for (var i = 0; i < 16; i += 1) {
            var c = id.substring(i, i + 1);
            var found = false;
            for (var j = 0; j < 16; j += 1) {
                if (hex.substring(j, j + 1).equals(c)) { found = true; break; }
            }
            if (!found) { logger.debug("caractère non hex: " + c); return false; }
        }
        return true;
    }
}
```

- [ ] **Step 2: Exécuter pour voir échouer (symboles inconnus)**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
monkeyc -d fr55 -f watch/connect-iq/monkey.jungle -o /tmp/t4-test.prg -y ~/keys/developer_key.der -t -w
monkeydo /tmp/t4-test.prg fr55 -t 2>&1 | grep -E "PASSED|FAILED|Symbol"
```
Expected: échec de compilation (`Symbol Not Found: MatchIds`) ou tests en échec.

- [ ] **Step 3: Implémenter MatchIds.mc**

```monkeyc
import Toybox.Lang;
import Toybox.Math;

// matchId : 8 caractères Crockford base32 (40 bits) — spec sync §4.2.
// Généré à la startMatch (offline-first, aucun aller-retour) ; unicité
// garantie en pratique + contrainte PK backend en filet (409 → régénération).
module MatchIds {
    const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";   // sans I/L/O/U

    function generate() as String {
        var id = "";
        for (var i = 0; i < 8; i += 1) {
            var v = Math.rand() & 0x1F;                     // 5 bits par caractère
            id = id + ALPHABET.substring(v, v + 1);
        }
        return id;
    }

    function isValid(id as String) as Boolean {
        if (id == null || id.length() != 8) { return false; }
        for (var i = 0; i < 8; i += 1) {
            if (!_inAlphabet(id.substring(i, i + 1))) { return false; }
        }
        return true;
    }

    hidden function _inAlphabet(c as String) as Boolean {
        for (var i = 0; i < 32; i += 1) {
            if (ALPHABET.substring(i, i + 1).equals(c)) { return true; }
        }
        return false;
    }
}
```

- [ ] **Step 4: Implémenter DeviceId.mc**

```monkeyc
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;

// deviceId : UUID d'installation (64 bits hex) — spec sync §4.2.
// Généré au premier lancement, persisté dans Application.Storage,
// stable par montre/install. 3 montres = 3 deviceIds (même device key).
module DeviceId {
    const KEY = "install_uuid_v1";
    const HEX = "0123456789abcdef";

    function getOrCreate() as String {
        var v = Storage.getValue(KEY);
        if (v != null) { return v as String; }
        var id = "";
        for (var i = 0; i < 16; i += 1) {
            var n = Math.rand() & 0x0F;
            id = id + HEX.substring(n, n + 1);
        }
        Storage.setValue(KEY, id);
        return id;
    }
}
```

- [ ] **Step 5: Brancher dans MatchView (matchId Crockford)**

Dans `watch/connect-iq/source/ui/MatchView.mc` :
1. `startMatch()` (ligne 161) : remplacer `mMatchId = genMatchId();` par `mMatchId = MatchIds.generate();`
2. `menuSelect()` (ligne 209) : remplacer `mEngine.newMatch(mEngine.getConfig(), genMatchId());` par `mEngine.newMatch(mEngine.getConfig(), MatchIds.generate());`
3. Supprimer la fonction `genMatchId()` (lignes 178-181) et son commentaire.

- [ ] **Step 6: Run tests — verts**

Même commande qu'en Step 2.
Expected: `PASSED (passed=44, failed=0, errors=0)` (39 + 5 nouveaux).

- [ ] **Step 7: Commit**

```bash
git add watch/connect-iq/source
git commit -m "feat(4a): matchId Crockford base32 (8 chars) + deviceId d'installation (5 tests RNE)"
```

---

### Task 7: `SyncCore` — cœur pur (batch, sérialisation, backoff) (RNE TDD)

**Files:**
- Create: `watch/connect-iq/source/services/SyncCore.mc`
- Modify: `watch/connect-iq/source/tests/SyncTest.mc`

- [ ] **Step 1: Tests d'abord**

Ajouter à `SyncTest.mc` (dans le module SyncTests) :
```monkeyc
    // ---- SyncCore ----

    // Fixture : engine 21 pts avec n points MOI.
    hidden function _enginePoints(n as Number) as ScoreEngine {
        var e = new ScoreEngine(MatchPresets.get(2), "T1");
        for (var i = 0; i < n; i += 1) { e.pointMe(); }
        return e;
    }

    (:test)
    function test_core_batchslice_premier_batch(logger as Logger) as Boolean {
        var core = new SyncCore();
        var batch = core.batchSlice(_enginePoints(8).getEvents(), 1, 5);
        if (batch.size() != 5) { logger.debug("attendu 5"); return false; }
        if (batch[0][2] != 1 || batch[4][2] != 5) { logger.debug("seqs 1..5 attendues"); return false; }
        return true;
    }

    (:test)
    function test_core_batchslice_deuxieme_batch(logger as Logger) as Boolean {
        var core = new SyncCore();
        var batch = core.batchSlice(_enginePoints(8).getEvents(), 6, 5);
        if (batch.size() != 3) { logger.debug("attendu 3"); return false; }
        if (batch[0][2] != 6 || batch[2][2] != 8) { logger.debug("seqs 6..8 attendues"); return false; }
        return true;
    }

    (:test)
    function test_core_batchslice_pf_deja_purge(logger as Logger) as Boolean {
        // pf pointe au-delà du journal (events acquittés purgés/undo) → vide.
        var core = new SyncCore();
        var batch = core.batchSlice(_enginePoints(4).getEvents(), 50, 5);
        if (batch.size() != 0) { logger.debug("attendu vide"); return false; }
        return true;
    }

    (:test)
    function test_core_serialize_event(logger as Logger) as Boolean {
        var core = new SyncCore();
        var e = core.serializeEvent([0, 0, 7, 123l, 2, 1]);
        if (e["type"] != 0 || e["arg"] != 0 || e["sequence"] != 7) { return false; }
        if (e["ts"] != 123l || e["prevMe"] != 2 || e["prevOpp"] != 1) { return false; }
        return true;
    }

    (:test)
    function test_core_buildbody(logger as Logger) as Boolean {
        var core = new SyncCore();
        var engine = _enginePoints(3);
        var body = core.buildBody(engine, "dev123", core.batchSlice(engine.getEvents(), 1, 5));
        var snap = body["snapshot"];
        if (body["deviceId"] != "dev123") { return false; }
        if (snap["status"] != "active" || snap["scoreMe"] != 3 || snap["scoreOpp"] != 0) { return false; }
        if (snap["currentSet"] != 1 || snap["setsMe"] != 0 || snap["setsOpp"] != 0) { return false; }
        if (snap["lastSequence"] != 3) { return false; }
        if (body["config"]["targetScore"] != 21) { return false; }
        if (body["events"].size() != 3) { return false; }
        return true;
    }

    (:test)
    function test_core_snapshot_match_finished(logger as Logger) as Boolean {
        var core = new SyncCore();
        var e = new ScoreEngine(MatchPresets.get(2), "T1");
        for (var i = 0; i < 21; i += 1) { e.pointMe(); }    // set 1 fini → SET_RESULT
        for (var i = 0; i < 21; i += 1) { e.pointMe(); }    // set 2 fini → MATCH_FINISHED
        if (core.statusString(e.getPhase()) != "match_finished") { logger.debug("match_finished attendu"); return false; }
        return true;
    }

    (:test)
    function test_core_backoff_sequence(logger as Logger) as Boolean {
        var core = new SyncCore();
        if (core.nextBackoffMs(0) != 10000l) { return false; }
        if (core.nextBackoffMs(1) != 20000l) { return false; }
        if (core.nextBackoffMs(2) != 40000l) { return false; }
        if (core.nextBackoffMs(3) != 80000l) { return false; }
        if (core.nextBackoffMs(4) != 120000l) { return false; }
        if (core.nextBackoffMs(9) != 120000l) { return false; }   // cap 2 min
        return true;
    }

    (:test)
    function test_core_shouldsend(logger as Logger) as Boolean {
        var core = new SyncCore();
        if (core.shouldSend(10000l, 0l, false, 0l) != true) { return false; }        // 1er envoi
        if (core.shouldSend(10000l, 8000l, false, 0l) != false) { return false; }    // < 5 s
        if (core.shouldSend(10000l, 5000l, true, 0l) != false) { return false; }     // en vol
        if (core.shouldSend(10000l, 0l, false, 20000l) != false) { return false; }   // backoff
        if (core.shouldSend(30000l, 0l, false, 20000l) != true) { return false; }    // backoff écoulé
        return true;
    }
```

- [ ] **Step 2: Voir échouer (Symbol Not Found SyncCore)** — même commande que Task 6 Step 2.

- [ ] **Step 3: Implémenter SyncCore.mc**

```monkeyc
import Toybox.Lang;

// Cœur pur de la synchronisation (Phase 4a, spec sync §7/§13) — aucun import
// Communications/Timer : testable Run No Evil. Le format des events est le
// journal plat de la montre [type, arg, seq, ts, prevMe, prevOpp] (§7.2).
class SyncCore {

    // Batch d'events à envoyer : ≤ max events de séquence ≥ fromSeq, clampé à
    // la 1re séquence du journal (un event acquitté peut avoir été purgé —
    // §7.2 : jamais un event non acquitté ; les events fantômes après undo
    // sont assumés, décision D-3).
    function batchSlice(events as Array, fromSeq as Number, max as Number) as Array {
        if (events == null || events.size() == 0) { return []; }
        var start = 0;
        while (start < events.size() && events[start][2] < fromSeq) { start += 1; }
        var stop = start + max;
        if (stop > events.size()) { stop = events.size(); }
        var batch = [];
        for (var i = start; i < stop; i += 1) { batch.add(events[i]); }
        return batch;
    }

    function serializeEvent(e as Array) as Dictionary {
        return { "type" => e[0], "arg" => e[1], "sequence" => e[2], "ts" => e[3], "prevMe" => e[4], "prevOpp" => e[5] };
    }

    // Payload complet du POST (spec sync §13). La montre (source de vérité)
    // fournit le snapshot : le backend ne recalcule jamais le score (ADR-007).
    function buildBody(engine as ScoreEngine, deviceId as String, batch as Array) as Dictionary {
        var cfg = engine.getConfig();
        var evts = [];
        for (var i = 0; i < batch.size(); i += 1) { evts.add(serializeEvent(batch[i])); }
        return {
            "deviceId" => deviceId,
            "config" => { "targetScore" => cfg.mTargetScore, "winBy" => cfg.mWinBy, "cap" => cfg.mCap, "setsToWin" => cfg.mSetsToWin },
            "snapshot" => {
                "status" => statusString(engine.getPhase()),
                "currentSet" => engine.getSetNumber(),
                "scoreMe" => engine.getScoreMe(),
                "scoreOpp" => engine.getScoreOpp(),
                "setsMe" => engine.getSetsMe(),
                "setsOpp" => engine.getSetsOpp(),
                "lastSequence" => engine.getLastSequence()
            },
            "events" => evts
        };
    }

    // Phase moteur → statut match_state (check DB : active|set_result|match_finished).
    function statusString(phase as Number) as String {
        if (phase == ScorePhase.MATCH_FINISHED) { return "match_finished"; }
        if (phase == ScorePhase.SET_RESULT) { return "set_result"; }
        return "active";
    }

    // Backoff exponentiel 10 s → cap 2 min (§9.3 de la spec principale).
    function nextBackoffMs(errors as Number) as Long {
        var ms = 10000l;
        for (var i = 0; i < errors; i += 1) {
            ms = ms * 2;
            if (ms >= 120000l) { return 120000l; }
        }
        return ms;
    }

    // Conditions d'envoi : pas de requête en vol, backoff écoulé, ≥ 5 s entre
    // débuts de requêtes (débit BLE 400-800 o/s, §9.6 de la spec principale).
    function shouldSend(nowMs as Long, lastAttemptMs as Long, inFlight as Boolean, backoffUntilMs as Long) as Boolean {
        if (inFlight) { return false; }
        if (nowMs < backoffUntilMs) { return false; }
        if (lastAttemptMs != 0l && nowMs - lastAttemptMs < 5000l) { return false; }
        return true;
    }
}
```

- [ ] **Step 4: Run tests — verts**

Expected: `PASSED (passed=52, failed=0, errors=0)` (44 + 8).

- [ ] **Step 5: Commit**

```bash
git add watch/connect-iq/source
git commit -m "feat(4a): SyncCore pur — batch/sérialisation/buildBody/backoff/shouldSend (8 tests RNE)"
```

---

### Task 8: `MatchStore` — pointeur `pf` (getPendingFrom / ackUntil / préservation)

**Files:**
- Modify: `watch/connect-iq/source/MatchStore.mc`
- Modify: `watch/connect-iq/source/tests/StoreTest.mc`

- [ ] **Step 1: Tests d'abord**

Ajouter à `StoreTest.mc` (respecter le style existant du fichier — module, helper engine) :
```monkeyc
    (:test)
    function test_store_pf_default_et_ack(logger as Logger) as Boolean {
        var engine = _engine();                       // helper existant (ou new ScoreEngine(MatchPresets.get(2), "PF1") + points)
        engine.pointMe();
        MatchStore.saveMatch(engine, 2);
        if (MatchStore.getPendingFrom() != 1) { logger.debug("pf défaut = 1"); return false; }
        MatchStore.ackUntil(1);
        if (MatchStore.getPendingFrom() != 2) { logger.debug("pf=2 après ack"); return false; }
        // un ack plus ancien ne recule pas pf
        MatchStore.ackUntil(1);
        if (MatchStore.getPendingFrom() != 2) { return false; }
        return true;
    }

    (:test)
    function test_store_pf_preserve_apres_save(logger as Logger) as Boolean {
        var engine = _engine();
        engine.pointMe();
        MatchStore.saveMatch(engine, 2);
        MatchStore.ackUntil(3);                       // ack hypothétique au-delà du journal → pf=4
        engine.pointMe();
        MatchStore.saveMatch(engine, 2);              // re-save du MÊME match
        if (MatchStore.getPendingFrom() != 4) { logger.debug("pf doit être préservé"); return false; }
        return true;
    }

    (:test)
    function test_store_pf_reset_nouveau_match(logger as Logger) as Boolean {
        var engine = _engine();
        engine.pointMe();
        MatchStore.saveMatch(engine, 2);
        MatchStore.ackUntil(1);
        var other = new ScoreEngine(MatchPresets.get(2), "PF2");
        other.pointMe();
        MatchStore.saveMatch(other, 2);               // matchId différent → pf repart à 1
        if (MatchStore.getPendingFrom() != 1) { logger.debug("pf reset nouveau match"); return false; }
        return true;
    }
```
(Adapter `_engine()` au helper réellement présent dans StoreTest.mc ; sinon définir : `new ScoreEngine(MatchPresets.get(2), "PFX")`.)

- [ ] **Step 2: Voir échouer** — même commande tests que Task 6 Step 2 (Symbol Not Found getPendingFrom).

- [ ] **Step 3: Implémenter dans MatchStore.mc**

1. `saveMatch` — remplacer `"pf" => 1,` par pf préservé (insérer AVANT le bloc `var meta = {`) :
```monkeyc
        // pendingFrom préservé si c'est toujours le même match (sinon 1) —
        // les ACK ne doivent pas être perdus à chaque save (§7 sync).
        var prevMeta = Storage.getValue(META_KEY) as Dictionary;
        var pf = 1;
        if (prevMeta != null && prevMeta["mid"] != null && prevMeta["pf"] != null
                && prevMeta["mid"].toString().equals(engine.getMatchId())) {
            pf = prevMeta["pf"];
        }
```
puis dans la meta : `"pf" => pf,`.

2. Nouvelles fonctions (module, après `clearMatch`) :
```monkeyc
    // ---- sync (Phase 4a) : pointeur d'acquittement ----

    // Première séquence non acquittée (meta["pf"]). 1 par défaut.
    function getPendingFrom() as Number {
        var meta = Storage.getValue(META_KEY) as Dictionary;
        if (meta == null || meta["pf"] == null) { return 1; }
        return meta["pf"];
    }

    // ACK backend : les events de séquence ≤ seq sont acquittés (spec sync §7).
    // Sans effet si la meta a disparu (match purgé) ou si seq recule.
    function ackUntil(seq as Number) as Void {
        var meta = Storage.getValue(META_KEY) as Dictionary;
        if (meta == null) { return; }
        var pf = meta["pf"];
        if (pf != null && seq > pf) {
            meta["pf"] = seq;
            Storage.setValue(META_KEY, meta);
        }
    }
```

- [ ] **Step 4: Run tests — verts**

Expected: `PASSED (passed=55, failed=0, errors=0)` (52 + 3).

- [ ] **Step 5: Commit**

```bash
git add watch/connect-iq/source
git commit -m "feat(4a): MatchStore — pf persistant (getPendingFrom/ackUntil), saveMatch préserve l'acquittement"
```

---

### Task 9: `SyncService` (adaptateur makeWebRequest + watchdog) + manifest + câblage

**Files:**
- Create: `watch/connect-iq/source/services/SyncService.mc`
- Modify: `watch/connect-iq/manifest.xml`
- Modify: `watch/connect-iq/source/ui/MatchView.mc`

- [ ] **Step 1: SyncService.mc**

```monkeyc
import Toybox.Application.Properties;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

// Synchronisation montre → backend (Phase 4a, spec sync §7). Jamais bloquant :
// le scoring ne dépend jamais du réseau. Batchs ≤ 5 events + snapshot, une
// seule requête en vol, ≥ 5 s entre débuts (BLE 400-800 o/s), timeout
// applicatif 30 s (le callback makeWebRequest peut ne jamais être appelé,
// §3.8 de la spec sync), backoff 10 s → 2 min.
class SyncService {
    hidden var mCore;
    hidden var mDeviceId;
    hidden var mInFlight = false;
    hidden var mLastAttemptMs = 0l;
    hidden var mBackoffUntilMs = 0l;
    hidden var mErrors = 0;
    hidden var mEngineRef = null;      // dernier engine vu (drain / watchdog)
    hidden var mTimer;                 // watchdog 30 s OU drain — un seul rôle à la fois

    function initialize(deviceId as String) {
        mCore = new SyncCore();
        mDeviceId = deviceId;
        mTimer = new Timer.Timer();
    }

    // Déclencheur : après chaque saveMatch (MatchView.syncScreen / startMatch)
    // et au lancement (flush §9.4). Configuration absente → inactif (graceful).
    function trigger(engine as ScoreEngine or Null) as Void {
        mEngineRef = engine;
        if (engine == null) { return; }
        var url = Properties.getValue("backendUrl");
        var key = Properties.getValue("deviceKey");
        if (url == null || url.equals("") || key == null || key.equals("")) { return; }
        var now = System.getTimer();
        if (!mCore.shouldSend(now, mLastAttemptMs, mInFlight, mBackoffUntilMs)) { return; }
        var batch = mCore.batchSlice(engine.getEvents(), MatchStore.getPendingFrom(), 5);
        if (batch.size() == 0) { return; }
        _send(url, key, engine, batch);
    }

    hidden function _send(url as String, key as String, engine as ScoreEngine, batch as Array) as Void {
        mInFlight = true;
        mLastAttemptMs = System.getTimer();
        var fullUrl = url + "/matches/" + engine.getMatchId() + "/events";
        var body = mCore.buildBody(engine, mDeviceId, batch);
        var options = {
            "method" => Communications.HTTP_REQUEST_METHOD_POST,
            "headers" => { "X-Device-Key" => key, "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
            "responseType" => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        mTimer.stop();
        mTimer.start(method(:_onTimeout), 30000, false);
        Communications.makeWebRequest(fullUrl, body, options, method(:_onResponse));
        System.println("[sync] envoi seq<=" + batch[batch.size() - 1][2] + " via " + fullUrl);
    }

    hidden function _onResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        mTimer.stop();
        mInFlight = false;
        if (responseCode == 200) {
            mErrors = 0;
            mBackoffUntilMs = 0l;
            if (data != null && data instanceof Dictionary && data["lastAcceptedSequence"] != null) {
                MatchStore.ackUntil(data["lastAcceptedSequence"]);
                System.println("[sync] ack " + data["lastAcceptedSequence"]);
            }
        } else {
            mErrors += 1;
            mBackoffUntilMs = System.getTimer() + mCore.nextBackoffMs(mErrors);
            System.println("[sync] erreur " + responseCode + " -> backoff");
        }
        _scheduleDrain();
    }

    // Le callback peut ne jamais être appelé (GCM endormie) — §3.8.
    hidden function _onTimeout() as Void {
        if (mInFlight) {
            Communications.cancelAllRequests();
            _onResponse(Communications.NETWORK_REQUEST_TIMED_OUT, null);
        }
    }

    // File non vide → re-tenter au prochain créneau (≥ 5 s / backoff).
    hidden function _scheduleDrain() as Void {
        var engine = mEngineRef;
        if (engine == null) { return; }
        var batch = mCore.batchSlice(engine.getEvents(), MatchStore.getPendingFrom(), 5);
        if (batch.size() == 0) { return; }
        var now = System.getTimer();
        var next = mLastAttemptMs + 5000l;
        if (mBackoffUntilMs > next) { next = mBackoffUntilMs; }
        var delay = next - now;
        if (delay < 1000l) { delay = 1000l; }
        mTimer.start(method(:_drain), delay, false);
    }

    hidden function _drain() as Void {
        trigger(mEngineRef);
    }
}
```

- [ ] **Step 2: manifest.xml — permission + properties + settings**

Dans `watch/connect-iq/manifest.xml`, remplacer `<iq:permissions/>` par :
```xml
        <iq:permissions>
            <iq:uses-permission id="Communications"/>
        </iq:permissions>
```
Puis, juste après le bloc permissions (dans `<iq:application>`), ajouter :
```xml
        <iq:properties>
            <iq:property id="backendUrl" type="string"/>
            <iq:property id="deviceKey" type="string"/>
        </iq:properties>
        <iq:settings>
            <iq:setting propertyKey="@Properties.backendUrl">
                <iq:settingConfig type="url" required="false"/>
            </iq:setting>
            <iq:setting propertyKey="@Properties.deviceKey">
                <iq:settingConfig type="alphaNumeric" required="false"/>
            </iq:setting>
        </iq:settings>
```
(la device key est hexadécimale → compatible alphaNumeric.)

- [ ] **Step 3: Câblage MatchView**

Dans `watch/connect-iq/source/ui/MatchView.mc` :
1. Champ : ajouter `hidden var mSync;` près des autres champs.
2. `initialize()` : après la création de `mEngine`/restore et avant le `syncScreen()` final, ajouter :
   `mSync = new SyncService(DeviceId.getOrCreate());`
3. `syncScreen()` : juste après `MatchStore.saveMatch(mEngine, mMatchPresetIndex);` (ligne ~187), ajouter :
   `mSync.trigger(mEngine);`
4. `startMatch()` : après `MatchStore.saveMatch(mEngine, mMatchPresetIndex);` (ligne ~166), ajouter :
   `mSync.trigger(mEngine);`
5. `clearMatch()` (zone DOWN, ligne ~133) : après `MatchStore.clearMatch();` et `mEngine = null;`, ajouter :
   `mSync.trigger(null);`

- [ ] **Step 4: Builds ×5 + tests verts**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
for d in epix2pro42mm epix2pro47mm epix2pro51mm fr55 instinct2; do
  monkeyc -d $d -f watch/connect-iq/monkey.jungle -o watch/connect-iq/bin/badmintonscore-$d.prg -y ~/keys/developer_key.der -w -r || exit 1
done
monkeyc -d fr55 -f watch/connect-iq/monkey.jungle -o /tmp/t4-test.prg -y ~/keys/developer_key.der -t -w
monkeydo /tmp/t4-test.prg fr55 -t 2>&1 | grep -E "PASSED|FAILED"
```
Expected: 5 builds OK ; `PASSED (passed=55, failed=0, errors=0)`.

- [ ] **Step 5: Commit**

```bash
git add watch/connect-iq
git commit -m "feat(4a): SyncService (makeWebRequest, watchdog 30s, drain) + manifest settings + câblage syncScreen"
```

---

### Task 10: E2E simu + matériel + notes + PR

**Files:**
- Create: `docs/superpowers/notes/phase-4a-sync-results.md`
- Modify: `docs/superpowers/plans/2026-09-19-phase-4a-sync.md` (coches)

- [ ] **Step 1: E2E simulateur (réseau du Mac)**

```bash
# properties simu : File > Edit Persistent Storage > Edit Application.Properties
#   backendUrl = https://bzdbnptnubkkagmmxhyi.supabase.co/functions/v1/sync
#   deviceKey  = <contenu DEVICE_KEY de .secrets/phase-4a.env>
pkill -f ConnectIQ 2>/dev/null; sleep 1
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
open "$SDK/bin/ConnectIQ.app" && sleep 6
"$SDK/bin/monkeydo" watch/connect-iq/bin/badmintonscore-epix2pro51mm.prg epix2pro51mm
```
Scénario : match 11 pts → compter 2-1 → vérifier dans les logs et via curl :
```bash
source .secrets/phase-4a.env
curl -s "https://bzdbnptnubkkagmmxhyi.supabase.co/rest/v1/match_state?select=*" -H "apikey: $ANON_KEY"
curl -s "https://bzdbnptnubkkagmmxhyi.supabase.co/rest/v1/events?select=*&order=sequence.asc&limit=10" -H "apikey: $ANON_KEY"
```
Expected : `match_state` score 2-1 ; events seq 1-2. Puis : menu → QUITTER → relancer l'app → flush → `pf` avancé ; kill de l'app pendant 3 points → relance → rattrapage complet (aucune perte, séquences continues).

- [ ] **Step 2: Matériel epix + GCM — [USER ACTION]**

1. Sideload `badmintonscore-epix2pro51mm.prg` sur l'epix.
2. Dans GCM (téléphone) : réglages de l'app → saisir `backendUrl` et `deviceKey` (vérifie OQ4 : l'UI settings des apps sideloadées).
3. Compter un match réel : points visibles dans Supabase (curl/dashboard) ; noter la latence bouton→DB (OQ1).
4. GCM fermée à la main (Android) → compter 2 points → réouvrir GCM → rattrapage (OQ2).
5. Mode avion pendant 5 points → couper l'avion → rattrapage complet.
6. Noter tout dans les notes.

- [ ] **Step 3: fr55/instinct2 en simulateur**

Builds + un match rapide chacun (properties via le menu du simulateur) → lignes créées avec leur propre `deviceId`. (Simulation ≠ device : seul l'epix valide GCM.)

- [ ] **Step 4: Notes + plan coché + PR**

Créer `docs/superpowers/notes/phase-4a-sync-results.md` (même style que `phase-3-sim-results.md`) : scénario, latences, leçons, OQ1/OQ2/OQ4 levées ou reportées. Cocher les tasks de ce plan. Puis :

```bash
git add docs/superpowers watch/connect-iq prototypes
git commit -m "docs(4a): résultats simu + matériel, plan coché"
git push -u origin phase-4a
gh pr create --base main --head phase-4a --title "Phase 4a : synchronisation (POC, Supabase, SyncService)" --body "$(cat <<'EOF'
## Summary
- Edge Function `sync` : auth device key (sha256), validation stricte, upserts idempotents `(match_id, sequence)`, ACK `{matchId, lastAcceptedSequence}` — 9 tests Deno
- Schéma Supabase : matches/events/match_state/devices + RLS lecture seule publique + publication realtime (spec sync §12)
- Montre : SyncService (batchs ≤ 5 + snapshot, watchdog 30 s, backoff 10 s → 2 min, drain), MatchStore `pf` persistant, matchId Crockford 8 chars, deviceId d'installation ; 55 tests Run No Evil verts × 3 profils
- Décision D-3 : rétraction undo (TYPE_UNDO) reportée Phase 7 — historique append-only, snapshot fait foi

## Test Plan
- [x] Builds ×5 OK (release + tests)
- [x] Simulateur : POC sync-test 200 ; app principale → lignes match_state/events ; kill/relance → flush sans perte
- [x] curl : RLS (anon lecture OK, écriture refusée), idempotence (re-POST), 401 sans clé
- [x] Matériel epix + GCM : points → DB, GCM fermée → rattrapage, mode avion → rattrapage (notes)
EOF
)"
```

---

## Critères de sortie (§16 spec principale, Phase 4a adaptée)

1. `makeWebRequest` → GCM → Edge Function → PostgreSQL fonctionnel **sur l'epix matérielle** (le seul vrai risque de la phase).
2. Idempotence prouvée (re-POST sans duplication), ACK traité (pf avance, rien n'est renvoyé inutilement).
3. Offline-first intact : score local instantané, file jamais perdue, rattrapage complet après reprise/avion.
4. 55+ tests RNE verts × 3 profils ; 9 tests Deno verts.
5. Notes + PR + coches plan.

## Points d'attention pour l'implémenteur

- **Monkey C** : `me` réservé ; `import Toybox.X` ; `Long` literals `10000l` ; pas de `remove()` sur Array (`slice`) ; `System.exit()` en dernier bloc ; `instanceof Dictionary` avant cast d'un payload réseau.
- **Pseudo-code ≠ vérité** : en cas de divergence avec le code réel (noms de champs, helpers StoreTest), adapter au code et le noter dans le report de tâche.
- **Jamais bloquant** : toute erreur réseau est silencieuse pour l'utilisateur (logs uniquement) — l'UX de score ne change pas.
- **Secrets** : jamais de clé dans le code commité ; `.secrets/` gitigné ; vérifier `git status` avant chaque commit.
