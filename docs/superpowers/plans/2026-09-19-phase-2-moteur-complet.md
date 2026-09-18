# Phase 2 — Moteur complet (UNDO + événements) — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal :** Compléter le moteur (UNDO §4.5/D7, métadonnées d'événements §7.1/§8.2) et l'UI (menu inline 4 items §5), couvrir tous les cas §15.1 hors persistance (Phase 3).

**Architecture :** Event-sourcing pur — UNDO = retire le dernier event du journal + replay (journal vide → sans effet ; `MATCH_FINISHED` ne s'annule jamais). Les events deviennent `[type, arg, sequence, timestamp, prevMe, prevOpp]` avec compteur de séquence **monotone** (décision D-2 ci-dessous). UI : `undo()` branché sur UP en SCORE, menu passe de 2 à 4 items.

**Tech Stack :** Monkey C / Connect IQ SDK 9.2.0, tests Run No Evil (simulateur), branch `phase-2` depuis `main`.

**Décisions & dérogations documentées (à reprendre dans les findings Task 6) :**
- **D-2 — Séquence monotone** : après un UNDO, le numéro de séquence n'est **jamais réutilisé** (l'event suivant prend `mLastSequence + 1`). Lecture de §8.2 « sequence croît sans trou depuis 1 » : sans trou **en l'absence d'undo** ; réutiliser un numéro après undo casserait l'idempotence backend `(match_id, sequence)` (un point différent avec le même id serait ignoré → point perdu). Le trou côté journal est volontaire ; la représentation réseau de l'undo (event `TYPE_UNDO` ou réémission) sera tranchée en Phase 4a.
- **TYPE_UNDO** ajouté à l'enum (§7.1) mais **jamais journalisé** en Phase 2 (undo = retrait, §4.5 explicite) — réservé au protocole de sync Phase 4a.
- **Labels menu compacts** (écrans ronds, leçon Phase 1) : `REPRENDRE / FORMAT / RESET / QUITTER` au lieu de « Reprendre / Changer de format / Réinitialiser le match / Quitter ».
- **Footer SCORE inchangé** (pas d'indice « UP=UNDO » : place insuffisante dans la corde des ronds — leçon Phase 1).

**Vocabulaire du plan :** SDK = `$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")` ; clé = `~/keys/developer_key.der` ; verdict de test = ligne `PASSED (passed=N, failed=0, errors=0)` du runner Run No Evil (le code de sortie de monkeydo n'est pas fiable) ; si `Unable to connect to simulator` → ouvrir `$SDK/bin/ConnectIQ.app` puis relancer après ~6 s.

---

### Task 1: UNDO noyau (TDD)

**Files:**
- Modify: `watch/connect-iq/source/engine/ScoreEngine.mc` (ajout `undo()` après `newMatch`)
- Test: `watch/connect-iq/source/tests/EngineTest.mc` (4 tests, section « UNDO » après `test_engine_manual_set_change_tie_not_credited`)

- [x] **Step 1: Créer la branche**

```bash
cd /Users/marcsuarez/Documents/badminton-score
git checkout main -q && git pull -q && git checkout -b phase-2
```

- [x] **Step 2: Écrire les 4 tests (rouge attendu : `undo()` n'existe pas → build échoue)**

Dans `EngineTest.mc`, après `test_engine_manual_set_change_tie_not_credited` (fin de la section transitions, avant la section match_locked... à placer juste après `test_engine_manual_set_change_tie_not_credited`), insérer :

```monkeyc
// ---- ScoreEngine : UNDO (spec §4.5/D7, §15.1) ----

(:test)
function test_engine_undo_simple(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    e.pointMe();
    e.undo();
    Test.assertEqualMessage(0, e.getScoreMe(), "undo simple : retour 0-0");
    Test.assertEqualMessage(0, e.getScoreOpp(), "undo simple : retour 0-0");
    Test.assertEqualMessage(0, e.getPhase(), "undo simple : PLAYING");
    Test.assertEqualMessage(0, e.getEvents().size(), "journal vide apres undo");
    return true;
}

(:test)
function test_engine_undo_multi(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 2, 1);
    Test.assertEqualMessage(2, e.getScoreMe(), "2-1 avant undo");
    e.undo();
    e.undo();
    e.undo();
    Test.assertEqualMessage(0, e.getScoreMe(), "undo x3 : 0-0");
    Test.assertEqualMessage(0, e.getScoreOpp(), "undo x3 : pas de negatif");
    Test.assertEqualMessage(0, e.getEvents().size(), "journal vide");
    return true;
}

(:test)
function test_engine_undo_empty(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    e.undo();   // journal vide : sans effet
    Test.assertEqualMessage(0, e.getScoreMe(), "undo vide : 0-0");
    Test.assertEqualMessage(0, e.getEvents().size(), "undo vide : journal intact");
    Test.assertEqualMessage(1, e.getSetNumber(), "undo vide : set 1");
    return true;
}

(:test)
function test_engine_undo_match_finished_refused(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 21, 0);
    e.changeSet();
    enginePoints(e, 21, 0);
    Test.assertEqualMessage(2, e.getPhase(), "MATCH_FINISHED");
    var count = e.getEvents().size();
    e.undo();   // D7 : MATCH_FINISHED ne s'annule jamais
    Test.assertEqualMessage(count, e.getEvents().size(), "undo refuse sur match fini");
    Test.assertEqualMessage(2, e.getPhase(), "toujours MATCH_FINISHED");
    return true;
}
```

- [x] **Step 3: Vérifier le rouge**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
"$SDK/bin/monkeyc" -d epix2pro51mm -f watch/connect-iq/monkey.jungle \
  -o /tmp/bad-test.prg -y ~/keys/developer_key.der -w -t
```
Attendu : **échec de compilation** (`Unknown Class or Module 'undo'` / cannot find symbol `undo`).

- [x] **Step 4: Implémenter `undo()`** — dans `ScoreEngine.mc`, après `newMatch` :

```monkeyc
    // UNDO (§4.5/D7) : retire le dernier événement du journal (quel qu'il
    // soit) puis rejoue. MATCH_FINISHED ne s'annule jamais (verrou) ;
    // journal vide → sans effet. slice() plutôt que remove() (par valeur).
    function undo() as Void {
        if (mEvents.size() == 0) { return; }
        var last = mEvents[mEvents.size() - 1];
        if (last[0] == ScoreEvent.TYPE_MATCH_FINISHED) { return; }
        mEvents = mEvents.slice(0, mEvents.size() - 1);
        replay();
    }
```

- [x] **Step 5: Vérifier le vert**

```bash
"$SDK/bin/monkeyc" -d epix2pro51mm -f watch/connect-iq/monkey.jungle \
  -o watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg -y ~/keys/developer_key.der -w -t
open "$SDK/bin/ConnectIQ.app" && sleep 6
"$SDK/bin/monkeydo" watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg epix2pro51mm -t
```
Attendu : `PASSED (passed=25, failed=0, errors=0)` (21 + 4).

- [x] **Step 6: Commit**

```bash
git add watch/connect-iq/source/engine/ScoreEngine.mc watch/connect-iq/source/tests/EngineTest.mc
git commit -m "feat(phase2): UNDO moteur — retrait du dernier event + replay, verrou MATCH_FINISHED (§4.5/D7)"
```

---

### Task 2: UNDO des transitions de set (TDD — cas §15.1)

**Files:**
- Test: `watch/connect-iq/source/tests/EngineTest.mc` (2 tests, dans la section UNDO)
- Le moteur ne change pas (l'undo est générique) : ces tests peuvent passer immédiatement — ce sont des tests de conformité §15.1. S'ils échouent, c'est un bug de `replay()`/`undo()` : debugger, ne pas modifier l'implémentation « au cas où ».

- [x] **Step 1: Écrire les 2 tests** (dans la section UNDO de `EngineTest.mc`, après `test_engine_undo_match_finished_refused`) :

```monkeyc
(:test)
function test_engine_undo_set_finished(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 21, 19);          // SET_FINISHED auto (§4.2)
    Test.assertEqualMessage(1, e.getPhase(), "SET_RESULT apres 21-19");
    Test.assertEqualMessage(1, e.getSetsMe(), "sets 1-0");
    e.undo();                          // reprendre le set terminé
    Test.assertEqualMessage(0, e.getPhase(), "set repris : PLAYING");
    Test.assertEqualMessage(21, e.getScoreMe(), "score du set restaure : 21");
    Test.assertEqualMessage(19, e.getScoreOpp(), "score du set restaure : 19");
    Test.assertEqualMessage(0, e.getSetsMe(), "sets recalcules : 0-0");
    Test.assertEqualMessage(40, e.getEvents().size(), "journal : 41 - 1");
    return true;
}

(:test)
function test_engine_undo_set_changed(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 21, 19);
    e.changeSet();                     // SET_CHANGED apres SET_FINISHED
    Test.assertEqualMessage(2, e.getSetNumber(), "set 2");
    e.undo();                          // retour au set précédent
    Test.assertEqualMessage(1, e.getPhase(), "retour : SET_RESULT (fin du set 1 toujours enregistrée)");
    Test.assertEqualMessage(1, e.getSetNumber(), "retour au set 1");
    Test.assertEqualMessage(1, e.getSetsMe(), "sets 1-0");
    Test.assertEqualMessage(21, e.getLastSetScoreMe(), "score du set 1 restaure");
    Test.assertEqualMessage(19, e.getLastSetScoreOpp(), "19");
    return true;
}
```

- [x] **Step 2: Vérifier le vert**

```bash
"$SDK/bin/monkeyc" -d epix2pro51mm -f watch/connect-iq/monkey.jungle \
  -o watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg -y ~/keys/developer_key.der -w -t
open "$SDK/bin/ConnectIQ.app" && sleep 6
"$SDK/bin/monkeydo" watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg epix2pro51mm -t
```
Attendu : `PASSED (passed=27, failed=0, errors=0)`.

- [x] **Step 3: Commit**

```bash
git add watch/connect-iq/source/tests/EngineTest.mc
git commit -m "test(phase2): undo SET_FINISHED (set repris) et SET_CHANGED (retour set précédent) — cas §15.1"
```

---

### Task 3: Métadonnées d'événements (TDD — §7.1/§8.2, décision D-2)

**Files:**
- Modify: `watch/connect-iq/source/engine/ScoreEvent.mc` (constante `TYPE_UNDO`)
- Modify: `watch/connect-iq/source/engine/ScoreEngine.mc` (matchId, séquence, timestamp, prevScore dans `appendEvent` ; signatures `initialize`/`newMatch` ; getters protocole)
- Modify: `watch/connect-iq/source/ui/MatchView.mc` (génération du matchId)
- Test: `watch/connect-iq/source/tests/EngineTest.mc` (3 nouveaux tests + 1 test existant adapté)

**Format du journal (§7.2 : tableaux positionnels compacts) :**
`[type, arg, sequence, timestamp, prevMe, prevOpp]` — `arg` = winner (SET_*) ou 0 ; `timestamp` = `System.getTimer()` (ms, Long) ; `prevMe/prevOpp` = score dérivé **avant** l'application de l'event (append a lieu avant replay). `id` (non stocké) = `matchId + ":" + sequence`.

- [x] **Step 1: Ajouter TYPE_UNDO** — dans `ScoreEvent.mc`, après `TYPE_MATCH_FINISHED` :

```monkeyc
    const TYPE_UNDO = 5;              // réservé protocole sync Phase 4a — jamais journalisé
                                      // (undo = retrait du dernier event, §4.5)
```

- [x] **Step 2: Écrire les 3 tests + adapter le test existant (rouge attendu : signatures absentes → build échoue)**

Dans `EngineTest.mc`, section UNDO, ajouter :

```monkeyc
// ---- ScoreEngine : protocole d'événements (spec §7.1/§8.2, décision D-2) ----

(:test)
function test_engine_events_protocol(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    e.pointMe();
    e.pointOpponent();
    e.pointMe();
    Test.assertEqualMessage(3, e.getEvents().size(), "3 events");
    // id = matchId:sequence, unique (§8.2)
    Test.assertEqualMessage("m1:1", e.getEventId(0), "id 1 = m1:1");
    Test.assertEqualMessage("m1:2", e.getEventId(1), "id 2 = m1:2");
    Test.assertEqualMessage("m1:3", e.getEventId(2), "id 3 = m1:3");
    // sequence sans trou depuis 1 (§8.2)
    Test.assertEqualMessage(1, e.getEvent(0)[2], "seq 1");
    Test.assertEqualMessage(2, e.getEvent(1)[2], "seq 2");
    Test.assertEqualMessage(3, e.getEvent(2)[2], "seq 3");
    // timestamp present (System.getTimer() > 0 en simu)
    Test.assertEqualMessage(true, e.getEvent(0)[3] > 0, "ts > 0");
    // previousScore cohérent : état dérivé avant chaque mutation
    Test.assertEqualMessage(0, e.getEvent(0)[4], "e1 prev me 0");
    Test.assertEqualMessage(0, e.getEvent(0)[5], "e1 prev opp 0");
    Test.assertEqualMessage(1, e.getEvent(1)[4], "e2 prev me 1");
    Test.assertEqualMessage(0, e.getEvent(1)[5], "e2 prev opp 0");
    Test.assertEqualMessage(1, e.getEvent(2)[4], "e3 prev me 1");
    Test.assertEqualMessage(1, e.getEvent(2)[5], "e3 prev opp 1");
    // newScore du dernier event = état courant (2-1)
    Test.assertEqualMessage(2, e.getScoreMe(), "new dernier event : me 2");
    Test.assertEqualMessage(1, e.getScoreOpp(), "new dernier event : opp 1");
    return true;
}

(:test)
function test_engine_events_set_finished_metadata(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    enginePoints(e, 21, 19);
    var n = e.getEvents().size();      // 40 points + SET_FINISHED
    Test.assertEqualMessage(41, n, "41 events");
    var fin = e.getEvent(n - 1);
    Test.assertEqualMessage(ScoreEvent.TYPE_SET_FINISHED, fin[0], "dernier = SET_FINISHED");
    Test.assertEqualMessage(41, fin[2], "seq 41 (les points comptent aussi, §8.2)");
    Test.assertEqualMessage(21, fin[4], "prev me 21");
    Test.assertEqualMessage(19, fin[5], "prev opp 19");
    return true;
}

(:test)
function test_engine_undo_sequence_monotonic(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2), "m1");
    e.pointMe();
    e.undo();
    e.pointMe();
    Test.assertEqualMessage(1, e.getEvents().size(), "1 event apres undo+nouveau");
    Test.assertEqualMessage(2, e.getEvent(0)[2], "sequence jamais reutilisee : 2, pas 1 (D-2)");
    Test.assertEqualMessage("m1:2", e.getEventId(0), "id m1:2");
    return true;
}
```

Adapter le test existant `test_engine_new_match_reset` (ligne `e.newMatch(MatchPresets.get(0));`) :

```monkeyc
    e.newMatch(MatchPresets.get(0), "m2");   // nouveau match en 11 pts, nouvel id
    Test.assertEqualMessage(0, e.getScoreMe(), "reset 0-0");
    Test.assertEqualMessage(1, e.getSetNumber(), "reset set 1");
    Test.assertEqualMessage(0, e.getPhase(), "reset PLAYING");
    Test.assertEqualMessage(0, e.getEvents().size(), "journal vide");
    Test.assertEqualMessage(11, e.getConfig().mTargetScore, "nouvelle config 11 pts");
