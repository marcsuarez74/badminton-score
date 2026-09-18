# Phase 3 — Persistance — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal :** Le match survit à la fermeture/relance de l'app (kill/restart sans perte, §16 ligne 3) ; reprise directe sur le bon écran (§5 Démarrage) ; format mémorisé ; historique borné 200 événements avec purge par lots (§7.2).

**Architecture :** `MatchStore` (module, `source/MatchStore.mc`) encapsule `Application.Storage` — meta (Dictionary : matchId, presetIndex, base state, lastSequence, pendingFrom) + événements en **lots plats** de 30 (tableaux de Numbers, jamais d'imbrication risque) + préférence format (`badminton_prefs_v1`). Le moteur gagne un **état de base** (`mBase*`) : `replay()` = base + journal ; `restore(base, events)` restaure ; `trimEvents(175)` purge les plus anciens en avançant la base (jamais le dernier event). Sauvegarde **à chaque mutation** (via `syncScreen`, setValue synchrone) + filet `App.onStop`.

**Tech Stack :** Monkey C / Connect IQ SDK 9.2.0, `Application.Storage` (minApi 3.4 ✓), tests Run No Evil (simu), branch `phase-3` depuis `main`.

**Décisions & dérogations documentées (à reprendre dans les findings Task 5) :**
- **Meta = état de BASE, pas l'état dérivé complet** : l'état reconstruit = replay(base + events conservés). Esprit §7.2 respecté (« pas de replay complet nécessaire » : le tail conservé ≤ 175 events, coût négligeable) et modèle cohérent avec la purge.
- **Purge (§7.2, historique borné 200)** : au-delà de 200 events, `trimEvents(175)` retire les plus anciens **par lot aligné** (175 = 7×30... non : 175 = 7×25 ; on garde simplement les 175 derniers) en avançant la base — le dernier event n'est jamais purgé ; l'UNDO reste correct après purge. Nuance « jamais un event non acquitté » : en Phase 3 rien n'est acquitté (pas de backend) — la nuance s'appliquera en Phase 4a.
- **pendingEvents** : pas de file dupliquée en Phase 3 (YAGNI — sans ACK, tout est pending). Meta porte `pf` (pendingFrom = 1) pour que la Phase 4a sache d'où réémettre.
- **Match fini** : reste persisté tant que l'utilisateur n'a pas fait DOWN (relance → ré-affiche MATCH_TERMINE, lisible) ; DOWN → SETUP **purge** le storage (le match n'est plus « en cours », §5).
- **Format mémorisé (§5)** : `savePresetIndex` au START ; utilisé à l'écran Setup frais.

**Vocabulaire du plan :** SDK = `$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")` ; clé = `~/keys/developer_key.der` ; verdict de test = ligne `PASSED (passed=N, failed=0, errors=0)` ; simu : `open "$SDK/bin/ConnectIQ.app"`, sleep 6, puis `monkeydo` ; relancer l'app au simu = kill/restart équivalent (nouvelle instance AppBase).

---

### Task 1: Moteur — état de base, restore, trimEvents (TDD)

**Files:**
- Modify: `watch/connect-iq/source/engine/ScoreEngine.mc`
- Test: `watch/connect-iq/source/tests/EngineTest.mc` (3 tests)

- [x] **Step 1: Créer la branche**

```bash
cd /Users/marcsuarez/Documents/badminton-score
git checkout main -q && git pull -q && git checkout -b phase-3
```

- [x] **Step 2: Écrire les 3 tests (rouge attendu : `restore`/`trimEvents`/`getBaseState` inconnus)**

Dans `EngineTest.mc`, section protocole (après `test_engine_undo_sequence_monotonic`), ajouter :

```monkeyc
// ---- ScoreEngine : état de base + restore + purge (spec §7.2, Phase 3) ----

(:test)
function test_engine_restore_roundtrip(logger as Logger) as Boolean {
    var e1 = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e1, 21, 19);           // SET_RESULT, sets 1-0
    var e2 = new ScoreEngine(MatchPresets.get(2), "m1");
    e2.restore(e1.getBaseState(), e1.getEvents());
    Test.assertEqualMessage(e1.getPhase(), e2.getPhase(), "restore : phase identique");
    Test.assertEqualMessage(e1.getScoreMe(), e2.getScoreMe(), "restore : score me");
    Test.assertEqualMessage(e1.getScoreOpp(), e2.getScoreOpp(), "restore : score opp");
    Test.assertEqualMessage(e1.getSetsMe(), e2.getSetsMe(), "restore : sets me");
    Test.assertEqualMessage(e1.getSetNumber(), e2.getSetNumber(), "restore : set number");
    Test.assertEqualMessage(e1.getLastSetScoreMe(), e2.getLastSetScoreMe(), "restore : last set me");
    Test.assertEqualMessage(e1.getEvents().size(), e2.getEvents().size(), "restore : journal");
    e2.undo();                           // l'undo marche après restore
    Test.assertEqualMessage(0, e2.getPhase(), "restore + undo : set repris (PLAYING)");
    Test.assertEqualMessage(21, e2.getScoreMe(), "restore + undo : 21-19");
    Test.assertEqualMessage(0, e2.getSetsMe(), "restore + undo : sets 0-0");
    return true;
}

(:test)
function test_engine_restore_then_extend(logger as Logger) as Boolean {
    var e1 = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e1, 5, 3);              // PLAYING 5-3
    var e2 = new ScoreEngine(MatchPresets.get(2), "m1");
    e2.restore(e1.getBaseState(), e1.getEvents());
    e2.pointMe();                        // prolonger après restore : base + events + nouvel event
    Test.assertEqualMessage(6, e2.getScoreMe(), "restore + point : 6-3");
    Test.assertEqualMessage(9, e2.getEvents().size(), "journal 8 + 1");
    Test.assertEqualMessage("m1:9", e2.getEventId(8), "sequence poursuite (9)");
    return true;
}

(:test)
function test_engine_trim_events(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 0);              // 21-0 : 22 events (21 POINT + SET_FINISHED), phase SET_RESULT
    e.changeSet();                       // 23 events, set 2, PLAYING
    enginePoints(e, 21, 0);              // 21-0 : +22 = 45 events + MATCH_FINISHED = 46
    Test.assertEqualMessage(46, e.getEvents().size(), "46 events avant purge");
    Test.assertEqualMessage(2, e.getSetsMe(), "sets 2-0");
    e.trimEvents(10);                    // purge les 36 plus anciens (base avance)
    Test.assertEqualMessage(10, e.getEvents().size(), "journal purge : 10");
    Test.assertEqualMessage(2, e.getSetsMe(), "etat derive intact apres purge (sets)");
    Test.assertEqualMessage(21, e.getScoreMe(), "etat derive intact apres purge (score)");
    Test.assertEqualMessage(2, e.getPhase(), "etat derive intact apres purge (phase)");
    Test.assertEqualMessage(37, e.getEvent(0)[2], "premier event retenu : seq 37");
    Test.assertEqualMessage(46, e.getEvent(9)[2], "dernier event : seq 46");
    return true;
}
```

- [x] **Step 3: Vérifier le rouge**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
"$SDK/bin/monkeyc" -d epix2pro51mm -f watch/connect-iq/monkey.jungle \
  -o /tmp/bad-test.prg -y ~/keys/developer_key.der -w -t
```
Attendu : échec de compilation (`restore`/`trimEvents`/`getBaseState` inconnus).

- [x] **Step 4: Implémenter le moteur** — dans `ScoreEngine.mc` :

Champs (après `mLastSequence`) :

```monkeyc
    // État de base (§7.2) : état produit par les événements PURGÉS du journal.
    // replay() = base + journal. Journal plein → base nulle ; après purge → base avancée.
    var mBasePhase;
    var mBaseScoreMe;
    var mBaseScoreOpp;
    var mBaseSetsMe;
    var mBaseSetsOpp;
    var mBaseSetNumber;
    var mBaseLastSetScoreMe;
    var mBaseLastSetScoreOpp;
```

Constante module (dans `ScorePhase`, pour la lisibilité du tableau base) — non, garder simple : l'ordre du tableau base est documenté sur `getBaseState()`.

Dans `initialize`, après `mLastSequence = 0;` :

```monkeyc
        resetBase();
```

Dans `newMatch`, après `mLastSequence = 0;` :

```monkeyc
        resetBase();
```

Nouvelles méthodes privées + API (après `replay()`, avant `applyEvent` — ou en section dédiée après `trimEvents`) :

```monkeyc
    // ---- état de base (Phase 3, §7.2) ----

    function resetBase() as Void {
        mBasePhase = ScorePhase.PLAYING;
        mBaseScoreMe = 0;
        mBaseScoreOpp = 0;
        mBaseSetsMe = 0;
        mBaseSetsOpp = 0;
        mBaseSetNumber = 1;
        mBaseLastSetScoreMe = 0;
        mBaseLastSetScoreOpp = 0;
    }

    function copyBaseToDerived() as Void {
        mPhase = mBasePhase;
        mScoreMe = mBaseScoreMe;
        mScoreOpp = mBaseScoreOpp;
        mSetsMe = mBaseSetsMe;
        mSetsOpp = mBaseSetsOpp;
        mSetNumber = mBaseSetNumber;
        mLastSetScoreMe = mBaseLastSetScoreMe;
        mLastSetScoreOpp = mBaseLastSetScoreOpp;
    }

    function copyDerivedToBase() as Void {
        mBasePhase = mPhase;
        mBaseScoreMe = mScoreMe;
        mBaseScoreOpp = mScoreOpp;
        mBaseSetsMe = mSetsMe;
        mBaseSetsOpp = mSetsOpp;
        mBaseSetNumber = mSetNumber;
        mBaseLastSetScoreMe = mLastSetScoreMe;
        mBaseLastSetScoreOpp = mLastSetScoreOpp;
    }
```

Remplacer le début de `replay()` (l'initialisation de l'état dérivé) par la copie de la base :

```monkeyc
    function replay() as Void {
        copyBaseToDerived();
        for (var i = 0; i < mEvents.size(); i += 1) {
            applyEvent(mEvents[i]);
        }
    }
```

API restore / trim / getters (à la fin, après `getEventId`) :

```monkeyc
    // Restauration (§7.2) : base = état produit par les événements absents du
    // journal ; events = journal conservé (6 slots). Ordre base :
    // [phase, scoreMe, scoreOpp, setsMe, setsOpp, setNumber, lastSetMe, lastSetOpp].
    function restore(base as Array, events as Array) as Void {
        mBasePhase = base[0];
        mBaseScoreMe = base[1];
        mBaseScoreOpp = base[2];
        mBaseSetsMe = base[3];
        mBaseSetsOpp = base[4];
        mBaseSetNumber = base[5];
        mBaseLastSetScoreMe = base[6];
        mBaseLastSetScoreOpp = base[7];
        mEvents = events;
        // la séquence repart du dernier event journalisé (sinon réinitialisée) —
        // correction validée en TDD (test_engine_restore_then_extend : "m1:9") ;
        // meta "ls" (Task 2) = filet si le journal est entièrement purgé.
        var n = events.size();
        if (n > 0) { mLastSequence = events[n - 1][2]; }
        replay();
    }

    // Purge §7.2 : historique borné — au-delà de maxKeep, retire les plus
    // anciens et avance la base de leur effet. Jamais le dernier event.
    function trimEvents(maxKeep as Number) as Void {
        var size = mEvents.size();
        if (size <= maxKeep) { return; }
        var drop = size - maxKeep;
        copyBaseToDerived();
        for (var i = 0; i < drop; i += 1) {
            applyEvent(mEvents[i]);
        }
        copyDerivedToBase();
        mEvents = mEvents.slice(drop, size);
        replay();
    }

    function getBaseState() as Array {
        return [mBasePhase, mBaseScoreMe, mBaseScoreOpp, mBaseSetsMe, mBaseSetsOpp,
            mBaseSetNumber, mBaseLastSetScoreMe, mBaseLastSetScoreOpp];
    }

    function getMatchId() as String { return mMatchId; }
    function getLastSequence() as Number { return mLastSequence; }
```

- [x] **Step 5: Vérifier le vert**

```bash
"$SDK/bin/monkeyc" -d epix2pro51mm -f watch/connect-iq/monkey.jungle \
  -o watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg -y ~/keys/developer_key.der -w -t
open "$SDK/bin/ConnectIQ.app" && sleep 6
"$SDK/bin/monkeydo" watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg epix2pro51mm -t
```
Attendu : `PASSED (passed=35, failed=0, errors=0)` (30 + 5, dont 2 de revue). **Point d'attention** : les 30 tests existants doivent rester verts — le seul changement comportemental est `replay()` qui part maintenant de la base (nulle pour eux).

- [x] **Step 6: Commit**

```bash
git add watch/connect-iq/source/engine/ScoreEngine.mc watch/connect-iq/source/tests/EngineTest.mc
git commit -m "feat(phase3): état de base du moteur — restore(base, events) et trimEvents (purge §7.2)"
```

---

### Task 2: MatchStore — meta + lots d'événements + préfs (TDD)

**Files:**
- Create: `watch/connect-iq/source/MatchStore.mc`
- Test: `watch/connect-iq/source/tests/StoreTest.mc` (3 tests)

**Format (§7.2) :**
- `badminton_meta_v1` = Dictionary `{ "v": 1, "mid": String, "pi": Number, "pf": 1, "ls": Number, "base": [8 Numbers] }`
- `badminton_events_v1.<n>` = tableau **plat** de Numbers (6 slots × 30 events max/lot — jamais de tableau imbriqué dans Storage)
- `badminton_prefs_v1` = Number (presetIndex)
- Constantes : `CHUNK = 30`, `MAX_EVENTS = 200`, `KEEP = 175`.

- [x] **Step 1: Écrire les 3 tests (rouge attendu : MatchStore inconnu)**

Nouveau fichier `watch/connect-iq/source/tests/StoreTest.mc` :

```monkeyc
import Toybox.Lang;
import Toybox.Test;

// ---- MatchStore : persistance §7.2 (Phase 3) ----

(:test)
function test_store_roundtrip(logger as Logger) as Boolean {
    MatchStore.clearMatch();               // état propre avant test
    var e = new ScoreEngine(MatchPresets.get(2), "mP");
    enginePoints(e, 21, 19);
    e.changeSet();                         // 42 events, set 2, 0-0, sets 1-0
    MatchStore.saveMatch(e, 2);
    var loaded = MatchStore.loadMatch();
    Test.assertEqualMessage(loaded != null, true, "meta presente apres save");
    Test.assertEqualMessage("mP", loaded["mid"], "matchId restaure");
    Test.assertEqualMessage(2, loaded["pi"], "preset index restaure");
    Test.assertEqualMessage(42, loaded["ls"], "lastSequence restaure");
    Test.assertEqualMessage(42, loaded["events"].size(), "42 events restaures");
    var e2 = new ScoreEngine(MatchPresets.get(2), loaded["mid"]);
    e2.restore(loaded["base"], loaded["events"]);
    Test.assertEqualMessage(0, e2.getPhase(), "restore : PLAYING (set 2)");
    Test.assertEqualMessage(2, e2.getSetNumber(), "restore : set 2");
    Test.assertEqualMessage(1, e2.getSetsMe(), "restore : sets 1-0");
    MatchStore.clearMatch();
    Test.assertEqualMessage(MatchStore.loadMatch() == null, true, "clear : plus de meta");
    return true;
}

(:test)
function test_store_chunks_41_events(logger as Logger) as Boolean {
    MatchStore.clearMatch();
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 19);               // 41 events (40 POINT + SET_FINISHED)
    MatchStore.saveMatch(e, 2);            // 41 > 30 : au moins 2 lots
    var loaded = MatchStore.loadMatch();
    Test.assertEqualMessage(41, loaded["events"].size(), "41 events via plusieurs lots");
    Test.assertEqualMessage(41, loaded["events"][40][2], "dernier event : seq 41");
    Test.assertEqualMessage(ScoreEvent.TYPE_SET_FINISHED, loaded["events"][40][0], "dernier = SET_FINISHED");
    MatchStore.clearMatch();
    return true;
}

(:test)
function test_store_prefs(logger as Logger) as Boolean {
    MatchStore.savePresetIndex(1);
    Test.assertEqualMessage(1, MatchStore.loadPresetIndex(), "prefs : format 15 pts memorise");
    MatchStore.savePresetIndex(2);         // hygiene : valeur par defaut
    return true;
}
```

- [x] **Step 2: Vérifier le rouge**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
"$SDK/bin/monkeyc" -d epix2pro51mm -f watch/connect-iq/monkey.jungle \
  -o /tmp/bad-test.prg -y ~/keys/developer_key.der -w -t
```
Attendu : échec (`MatchStore` inconnu).

- [x] **Step 3: Implémenter `MatchStore`** — nouveau fichier `watch/connect-iq/source/MatchStore.mc` :

```monkeyc
import Toybox.Application.Storage;
import Toybox.Lang;

// Persistance du match (spec §7.2, Phase 3). Application.Storage : 8 Ko/valeur,
// 128 Ko au total — découpage en meta + lots plats de 30 events (6 Numbers par
// event, jamais d'imbrication). Écriture à chaque mutation (setValue synchrone).
module MatchStore {
    const META_KEY = "badminton_meta_v1";
    const EVT_PREFIX = "badminton_events_v1.";
    const PREFS_KEY = "badminton_prefs_v1";
    const CHUNK = 30;         // events par lot (~1,5 Ko < 8 Ko)
    const KEEP = 175;         // events conservés après purge (§7.2 : borné 200, purge par lots)

    // ---- préférence format (§5 : mémorisé pour les matchs suivants) ----

    function savePresetIndex(i as Number) as Void {
        Storage.setValue(PREFS_KEY, i);
    }

    function loadPresetIndex() as Number {
        var v = Storage.getValue(PREFS_KEY);
        return (v == null) ? 2 : v;        // défaut : 21 POINTS
    }

    // ---- match ----

    // Sauvegarde synchrone : purge éventuelle, lots d'events, meta.
    function saveMatch(engine as ScoreEngine, presetIndex as Number) as Void {
        engine.trimEvents(KEEP);           // no-op si journal ≤ 200 (§7.2)
        var events = engine.getEvents();
        var chunk = 0;
        var i = 0;
        while (i < events.size()) {
            var flat = [];
            var stop = i + CHUNK;
            if (stop > events.size()) { stop = events.size(); }
            for (var j = i; j < stop; j += 1) {
                var ev = events[j];
                for (var k = 0; k < 6; k += 1) {
                    flat.add(ev[k]);
                }
            }
            Storage.setValue(EVT_PREFIX + chunk, flat);
            chunk += 1;
            i = stop;
        }
        // supprime les lots orphelins (journal rétréci / nouveau match)
        while (Storage.getValue(EVT_PREFIX + chunk) != null) {
            Storage.remove(EVT_PREFIX + chunk);
            chunk += 1;
        }
        var meta = {
            "v" => 1,
            "mid" => engine.getMatchId(),
            "pi" => presetIndex,
            "pf" => 1,                     // pendingFrom : rien d'acquitté en Phase 3 (§7.2)
            "ls" => engine.getLastSequence(),
            "base" => engine.getBaseState()
        };
        Storage.setValue(META_KEY, meta);
    }

    // Retourne null si aucun match persisté, sinon
    // { "mid", "pi", "ls", "base", "events" } — events = Array de 6-slots.
    function loadMatch() as Dictionary {
        var meta = Storage.getValue(META_KEY);
        if (meta == null) { return null; }
        var events = [];
        var chunk = 0;
        while (true) {
            var flat = Storage.getValue(EVT_PREFIX + chunk);
            if (flat == null) { break; }
            for (var i = 0; i + 5 < flat.size(); i += 6) {
                events.add([flat[i], flat[i + 1], flat[i + 2], flat[i + 3], flat[i + 4], flat[i + 5]]);
            }
            chunk += 1;
        }
        return {
            "mid" => meta["mid"],
            "pi" => meta["pi"],
            "ls" => meta["ls"],
            "base" => meta["base"],
            "events" => events
        };
    }

    function clearMatch() as Void {
        Storage.remove(META_KEY);
        var chunk = 0;
        while (Storage.getValue(EVT_PREFIX + chunk) != null) {
            Storage.remove(EVT_PREFIX + chunk);
            chunk += 1;
        }
    }
}
```

- [x] **Step 4: Vérifier le vert**

```bash
"$SDK/bin/monkeyc" -d epix2pro51mm -f watch/connect-iq/monkey.jungle \
  -o watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg -y ~/keys/developer_key.der -w -t
open "$SDK/bin/ConnectIQ.app" && sleep 6
"$SDK/bin/monkeydo" watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg epix2pro51mm -t
```
Attendu : `PASSED (passed=39, failed=0, errors=0)` (33 + 3). **Si Storage échoue dans le runner** (getValue/setValue indisponibles au simu test — improbable, API système) : le rapport l'indiquera, ne pas contourner en mockant — escalader au contrôleur.

- [x] **Step 5: Commit**

```bash
git add watch/connect-iq/source/MatchStore.mc watch/connect-iq/source/tests/StoreTest.mc
git commit -m "feat(phase3): MatchStore — meta + lots plats d'événements + préfs format (§7.2)"
```

---

### Task 3: Câblage UI/App — reprise au lancement, sauvegarde par mutation, purge à la sortie

**Files:**
- Modify: `watch/connect-iq/source/ui/MatchView.mc`
- Modify: `watch/connect-iq/source/App.mc`
- Pas de test unitaire (UI) — validation simu Task 4. Builds ×5 + 36 tests verts exigés.

- [x] **Step 1: MatchView.initialize — reprise §5** — remplacer :

```monkeyc
    function initialize() {
        View.initialize();
    }
```

par :

```monkeyc
    function initialize() {
        View.initialize();
        mSetupIndex = MatchStore.loadPresetIndex();   // format mémorisé (§5)
        var saved = MatchStore.loadMatch();
        if (saved != null) {
            // Match en cours persisté : reprise directe (§5 Démarrage)
            mSetupIndex = saved["pi"];
            mMatchId = saved["mid"];
            mEngine = new ScoreEngine(MatchPresets.get(mSetupIndex), mMatchId);
            mEngine.restore(saved["base"], saved["events"]);
            mEngine.setLastSequence(saved["ls"]);   // filet D-2 APRÈS restore (undo préalable)
            mScreen = MatchScreen.SCORE;              // syncScreen dérive SCORE/SET_RESULT/MATCH_FINISHED
        }
        WatchUi.requestUpdate();
    }
```

- [x] **Step 2: syncScreen — sauvegarde à chaque mutation (§7.2)** — ajouter en tête de `syncScreen` :

```monkeyc
    function syncScreen() as Void {
        if (mEngine != null) {
            MatchStore.saveMatch(mEngine, mSetupIndex);   // setValue synchrone, §7.2
        }
        var p = mEngine.getPhase();
        ... (reste inchangé)
```

- [x] **Step 3: menuSelect RESET via syncScreen** (sauvegarde du nouveau match) — remplacer la branche 2 :

```monkeyc
        } else if (mMenuIndex == 2) {
            mEngine.newMatch(mEngine.getConfig(), genMatchId());   // Réinitialiser
            syncScreen();                                          // SCORE + sauvegarde
        }
```

- [x] **Step 4: DOWN sur MATCH_FINISHED purge le storage** (le match n'est plus « en cours ») — remplacer la branche MATCH_FINISHED de `onDown` :

```monkeyc
        if (mScreen == MatchScreen.MATCH_FINISHED) {
            MatchStore.clearMatch();             // résultat consulté → prochain lancement : Setup (§5)
            mScreen = MatchScreen.SETUP;         // DOWN = NOUVEAU (format mémorisé)
            WatchUi.requestUpdate();
            return true;
        }
```

- [x] **Step 5: startMatch mémorise le format** — dans `startMatch`, après `mMatchId = genMatchId();` :

```monkeyc
        MatchStore.savePresetIndex(mSetupIndex);
```

- [x] **Step 6: MatchView.persist() + App.onStop (filet §7.2)** — dans MatchView (après `startMatch`) :

```monkeyc
    // Filet de sauvegarde (App.onStop, §7.2) — chaque mutation sauvegarde déjà.
    function persist() as Void {
        if (mEngine != null) {
            MatchStore.saveMatch(mEngine, mSetupIndex);
        }
    }
```

`App.mc` complet :

```monkeyc
using Toybox.Application;
using Toybox.WatchUi;

// Persistance : sauvegarde à chaque mutation (MatchView.syncScreen) + filet
// onStop (§7.2). Reprise au lancement : MatchView.initialize (§5 Démarrage).
class BadmintonApp extends Application.AppBase {

    var mView;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        mView = new MatchView();
        return [mView, new MatchDelegate(mView)];
    }

    function onStop() as Void {
        if (mView != null) {
            mView.persist();
        }
    }
}
```

- [x] **Step 7: Build × 5 + tests verts**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
for d in epix2pro42mm epix2pro47mm epix2pro51mm fr55 instinct2; do
  "$SDK/bin/monkeyc" -d $d -f watch/connect-iq/monkey.jungle \
    -o watch/connect-iq/bin/badmintonscore-$d.prg -y ~/keys/developer_key.der -w -r || exit 1
done
"$SDK/bin/monkeyc" -d epix2pro51mm -f watch/connect-iq/monkey.jungle \
  -o watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg -y ~/keys/developer_key.der -w -t
open "$SDK/bin/ConnectIQ.app" && sleep 6
"$SDK/bin/monkeydo" watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg epix2pro51mm -t
```
Attendu : 5 builds OK, `PASSED (passed=39, failed=0, errors=0)`.

- [x] **Step 8: Commit**

```bash
git add watch/connect-iq/source/ui/MatchView.mc watch/connect-iq/source/App.mc
git commit -m "feat(phase3): reprise au lancement (§5), sauvegarde par mutation + onStop, purge au DOWN (§7.2)"
```

---

### Task 4: Validation simulateur kill/restart [USER ACTION]

**Files:** aucun — le contrôleur lance les instances successives ; le propriétaire valide.

- [x] **Step 1 (epix2pro51mm)** : lancer l'app → match en 21 pts, compter 7-3 → menu QUITTER → **relancer l'app** → retour direct **SCORE 7-3** (reprise §5)
- [x] **Step 2** : compter jusqu'à 21-19 (SET_RESULT, sets 1-0) → QUITTER → relancer → **« SET 1 TERMINE », sets 1-0** → UP → **retour SCORE 21-19, sets 0-0** (undo après reprise)
- [x] **Step 3** : finir le match 2-0 → QUITTER → relancer → **MATCH TERMINE 2-1/2-0 affiché** → DOWN → SETUP → relancer → **Setup propre** (match purgé)
- [x] **Step 4** : démarrer un match en 11 pts → QUITTER → relancer → reprise 11 pts ; DOWN sur MATCH_FINISHED d'un autre match → relancer → **Setup présélectionne 11 POINTS** (format mémorisé)
- [x] **Step 5 (fr55 ou instinct2)** : un match en cours → QUITTER → relancer → reprise directe SCORE
- [x] **Step 6** : résultats consignés dans `docs/superpowers/notes/phase-3-sim-results.md` + commit

---

### Task 5: Synthèse + PR

**Files:**
- Create: `docs/superpowers/notes/2026-09-19-phase-3-findings.md`
- Modify: ce plan (coches Tasks 1-4)

- [ ] **Step 1:** Findings : modèle base+tail (interprétation §7.2), purge 200/175, `pf` pour Phase 4a, format Storage plat (risque imbriqué évité), match fini purgé au DOWN, scénario kill/restart.
- [ ] **Step 2:** Commit + `git push -u origin phase-3` + PR `gh pr create --base main`.
- [ ] **Step 3:** superpowers:finishing-a-development-branch après merge propriétaire.

---

## Auto-review (effectuée)

- **Couverture §16 ligne 3** : StorageService ✓ (MatchStore), reprise ✓ (initialize + scénario Task 4), pendingEvents ✓ (décision : `pf` dans meta, file réelle Phase 4a — dérogation documentée), kill/restart sans perte ✓ (scénario), cas persistance verts ✓ (3 tests §15.1 « Persistance »).
- **Couverture §7.2** : clés multiples ≤ 8 Ko ✓ (30 events ≈ 1,5 Ko/lot), écriture à chaque mutation + onStop ✓, restauration sans replay complet ✓ (base + tail ≤ 175), historique borné 200 + purge par lots ✓ (trimEvents), sur ¬perte ✓.
- **Cohérence types** : `restore(base as Array, events as Array)` = base 8 slots ↔ `getBaseState()` ; `saveMatch(engine, presetIndex)` ↔ getters `getMatchId/getLastSequence/getBaseState/getEvents` (tous définis Task 1) ; Dictionary Storage : valeurs = primitives + tableau plat de Numbers uniquement (pas d'imbrication tableau-dans-tableau dans Storage).
- **Tests indépendants du storage résiduel** : `clearMatch()` en tête des tests store.
- **Aucun placeholder** : code complet dans chaque étape.