```

Et l'initialisation de `test_engine_initial_state` reste sans matchId ? NON — toutes les constructions passent un matchId : remplacer dans **tous** les tests existants `new ScoreEngine(MatchPresets.get(...))` par `new ScoreEngine(MatchPresets.get(...), "m1")` (9 occurrences : initial_state, points_and_replay, deuce_21, cap_21, set_finished_normal, set_finished_opponent, deuce_15, cap_15, deuce_11, no_cap_11, match_finished_2_sets, manual_set_change_finishes_match, set_result_transition, manual_set_change_leader_credited, manual_set_change_tie_not_credited, match_locked, new_match_reset, undo_simple, undo_multi, undo_empty, undo_match_finished_refused, undo_set_finished, undo_set_changed — tout avec `"m1"`, sauf `new_match_reset` qui utilise `"m2"` en `newMatch`).

- [x] **Step 3: Vérifier le rouge**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
"$SDK/bin/monkeyc" -d epix2pro51mm -f watch/connect-iq/monkey.jungle \
  -o /tmp/bad-test.prg -y ~/keys/developer_key.der -w -t
```
Attendu : échec (constructeur `ScoreEngine(config, matchId)` inconnu / `getEventId` inconnu).

- [x] **Step 4: Implémenter le moteur** — dans `ScoreEngine.mc` :

En tête : `import Toybox.System;` (le moteur reste PUR : pas de Graphics/WatchUi — System est autorisé, §6.2).

Champs (après `mLastSetScoreOpp`) :

```monkeyc
    var mMatchId;       // id du match — préfixe des ids d'événements (§7.1)
    var mLastSequence;  // compteur monotone : jamais réutilisé, même après undo (D-2)
```

`initialize` / `newMatch` (signatures) :

```monkeyc
    function initialize(config, matchId) {
        mConfig = config;
        mMatchId = matchId;
        mEvents = [];
        mLastSequence = 0;
        replay();
    }
```

```monkeyc
    // Nouveau match (menu Réinitialiser/Changer de format ou DOWN sur MATCH_FINISHED).
    // Nouveau matchId : nouvelle espace de séquences.
    function newMatch(config, matchId) as Void {
        mConfig = config;
        mMatchId = matchId;
        mEvents = [];
        mLastSequence = 0;
        replay();
    }
```

**`replay()` ne touche PAS `mLastSequence`** (le compteur appartient au journal, l'undo appelle replay sans le réinitialiser).

`appendEvent` (remplacer l'existant) :

```monkeyc
    // Journal positionnel compact (§7.2) : [type, arg, seq, ts, prevMe, prevOpp].
    // prev = état dérivé AVANT l'event (append précède replay).
    function appendEvent(e) as Void {
        var arg = e.size() > 1 ? e[1] : 0;
        mLastSequence += 1;
        mEvents.add([e[0], arg, mLastSequence, System.getTimer(), mScoreMe, mScoreOpp]);
        replay();
    }
```

Getters protocole (à la fin, après `getEvents`) :

```monkeyc
    // ---- protocole (§7.1/§8.2) ----
    function getEvent(i as Number) as Array { return mEvents[i]; }
    function getEventId(i as Number) as String { return mMatchId + ":" + mEvents[i][2]; }
```

- [x] **Step 5: Adapter MatchView** — champ + génération d'id :

Après `var mEngine = null;` :

```monkeyc
    var mMatchId = "";        // id du match courant (protocole §7.1)
```

Nouvelle méthode (après `startMatch`) :

```monkeyc
    // Id de match : ms depuis le boot — suffit en local ; le backend
    // l'espacera du deviceId en Phase 4a (§8.2 : id = matchId:sequence).
    function genMatchId() as String {
        return System.getTimer().toString();
    }
```

`startMatch` (remplacer) :

```monkeyc
    function startMatch() as Void {
        mMatchId = genMatchId();
        mEngine = new ScoreEngine(MatchPresets.get(mSetupIndex), mMatchId);
        mScreen = MatchScreen.SCORE;
        WatchUi.requestUpdate();
    }
```

- [x] **Step 6: Vérifier le vert**

```bash
"$SDK/bin/monkeyc" -d epix2pro51mm -f watch/connect-iq/monkey.jungle \
  -o watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg -y ~/keys/developer_key.der -w -t
open "$SDK/bin/ConnectIQ.app" && sleep 6
"$SDK/bin/monkeydo" watch/connect-iq/bin/badmintonscore-epix2pro51mm-test.prg epix2pro51mm -t
```
Attendu : `PASSED (passed=30, failed=0, errors=0)`.

- [x] **Step 7: Commit**

```bash
git add watch/connect-iq/source/engine/ScoreEvent.mc watch/connect-iq/source/engine/ScoreEngine.mc \
        watch/connect-iq/source/ui/MatchView.mc watch/connect-iq/source/tests/EngineTest.mc
git commit -m "feat(phase2): métadonnées d'événements — matchId, séquence monotone (D-2), timestamp, prevScore (§7.1/§8.2)"
```

---

### Task 4: UI — UNDO sur UP + menu inline 4 items (§5)

**Files:**
- Modify: `watch/connect-iq/source/ui/MatchView.mc` (onUp, onDown MENU, menuSelect, drawMenu)

Pas de test Run No Evil (UI) — validation simu Task 5. Build × 5 + tests verts exigés.

- [x] **Step 1: UP = UNDO en SCORE** — dans `onUp`, remplacer la ligne commentée « UNDO = Phase 2 » :

```monkeyc
        if (mScreen == MatchScreen.SCORE) {
            mEngine.undo();              // UP = UNDO (§3.2/D7)
            syncScreen();                // peut revenir à SET_RESULT (undo SET_CHANGED)
            return true;
        }
        return true;
```

(la fin de la fonction garde `return true;` pour les autres écrans)

- [x] **Step 2: Navigation menu 4 items** — dans `onUp` (branche MENU) remplacer `% 2` :

```monkeyc
        if (mScreen == MatchScreen.MENU) {
            mMenuIndex = (mMenuIndex + 3) % 4;   // UP : recule dans la liste de 4
            WatchUi.requestUpdate();
            return true;
        }
```

Dans `onDown` (branche MENU) :

```monkeyc
        if (mScreen == MatchScreen.MENU) {
            mMenuIndex = (mMenuIndex + 1) % 4;
            WatchUi.requestUpdate();
            return true;
        }
```

- [x] **Step 3: menuSelect 4 branches** — remplacer la fonction (sortie unique : `System.exit()` en dernier — leçon Phase 1, « unreachable » sinon) :

```monkeyc
    // Menu inline §5 : Reprendre / Changer de format / Réinitialiser / Quitter.
    // (Labels compacts « FORMAT »/« RESET » : écrans ronds, leçon Phase 1.)
    function menuSelect() as Boolean {
        if (mMenuIndex == 0) {
            mScreen = MatchScreen.SCORE;      // Reprendre
            WatchUi.requestUpdate();
        } else if (mMenuIndex == 1) {
            mScreen = MatchScreen.SETUP;      // Changer de format (START = nouveau match)
            WatchUi.requestUpdate();
        } else if (mMenuIndex == 2) {
            mEngine.newMatch(mEngine.getConfig(), genMatchId());   // Réinitialiser
            mScreen = MatchScreen.SCORE;
            WatchUi.requestUpdate();
        } else {
            System.exit();                    // Quitter — dernier bloc, rien après
        }
        return true;
    }
```

- [x] **Step 4: drawMenu 4 items, centrage adaptatif** (leçon Phase 1 : items entre le titre et le bas de l'écran, compression si l'espace manque — fr55) — remplacer :

```monkeyc
    function drawMenu(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fMedium = dc.getFontHeight(Graphics.FONT_MEDIUM);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "MENU", Graphics.TEXT_JUSTIFY_CENTER);
        var items = ["REPRENDRE", "FORMAT", "RESET", "QUITTER"];
        var titleBottom = h / 8 + fSmall;
        var zone = h - titleBottom;                 // pas de footer sur le menu
        var spacing = 5 * fMedium / 4;
        if (spacing * 3 + fMedium > zone) {
            spacing = (zone - fMedium) / 3;         // compression (fr55)
        }
        var y = titleBottom + (zone - (spacing * 3 + fMedium)) / 2;
        for (var i = 0; i < items.size(); i += 1) {
            var marker = (i == mMenuIndex) ? "> " : "  ";
            dc.drawText(w / 2, y, Graphics.FONT_MEDIUM, marker + items[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += spacing;
        }
    }
```

Vérification métriques attendue : epix items 124/197/270/343 (bas 402 ≤ 454) ; instinct2 48/81/114/147 (bas 174 ≤ 176) ; fr55 compressé spacing 40, items ~53/93/133/173 (bas 207 ≤ 208).

- [x] **Step 5: Build × 5 + tests verts**

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
Attendu : 5 builds OK, `PASSED (passed=30, failed=0, errors=0)`.

- [x] **Step 6: Commit**

```bash
git add watch/connect-iq/source/ui/MatchView.mc
git commit -m "feat(phase2): UP=UNDO en SCORE + menu inline 4 items (Reprendre/Format/Reset/Quitter) §5"
```

---

### Task 5: Validation simulateur [USER ACTION]

**Files:** aucun — le contrôleur lance le simu et fournit le scénario ; le propriétaire valide.

- [x] **Step 1:** Relancer le simulateur epix2pro51mm (release build Task 4). Scénario :
  1. Match en 21 pts : compter 3 points → UP×3 → retour 0-0 **sans négatif**
  2. Compter jusqu'à 21-19 (SET_RESULT, sets 1-0) → UP → **retour en SCORE à 21-19, sets 0-0** (set repris)
  3. Recompter 21-19 → DOWN (set 2) → UP → **retour à SET_RESULT « SET 1 TERMINE », sets 1-0**
  4. DOWN → set 2 → finir le match 2-0 → UP → **inopérant** (verrou)
  5. Menu UP-long : **4 items** (REPRENDRE/FORMAT/RESET/QUITTER), UP et DOWN naviguent, BACK ferme
  6. FORMAT → écran Setup → START → **nouveau match** (format choisi)
  7. Menu → RESET → score **0-0 set 1** immédiat
  8. Menu → QUITTER → l'app se ferme
- [x] **Step 2:** Vérif rapide instinct2 (menu 4 items sans débordement + undo simple).
- [x] **Step 3:** Résultats consignés dans `docs/superpowers/notes/phase-2-sim-results.md` + commit `docs(phase2): résultats simulateur undo + menu`.

---

### Task 6: Synthèse + PR

**Files:**
- Create: `docs/superpowers/notes/2026-09-19-phase-2-findings.md`
- Modify: ce plan (coches Tasks 1-5)

- [ ] **Step 1:** Findings : décisions D-2 (séquence monotone, question ouverte protocole undo Phase 4a), TYPE_UNDO réservé, labels menu compacts, métriques menu × 3 devices ; points d'entrée Phase 3 (persistance §7.2 : journal positionnel compatible, prevScore/seq/ts déjà portés par les events).
- [ ] **Step 2:** Commit + `git push -u origin phase-2` + PR `gh pr create --base main` (résumé : undo, menu, événements, 30 tests).
- [ ] **Step 3:** superpowers:finishing-a-development-branch après merge propriétaire.

---

## Auto-review (effectuée)

- **Couverture §15.1 (hors persistance = Phase 3)** : undo simple/multi/vide (Task 1), undo SET_FINISHED/SET_CHANGED (Task 2), fin de match UNDO inopérant (Task 1), événements id/séquence/prev-new (Task 3). Score initial/points/déuce/caps/set/transitions : déjà couverts Phase 1 (21 tests conservés).
- **Couverture §16 ligne 2** : undo ✓ (Tasks 1-2, 4), événements ✓ (Task 3), menu/UX §5 ✓ (Task 4), suite verte ✓ (30 tests).
- **Cohérence types** : `undo()`/`getEvent(i)`/`getEventId(i)`/`genMatchId()` ; `newMatch(config, matchId)` mis à jour partout (test `new_match_reset` adapté, MatchView RESET) ; event 6 slots `[type, arg, seq, ts, prevMe, prevOpp]` cohérent avec `applyEvent` (indices 0/1 inchangés).
- **Aucun placeholder** : code complet dans chaque étape.
