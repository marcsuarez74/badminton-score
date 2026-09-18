# Phase 1 — Scoring minimal (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App montre « badminton-score » minimaliste mais jouable : moteur de score event-sourcing complet (règles §4.2 intégrales), mapping boutons §3.2, affichage mono-écran sur les 3 profils simu — critère de sortie : un match complet compté aux boutons sur epix Pro (simu + matériel).

**Architecture:** Nouveau projet `watch/connect-iq/` (§6 de la spec, structure Phase 1 réduite). Moteur PUR (`source/engine/`, zéro import Graphics/WatchUi) testable Run No Evil ; UI (`source/ui/`) observe le moteur et redessine. Event-sourcing dès le départ : l'état est le replay du journal d'événements positionnels — la Phase 2 (undo) et la Phase 3 (persistance) s'y grefferont sans refonte.

**Tech Stack:** Monkey C, Connect IQ SDK 9.2.0 (`monkeyc`, `monkeydo`), Run No Evil (`-t`), clé `~/keys/developer_key.der`, openMTP pour le sideload.

**Périmètre Phase 1 (validé avec le propriétaire, selon §16) :**
- ✅ Règles de fin de set **complètes** (§4.2 : déuce, winBy, cap, 11 pts sans plafond)
- ✅ Setup avec les **3 formats** (11/15/21), mémorisé en mémoire d'écran
- ✅ Menu inline (UP-long) **minimal** : Reprendre + Quitter
- ❌ UNDO (UP = sans effet) → Phase 2 · ❌ Persistance → Phase 3 · ❌ Sync, tactile, couleurs → Phases 4+

**Décisions d'implémentation (dérogations ou précisions assumées) :**
- Tests Run No Evil sous `source/tests/` (une seule `sourcePath`, convention validée en Phase 0) — le §6 les met à la racine ; regroupés en Phase 2 si besoin.
- `Theme.mc`, `SetupView.mc`, `services/` : pas créés en Phase 1 (mono-écran §5, N&B partout). Le Setup est un état de `MatchView`.
- Pas de permission `Communications` dans le manifest (à ajouter en Phase 4a).
- Textes UI en majuscules **sans accents** (fiabilité de rendu MIP 2 couleurs).
- Un set fermé manuellement (SET_CHANGED) crédite le **leader strict** ; en cas d'égalité, personne (détail non spécifié §4.4, à confirmer en Phase 2 si besoin).
- App id distinct du prototype : `59EEABC33F1813AE142E338E63007E53` (l'app s'installera **à côté** de ButtonTest, pas à la place).
- `App.mc` stub dès la Task 1 : monkeyc **exige** la classe d'entry point du manifest dès le premier build (empiriquement vérifié : sinon `Cannot find entry point class '$.BadmintonApp'` sur tous les builds) — remplacé par la vraie app en Task 5.
- **Sémantique Monkey C `import` vs `using`** (découverte Task 1) : `using Toybox.Graphics` ne résout PAS `Dc` dans une annotation `dc as Dc` — il faut `import Toybox.Graphics`. Symptôme : `Cannot resolve type 'Dc'`. À appliquer dans tout fichier annotant `Dc` (Task 5).

**Git :** branche `phase-1` depuis `main` (dérogation worktree identique à la Phase 0 : repo mono-dev, aucun travail parallèle). Créer la branche en début d'exécution.

**Marquage :** les tâches `[USER ACTION]` exigent la souris du simulateur ou la montre. L'agent prépare tout et s'arrête avec des instructions précises.

---

## File Structure

```
watch/connect-iq/
├── manifest.xml                  # watch-app, 5 products, SANS permission, id 59EEABC3...
├── monkey.jungle                 # manifest + sourcePath=source + resourcePath=resources
├── resources/
│   ├── strings/strings.xml       # AppName = "Badminton"
│   └── drawables/
│       ├── drawables.xml         # LauncherIcon
│       └── launcher_icon.png     # copié du prototype (36x36, warning scale non bloquant)
├── source/
│   ├── App.mc                    # BadmintonApp : getInitialView (rien d'autre en Phase 1)
│   ├── engine/                   # PUR — AUCUN import Toybox.Graphics / WatchUi
│   │   ├── MatchConfig.mc        # class MatchConfig + module MatchPresets (11/15/21)
│   │   ├── ScoreEvent.mc         # codes d'événements (const)
│   │   ├── Rules.mc              # isSetOver (formule §4.2)
│   │   └── ScoreEngine.mc        # journal + replay + mutations
│   ├── ui/
│   │   ├── MatchView.mc          # 6 écrans : SETUP/SCORE/CONFIRM_SET/SET_RESULT/MATCH_FINISHED/MENU
│   │   └── MatchDelegate.mc      # BehaviorDelegate → délègue tout à la vue
│   └── tests/
│       └── EngineTest.mc         # Run No Evil : sous-ensemble §15.1 (sans undo/persistance)
└── bin/                          # .prg (gitignoré globalement)
```

Responsabilités : `ScoreEngine` = seule source de vérité (l'UI ne fait que lire) ; `Rules` = formule de fin de set isolée ; `MatchView` = état d'écran + rendu ; `MatchDelegate` = traduction boutons → vue. Le moteur ne connaît ni Graphics ni WatchUi (§6.2).

**Journal d'événements (tableaux positionnels, préfiguration §7.2) :**

| Type | Code | Args | Sémantique |
|---|---|---|---|
| POINT_ME | 0 | — | point pour moi |
| POINT_OPPONENT | 1 | — | point pour l'adversaire |
| SET_FINISHED | 2 | `[winner]` (0/1) | fin auto (règles §4.2), set crédité au vainqueur |
| SET_CHANGED | 3 | `[winner]` (0/1/-1) | transition « set suivant » ; -1 = set déjà crédité par SET_FINISHED ou égalité |
| MATCH_FINISHED | 4 | — | verrou terminal (le futur UNDO le refusera, §4.5) |

Phases dérivées : 0=PLAYING, 1=SET_RESULT (set fini, en attente « set suivant »), 2=MATCH_FINISHED.

---

### Task 1: Squelette du projet `watch/connect-iq/`

**Files:**
- Create: `watch/connect-iq/manifest.xml`
- Create: `watch/connect-iq/monkey.jungle`
- Create: `watch/connect-iq/resources/strings/strings.xml`
- Create: `watch/connect-iq/resources/drawables/drawables.xml`
- Create: `watch/connect-iq/resources/drawables/launcher_icon.png` (copié du prototype)

- [ ] **Step 1: Créer la branche et l'arborescence**

```bash
git checkout -b phase-1
mkdir -p watch/connect-iq/source/engine watch/connect-iq/source/ui watch/connect-iq/source/tests watch/connect-iq/resources/strings watch/connect-iq/resources/drawables watch/connect-iq/bin
cp prototypes/button-test/resources/drawables/launcher_icon.png watch/connect-iq/resources/drawables/
```

- [ ] **Step 2: Écrire `watch/connect-iq/manifest.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<iq:manifest xmlns:iq="http://www.garmin.com/xml/connectiq" version="3">
    <iq:application id="59EEABC33F1813AE142E338E63007E53" version="0.1.0" minSdkVersion="3.4.0" minApiLevel="3.4.0" entry="BadmintonApp" type="watch-app" name="@Strings.AppName" launcherIcon="@Drawables.LauncherIcon">
        <iq:products>
            <iq:product id="epix2pro42mm"/>
            <iq:product id="epix2pro47mm"/>
            <iq:product id="epix2pro51mm"/>
            <iq:product id="fr55"/>
            <iq:product id="instinct2"/>
        </iq:products>
        <iq:permissions/>
        <iq:languages>
            <iq:language>eng</iq:language>
        </iq:languages>
    </iq:application>
</iq:manifest>
```

- [ ] **Step 3: Écrire `watch/connect-iq/monkey.jungle`**

```
project.manifest = manifest.xml
base.sourcePath = source
base.resourcePath = resources
```

- [ ] **Step 4: Écrire `watch/connect-iq/resources/strings/strings.xml`**

```xml
<strings>
    <string id="AppName">Badminton</string>
</strings>
```

- [ ] **Step 5: Écrire `watch/connect-iq/resources/drawables/drawables.xml`**

```xml
<drawables>
    <bitmap id="LauncherIcon" filename="launcher_icon.png"/>
</drawables>
```

- [ ] **Step 6: Commit**

```bash
git add watch/connect-iq
git commit -m "feat(phase1): squelette watch/connect-iq (manifest 5 devices sans permission, jungle, ressources)"
```

---

### Task 2: MatchConfig + Rules.isSetOver (TDD Run No Evil)

**Files:**
- Create: `watch/connect-iq/source/engine/MatchConfig.mc`
- Create: `watch/connect-iq/source/engine/Rules.mc`
- Create: `watch/connect-iq/source/tests/EngineTest.mc`

- [ ] **Step 1: Écrire les tests (rouge — les symboles n'existent pas encore)**

`watch/connect-iq/source/tests/EngineTest.mc` :

```monkeyc
import Toybox.Lang;
import Toybox.Test;

// ---- MatchConfig / presets ----

(:test)
function test_presets_values(logger as Logger) as Boolean {
    var c11 = MatchPresets.get(0);
    Test.assertEqualMessage(11, c11.mTargetScore, "11 pts target");
    Test.assertEqualMessage(0, c11.mCap, "11 pts sans plafond");
    var c15 = MatchPresets.get(1);
    Test.assertEqualMessage(15, c15.mTargetScore, "15 pts target");
    Test.assertEqualMessage(21, c15.mCap, "15 pts cap 21");
    var c21 = MatchPresets.get(2);
    Test.assertEqualMessage(21, c21.mTargetScore, "21 pts target");
    Test.assertEqualMessage(30, c21.mCap, "21 pts cap 30");
    Test.assertEqualMessage(3, MatchPresets.count(), "3 presets");
    Test.assertEqualMessage(2, c21.mWinBy, "winBy 2");
    Test.assertEqualMessage(2, c21.mSetsToWin, "setsToWin 2");
    return true;
}

// ---- Rules.isSetOver (spec §4.2) ----

(:test)
function test_rules_21_points(logger as Logger) as Boolean {
    var c = MatchPresets.get(2);
    Test.assertEqualMessage(false, Rules.isSetOver(c, 20, 19), "20-19 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 20, 20), "20-20 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 21, 20), "21-20 non fini (deuce)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 21, 19), "21-19 fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 29, 29), "29-29 non fini");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 30, 29), "30-29 fini (cap)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 19, 21), "19-21 fini (adversaire)");
    return true;
}

(:test)
function test_rules_15_points(logger as Logger) as Boolean {
    var c = MatchPresets.get(1);
    Test.assertEqualMessage(false, Rules.isSetOver(c, 14, 14), "14-14 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 15, 14), "15-14 non fini (deuce)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 15, 13), "15-13 fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 20, 20), "20-20 non fini");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 21, 20), "21-20 fini (cap 21)");
    return true;
}

(:test)
function test_rules_11_points(logger as Logger) as Boolean {
    var c = MatchPresets.get(0);
    Test.assertEqualMessage(false, Rules.isSetOver(c, 10, 10), "10-10 non fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 11, 10), "11-10 non fini (deuce)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 11, 9), "11-9 fini");
    Test.assertEqualMessage(false, Rules.isSetOver(c, 15, 14), "15-14 non fini (sans cap)");
    Test.assertEqualMessage(true, Rules.isSetOver(c, 16, 14), "16-14 fini (sans cap, ecart 2)");
    return true;
}
```

- [ ] **Step 2: Vérifier que le build des tests échoue (rouge)**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
cd watch/connect-iq
"$SDK/bin/monkeyc" -d fr55 -f monkey.jungle -o bin/tests-fr55.prg -y ~/keys/developer_key.der -t -w
```

Attendu : **échec de compilation** (`Cannot resolve symbol 'MatchPresets'` / `'Rules'`). Si le build passe : mauvaise étape, les symboles existent déjà.

- [ ] **Step 3: Écrire `source/engine/MatchConfig.mc`**

```monkeyc
import Toybox.Lang;

// Paramétrage complet d'un match (spec §4.1 — aucun chiffre codé en dur ailleurs).
class MatchConfig {
    var mTargetScore;   // points pour gagner un set (si écart suffisant)
    var mWinBy;         // écart minimal requis en fin de set
    var mCap;           // plafond optionnel (0 = sans plafond)
    var mSetsToWin;     // sets gagnants pour le match (best-of-3 => 2)

    function initialize(targetScore, winBy, cap, setsToWin) {
        mTargetScore = targetScore;
        mWinBy = winBy;
        mCap = cap;
        mSetsToWin = setsToWin;
    }
}

// Presets §4.1 : 11 pts (sans plafond), 15 pts (cap 21), 21 pts (cap 30).
module MatchPresets {
    function count() as Number {
        return 3;
    }

    // Index 0 = 11 pts, 1 = 15 pts, 2 = 21 pts (ordre du Setup : UP/DOWN naviguent).
    function get(index as Number) as MatchConfig {
        if (index == 0) { return new MatchConfig(11, 2, 0, 2); }
        if (index == 1) { return new MatchConfig(15, 2, 21, 2); }
        return new MatchConfig(21, 2, 30, 2);
    }

    function label(index as Number) as String {
        if (index == 0) { return "11 POINTS"; }
        if (index == 1) { return "15 POINTS"; }
        return "21 POINTS";
    }
}
```

- [ ] **Step 4: Écrire `source/engine/Rules.mc`**

```monkeyc
import Toybox.Lang;

// Formule de fin de set (spec §4.2) — isolée du moteur pour être testée isolément.
module Rules {

    // Le set est gagné dès que le leader a >= targetScore ET
    // (écart >= winBy OU (cap > 0 ET leader >= cap)).
    function isSetOver(config as MatchConfig, scoreMe as Number, scoreOpp as Number) as Boolean {
        var high = (scoreMe >= scoreOpp) ? scoreMe : scoreOpp;
        var low = (scoreMe >= scoreOpp) ? scoreOpp : scoreMe;
        if (high < config.mTargetScore) { return false; }
        if (high - low >= config.mWinBy) { return true; }
        if (config.mCap > 0 && high >= config.mCap) { return true; }
        return false;
    }
}
```

- [ ] **Step 5: Vérifier que le build des tests passe (vert) puis l'exécuter en simulateur**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
cd watch/connect-iq
"$SDK/bin/monkeyc" -d fr55 -f monkey.jungle -o bin/tests-fr55.prg -y ~/keys/developer_key.der -t -w \
  && echo "BUILD OK"
"$SDK/bin/monkeydo" bin/tests-fr55.prg fr55 -t
```

Attendu : `BUILD OK` puis dans la console simulateur : les 4 tests `PASSED` (`test_presets_values`, `test_rules_21_points`, `test_rules_15_points`, `test_rules_11_points`), aucun `FAILED`. Fermer le simulateur.

- [ ] **Step 6: Idem sur instinct2 et epix2pro51mm**

```bash
"$SDK/bin/monkeyc" -d instinct2 -f monkey.jungle -o bin/tests-instinct2.prg -y ~/keys/developer_key.der -t -w && "$SDK/bin/monkeydo" bin/tests-instinct2.prg instinct2 -t
"$SDK/bin/monkeyc" -d epix2pro51mm -f monkey.jungle -o bin/tests-epix2pro51mm.prg -y ~/keys/developer_key.der -t -w && "$SDK/bin/monkeydo" bin/tests-epix2pro51mm.prg epix2pro51mm -t
```

Attendu : 4 `PASSED` sur chaque profil (le moteur ne dépend pas du device).

- [ ] **Step 7: Commit**

```bash
git add watch/connect-iq/source/engine/MatchConfig.mc watch/connect-iq/source/engine/Rules.mc watch/connect-iq/source/tests/EngineTest.mc
git commit -m "feat(phase1): MatchConfig + presets 11/15/21 et Rules.isSetOver (formule §4.2) — TDD Run No Evil"
```

---

### Task 3: ScoreEngine — points, replay, fin de set auto (TDD)

**Files:**
- Create: `watch/connect-iq/source/engine/ScoreEvent.mc`
- Create: `watch/connect-iq/source/engine/ScoreEngine.mc`
- Modify: `watch/connect-iq/source/tests/EngineTest.mc` (ajout des tests moteur)

- [ ] **Step 1: Ajouter les tests moteur (rouge)**

Ajouter en fin de `source/tests/EngineTest.mc` :

```monkeyc
// ---- ScoreEngine : points + replay + fin de set auto (spec §4.2/§4.3, §15.1) ----

// Compte n points par côté en alternant (helper de test — l'alternance évite
// de déclencher SET_FINISHED prématurément, ex. 11-0 sur le preset 21).
// NB : `me` est un mot réservé Monkey C — premier paramètre nommé nMe.
function enginePoints(e as ScoreEngine, nMe as Number, opp as Number) as Void {
    var i = 0;
    var j = 0;
    while (i < nMe || j < opp) {
        if (i < nMe) { e.pointMe(); i += 1; }
        if (j < opp) { e.pointOpponent(); j += 1; }
    }
}

(:test)
function test_engine_initial_state(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    Test.assertEqualMessage(0, e.getScoreMe(), "score me 0-0");
    Test.assertEqualMessage(0, e.getScoreOpp(), "score opp 0-0");
    Test.assertEqualMessage(1, e.getSetNumber(), "set 1");
    Test.assertEqualMessage(0, e.getSetsMe(), "sets me 0");
    Test.assertEqualMessage(0, e.getSetsOpp(), "sets opp 0");
    Test.assertEqualMessage(0, e.getPhase(), "phase PLAYING");
    return true;
}

(:test)
function test_engine_points_and_replay(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    e.pointMe();
    Test.assertEqualMessage(1, e.getScoreMe(), "1-0 apres POINT_ME");
    e.pointOpponent();
    e.pointOpponent();
    Test.assertEqualMessage(1, e.getScoreMe(), "score me 1");
    Test.assertEqualMessage(2, e.getScoreOpp(), "1-2 apres 2 POINT_OPPONENT");
    Test.assertEqualMessage(3, e.getEvents().size(), "journal = 3 events");
    Test.assertEqualMessage(0, e.getPhase(), "toujours PLAYING");
    return true;
}

(:test)
function test_engine_deuce_21(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 20, 20);
    Test.assertEqualMessage(0, e.getPhase(), "20-20 pas fini");
    e.pointMe();
    Test.assertEqualMessage(21, e.getScoreMe(), "21-20");
    Test.assertEqualMessage(0, e.getPhase(), "21-20 : set NON fini (deuce)");
    return true;
}

(:test)
function test_engine_cap_21(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 29, 29);
    e.pointMe();
    Test.assertEqualMessage(30, e.getScoreMe(), "30-29");
    Test.assertEqualMessage(1, e.getPhase(), "cap atteint -> SET_RESULT");
    Test.assertEqualMessage(1, e.getSetsMe(), "sets 1-0");
    return true;
}

(:test)
function test_engine_set_finished_normal(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 21, 19);
    Test.assertEqualMessage(1, e.getPhase(), "21-19 -> SET_RESULT");
    Test.assertEqualMessage(1, e.getSetsMe(), "sets 1-0");
    Test.assertEqualMessage(21, e.getLastSetScoreMe(), "dernier set 21");
    Test.assertEqualMessage(19, e.getLastSetScoreOpp(), "dernier set 19");
    Test.assertEqualMessage(1, e.getSetNumber(), "setNumber toujours 1 tant que pas de transition");
    return true;
}

(:test)
function test_engine_set_finished_opponent(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 19, 21);
    Test.assertEqualMessage(1, e.getPhase(), "19-21 -> SET_RESULT");
    Test.assertEqualMessage(1, e.getSetsOpp(), "sets 0-1");
    return true;
}

(:test)
function test_engine_deuce_15(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(1));
    enginePoints(e, 14, 14);
    e.pointMe();
    Test.assertEqualMessage(15, e.getScoreMe(), "15-14");
    Test.assertEqualMessage(0, e.getPhase(), "15-14 : set NON fini");
    return true;
}

(:test)
function test_engine_cap_15(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(1));
    enginePoints(e, 20, 20);
    e.pointMe();
    Test.assertEqualMessage(21, e.getScoreMe(), "21-20");
    Test.assertEqualMessage(1, e.getPhase(), "cap 21 -> SET_RESULT");
    return true;
}

(:test)
function test_engine_deuce_11(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(0));
    enginePoints(e, 10, 10);
    e.pointMe();
    Test.assertEqualMessage(11, e.getScoreMe(), "11-10");
    Test.assertEqualMessage(0, e.getPhase(), "11-10 : set NON fini");
    return true;
}

(:test)
function test_engine_no_cap_11(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(0));
    enginePoints(e, 15, 14);
    Test.assertEqualMessage(0, e.getPhase(), "15-14 non fini (sans plafond)");
    e.pointMe();
    Test.assertEqualMessage(16, e.getScoreMe(), "16-14");
    Test.assertEqualMessage(1, e.getPhase(), "16-14 fini (ecart 2, sans plafond)");
    return true;
}

(:test)
function test_engine_match_finished_2_sets(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 21, 0);
    e.changeSet();
    enginePoints(e, 21, 0);
    Test.assertEqualMessage(2, e.getSetsMe(), "sets 2-0");
    Test.assertEqualMessage(2, e.getPhase(), "MATCH_FINISHED");
    Test.assertEqualMessage(46, e.getEvents().size(),
        "journal: 42 points + 2 SET_FINISHED + 1 SET_CHANGED + 1 MATCH_FINISHED");
    e.pointMe();   // sans effet : match verrouillé (§4.5)
    Test.assertEqualMessage(46, e.getEvents().size(), "point ignore apres MATCH_FINISHED");
    Test.assertEqualMessage(21, e.getScoreMe(), "scores du dernier set figes 21-0");
    return true;
}

(:test)
function test_engine_manual_set_change_finishes_match(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 21, 0);
    e.changeSet();                    // set 2
    enginePoints(e, 15, 2);
    e.changeSet();                    // changement manuel : leader crédité -> 2-0
    Test.assertEqualMessage(2, e.getSetsMe(), "sets 2-0 via SET_CHANGED manuel");
    Test.assertEqualMessage(2, e.getPhase(), "MATCH_FINISHED (spec §4.3)");
    Test.assertEqualMessage(42, e.getEvents().size(),
        "journal: 38 points + 1 SET_FINISHED + 2 SET_CHANGED + 1 MATCH_FINISHED");
    e.changeSet();
    Test.assertEqualMessage(42, e.getEvents().size(), "verrou : plus de mutation");
    return true;
}
```

- [ ] **Step 2: Vérifier que le build des tests échoue (rouge)**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
cd watch/connect-iq
"$SDK/bin/monkeyc" -d fr55 -f monkey.jungle -o bin/tests-fr55.prg -y ~/keys/developer_key.der -t -w
```

Attendu : échec (`Cannot resolve symbol 'ScoreEngine'`).

- [ ] **Step 3: Écrire `source/engine/ScoreEvent.mc`**

```monkeyc
// Codes des événements du journal (tableaux positionnels, préfiguration spec §7.2).
// [typeCode] ou [typeCode, arg] — la séquence est implicite (index dans le journal).
module ScoreEvent {
    const TYPE_POINT_ME = 0;
    const TYPE_POINT_OPPONENT = 1;
    const TYPE_SET_FINISHED = 2;      // [TYPE_SET_FINISHED, winner] winner: 0=moi 1=adversaire
    const TYPE_SET_CHANGED = 3;       // [TYPE_SET_CHANGED, winner] winner: 0/1 crédité, -1 = déjà crédité ou égalité
    const TYPE_MATCH_FINISHED = 4;    // verrou terminal (§4.5 : ne s'annule pas)
}

// Phases dérivées exposées par le moteur.
module ScorePhase {
    const PLAYING = 0;        // set en cours, points comptables
    const SET_RESULT = 1;     // set terminé (auto), en attente « set suivant »
    const MATCH_FINISHED = 2; // match terminé, verrouillé
}
```

- [ ] **Step 4: Écrire `source/engine/ScoreEngine.mc`**

```monkeyc
import Toybox.Lang;

// Moteur de score PUR (aucun import Graphics/WatchUi, spec §6.2).
// Event-sourcing : l'état est le replay du journal ; les mutations poussent
// des événements puis rejouent. L'undo (Phase 2) retirera le dernier event.
class ScoreEngine {

    var mConfig;      // MatchConfig
    var mEvents;      // Array de tableaux positionnels

    // État dérivé (replay)
    var mPhase;             // ScorePhase.PLAYING / SET_RESULT / MATCH_FINISHED
    var mScoreMe;           // set courant
    var mScoreOpp;
    var mSetsMe;            // sets gagnés
    var mSetsOpp;
    var mSetNumber;         // 1-based
    var mLastSetScoreMe;    // score final du dernier set terminé (SET_RESULT)
    var mLastSetScoreOpp;

    function initialize(config) {
        mConfig = config;
        mEvents = [];
        replay();
    }

    // ---- mutations ----

    function pointMe() as Void {
        if (mPhase != ScorePhase.PLAYING) { return; }
        appendEvent([ScoreEvent.TYPE_POINT_ME]);
        checkAutoSetFinish(0);
    }

    function pointOpponent() as Void {
        if (mPhase != ScorePhase.PLAYING) { return; }
        appendEvent([ScoreEvent.TYPE_POINT_OPPONENT]);
        checkAutoSetFinish(1);
    }

    // Transition « set suivant » : depuis SET_RESULT (fin auto, set déjà crédité)
    // ou depuis PLAYING (changement manuel confirmé — leader strict crédité, §4.4).
    function changeSet() as Void {
        if (mPhase == ScorePhase.MATCH_FINISHED) { return; }
        var winner = -1;
        if (mPhase == ScorePhase.PLAYING) {
            if (mScoreMe > mScoreOpp) { winner = 0; }
            else if (mScoreOpp > mScoreMe) { winner = 1; }
        }
        appendEvent([ScoreEvent.TYPE_SET_CHANGED, winner]);
    }

    // Nouveau match (menu Réinitialiser ou DOWN sur MATCH_FINISHED).
    function newMatch(config) as Void {
        mConfig = config;
        mEvents = [];
        replay();
    }

    // ---- journal + replay ----

    function appendEvent(e) as Void {
        mEvents.add(e);
        replay();
    }

    function replay() as Void {
        mPhase = ScorePhase.PLAYING;
        mScoreMe = 0;
        mScoreOpp = 0;
        mSetsMe = 0;
        mSetsOpp = 0;
        mSetNumber = 1;
        mLastSetScoreMe = 0;
        mLastSetScoreOpp = 0;
        for (var i = 0; i < mEvents.size(); i += 1) {
            applyEvent(mEvents[i]);
        }
    }

    function applyEvent(e) as Void {
        switch (e[0]) {
        case ScoreEvent.TYPE_POINT_ME:
            mScoreMe += 1;
            break;
        case ScoreEvent.TYPE_POINT_OPPONENT:
            mScoreOpp += 1;
            break;
        case ScoreEvent.TYPE_SET_FINISHED:
            mLastSetScoreMe = mScoreMe;
            mLastSetScoreOpp = mScoreOpp;
            if (e[1] == 0) { mSetsMe += 1; } else { mSetsOpp += 1; }
            if (mSetsMe >= mConfig.mSetsToWin || mSetsOpp >= mConfig.mSetsToWin) {
                mPhase = ScorePhase.MATCH_FINISHED;
            } else {
                mPhase = ScorePhase.SET_RESULT;
            }
            break;
        case ScoreEvent.TYPE_SET_CHANGED:
            if (e[1] == 0) { mSetsMe += 1; }
            else if (e[1] == 1) { mSetsOpp += 1; }
            mSetNumber += 1;
            mScoreMe = 0;
            mScoreOpp = 0;
            mPhase = ScorePhase.PLAYING;
            break;
        case ScoreEvent.TYPE_MATCH_FINISHED:
            mPhase = ScorePhase.MATCH_FINISHED;
            break;
        }
    }

    // Fin de set automatique après un point : pousse SET_FINISHED puis,
    // si le match est gagné, MATCH_FINISHED (verrou §4.5).
    function checkAutoSetFinish(winner as Number) as Void {
        if (!Rules.isSetOver(mConfig, mScoreMe, mScoreOpp)) { return; }
        appendEvent([ScoreEvent.TYPE_SET_FINISHED, winner]);
        if (mPhase == ScorePhase.MATCH_FINISHED) {
            appendEvent([ScoreEvent.TYPE_MATCH_FINISHED]);
        }
    }

    // ---- lectures pour l'UI ----

    function getPhase() as Number { return mPhase; }
    function getScoreMe() as Number { return mScoreMe; }
    function getScoreOpp() as Number { return mScoreOpp; }
    function getSetsMe() as Number { return mSetsMe; }
    function getSetsOpp() as Number { return mSetsOpp; }
    function getSetNumber() as Number { return mSetNumber; }
    function getLastSetScoreMe() as Number { return mLastSetScoreMe; }
    function getLastSetScoreOpp() as Number { return mLastSetScoreOpp; }
    function getConfig() as MatchConfig { return mConfig; }
    function getEvents() as Array { return mEvents; }
}
```

- [ ] **Step 5: Vérifier que le build des tests passe (vert) puis l'exécuter sur les 3 profils**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
cd watch/connect-iq
"$SDK/bin/monkeyc" -d fr55 -f monkey.jungle -o bin/tests-fr55.prg -y ~/keys/developer_key.der -t -w \
  && "$SDK/bin/monkeydo" bin/tests-fr55.prg fr55 -t
```

Attendu : les 15 tests `PASSED` (4 Task 2 + 11 Task 3), aucun `FAILED`. Corriger jusqu'au vert. Fermer le simulateur, puis :

```bash
"$SDK/bin/monkeyc" -d instinct2 -f monkey.jungle -o bin/tests-instinct2.prg -y ~/keys/developer_key.der -t -w && "$SDK/bin/monkeydo" bin/tests-instinct2.prg instinct2 -t
"$SDK/bin/monkeyc" -d epix2pro51mm -f monkey.jungle -o bin/tests-epix2pro51mm.prg -y ~/keys/developer_key.der -t -w && "$SDK/bin/monkeydo" bin/tests-epix2pro51mm.prg epix2pro51mm -t
```

Attendu : vert sur les 3 profils.

- [ ] **Step 6: Commit**

```bash
git add watch/connect-iq/source/engine/ScoreEvent.mc watch/connect-iq/source/engine/ScoreEngine.mc watch/connect-iq/source/tests/EngineTest.mc
git commit -m "feat(phase1): ScoreEngine event-sourcing (points, replay, fin de set auto, verrou MATCH_FINISHED) — TDD"
```

---

### Task 4: ScoreEngine — transitions de set (TDD)

**Files:**
- Modify: `watch/connect-iq/source/tests/EngineTest.mc`
- Modify: `watch/connect-iq/source/engine/ScoreEngine.mc` (aucune modification attendue — les transitions sont déjà implémentées ; les tests les verrouillent. Si un test échoue, corriger le moteur.)

- [ ] **Step 1: Ajouter les tests de transition (rouge si le moteur est incomplet)**

Ajouter en fin de `source/tests/EngineTest.mc` :

```monkeyc
// ---- ScoreEngine : transitions de set (spec §4.4, §15.1) ----

(:test)
function test_engine_set_result_transition(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 21, 19);
    Test.assertEqualMessage(1, e.getPhase(), "SET_RESULT apres 21-19");
    e.changeSet();
    Test.assertEqualMessage(0, e.getPhase(), "PLAYING apres set suivant");
    Test.assertEqualMessage(2, e.getSetNumber(), "set 2");
    Test.assertEqualMessage(0, e.getScoreMe(), "set 2 : 0-0");
    Test.assertEqualMessage(0, e.getScoreOpp(), "set 2 : 0-0");
    Test.assertEqualMessage(1, e.getSetsMe(), "sets 1-0 conserves");
    return true;
}

(:test)
function test_engine_manual_set_change_leader_credited(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 5, 3);
    e.changeSet();   // changement manuel assumé : leader strict crédité
    Test.assertEqualMessage(0, e.getPhase(), "PLAYING apres changement manuel");
    Test.assertEqualMessage(2, e.getSetNumber(), "set 2");
    Test.assertEqualMessage(1, e.getSetsMe(), "leader (5-3) credite : sets 1-0");
    return true;
}

(:test)
function test_engine_manual_set_change_tie_not_credited(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 3, 3);
    e.changeSet();   // égalité : personne n'est crédité
    Test.assertEqualMessage(0, e.getSetsMe(), "egalite : sets me 0");
    Test.assertEqualMessage(0, e.getSetsOpp(), "egalite : sets opp 0");
    Test.assertEqualMessage(2, e.getSetNumber(), "set 2 quand meme");
    return true;
}

(:test)
function test_engine_match_locked(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 21, 0);
    e.changeSet();
    enginePoints(e, 21, 0);
    Test.assertEqualMessage(2, e.getPhase(), "MATCH_FINISHED");
    var count = e.getEvents().size();
    e.changeSet();   // sans effet sur un match fini
    Test.assertEqualMessage(count, e.getEvents().size(), "changeSet ignore apres MATCH_FINISHED");
    e.pointMe();     // sans effet non plus
    Test.assertEqualMessage(count, e.getEvents().size(), "point ignore apres MATCH_FINISHED");
    return true;
}

(:test)
function test_engine_new_match_reset(logger as Logger) as Boolean {
    var e = new ScoreEngine(MatchPresets.get(2));
    enginePoints(e, 21, 0);
    e.changeSet();
    e.newMatch(MatchPresets.get(0));   // nouveau match en 11 pts
    Test.assertEqualMessage(0, e.getScoreMe(), "reset 0-0");
    Test.assertEqualMessage(1, e.getSetNumber(), "reset set 1");
    Test.assertEqualMessage(0, e.getPhase(), "reset PLAYING");
    Test.assertEqualMessage(0, e.getEvents().size(), "journal vide");
    Test.assertEqualMessage(11, e.getConfig().mTargetScore, "nouvelle config 11 pts");
    return true;
}
```

- [ ] **Step 2: Exécuter sur les 3 profils**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
cd watch/connect-iq
"$SDK/bin/monkeyc" -d fr55 -f monkey.jungle -o bin/tests-fr55.prg -y ~/keys/developer_key.der -t -w \
  && "$SDK/bin/monkeydo" bin/tests-fr55.prg fr55 -t
"$SDK/bin/monkeyc" -d instinct2 -f monkey.jungle -o bin/tests-instinct2.prg -y ~/keys/developer_key.der -t -w && "$SDK/bin/monkeydo" bin/tests-instinct2.prg instinct2 -t
"$SDK/bin/monkeyc" -d epix2pro51mm -f monkey.jungle -o bin/tests-epix2pro51mm.prg -y ~/keys/developer_key.der -t -w && "$SDK/bin/monkeydo" bin/tests-epix2pro51mm.prg epix2pro51mm -t
```

Attendu : les 21 tests `PASSED` sur les 3 profils (16 fin de Task 3, dont le test de régression C1 `test_engine_manual_set_change_finishes_match`). Corriger le moteur si un test échoue (le design attendu est celui de ScoreEngine.mc Task 3 Step 4 — ne pas corriger les tests pour faire passer, sauf erreur prouvée).

- [ ] **Step 3: Commit**

```bash
git add watch/connect-iq/source/tests/EngineTest.mc watch/connect-iq/source/engine/ScoreEngine.mc
git commit -m "test(phase1): transitions de set verrouillées (SET_RESULT→suivant, manuel leader/égalité, match verrouillé, reset)"
```

---

### Task 5: UI — MatchView, MatchDelegate, App

**Files:**
- Create: `watch/connect-iq/source/ui/MatchView.mc`
- Create: `watch/connect-iq/source/ui/MatchDelegate.mc`
- Create: `watch/connect-iq/source/App.mc`

- [ ] **Step 1: Écrire `source/ui/MatchView.mc`**

Leçons Phase 0 intégrées : fond opaque **avant** `clear()` (commit 5a2207c), géométrie verticale dérivée de `getFontHeight` (commit 81a2048), textes sans accents.

```monkeyc
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.WatchUi;

// Écrans de l'app (mono-écran + états inline, spec §5).
module MatchScreen {
    const SETUP = 0;          // choix du format au démarrage
    const SCORE = 1;          // écran principal
    const CONFIRM_SET = 2;    // confirmation inline « terminer set ? » (DOWN=OUI BACK=NON)
    const SET_RESULT = 3;     // set terminé auto, en attente « set suivant » (DOWN)
    const MATCH_FINISHED = 4; // match terminé (DOWN = nouveau match)
    const MENU = 5;           // menu inline UP-long (Reprendre / Quitter)
}

class MatchView extends WatchUi.View {

    var mScreen = MatchScreen.SETUP;
    var mSetupIndex = 2;      // 21 POINTS par défaut
    var mMenuIndex = 0;
    var mEngine = null;

    function initialize() {
        View.initialize();
    }

    // ---- délégué -> vue (le delegate n'a aucune logique) ----

    function onSelect() as Boolean {
        if (mScreen == MatchScreen.SETUP) {
            startMatch();
            return true;
        }
        if (mScreen == MatchScreen.SCORE) {
            mEngine.pointMe();
            syncScreen();
            return true;
        }
        if (mScreen == MatchScreen.MENU) {
            return menuSelect();
        }
        return true;
    }

    function onBack() as Boolean {
        if (mScreen == MatchScreen.SETUP) {
            return false;   // aucun match en cours : BACK ferme l'app (comportement CIQ naturel)
        }
        if (mScreen == MatchScreen.SCORE) {
            mEngine.pointOpponent();
            syncScreen();
            return true;    // BACK = point adversaire, ne quitte jamais (spec §3.2)
        }
        if (mScreen == MatchScreen.CONFIRM_SET) {
            mScreen = MatchScreen.SCORE;   // BACK = NON
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == MatchScreen.MENU) {
            mScreen = MatchScreen.SCORE;
            WatchUi.requestUpdate();
            return true;
        }
        return true;
    }

    function onUp() as Boolean {
        if (mScreen == MatchScreen.SETUP) {
            mSetupIndex = (mSetupIndex + MatchPresets.count() - 1) % MatchPresets.count();
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == MatchScreen.MENU) {
            mMenuIndex = (mMenuIndex + 1) % 2;   // liste de 2 : UP descend visuellement
            WatchUi.requestUpdate();
            return true;
        }
        return true;   // UNDO = Phase 2, UP sans effet en SCORE
    }

    function onDown() as Boolean {
        if (mScreen == MatchScreen.SETUP) {
            mSetupIndex = (mSetupIndex + 1) % MatchPresets.count();
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == MatchScreen.SCORE) {
            mScreen = MatchScreen.CONFIRM_SET;   // DOWN = changement de set -> confirmation inline
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == MatchScreen.SET_RESULT) {
            mEngine.changeSet();                 // « set suivant » (SET_FINISHED déjà enregistré)
            syncScreen();
            return true;
        }
        if (mScreen == MatchScreen.MATCH_FINISHED) {
            mScreen = MatchScreen.SETUP;         // DOWN = NOUVEAU (format mémorisé)
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == MatchScreen.MENU) {
            mMenuIndex = (mMenuIndex + 1) % 2;
            WatchUi.requestUpdate();
            return true;
        }
        return true;
    }

    function onMenuButton() as Boolean {
        if (mScreen == MatchScreen.SCORE) {
            mScreen = MatchScreen.MENU;          // UP-long = menu inline
            mMenuIndex = 0;
            WatchUi.requestUpdate();
            return true;
        }
        return true;
    }

    // ---- transitions ----

    function startMatch() as Void {
        mEngine = new ScoreEngine(MatchPresets.get(mSetupIndex));
        mScreen = MatchScreen.SCORE;
        WatchUi.requestUpdate();
    }

    // Après chaque mutation moteur : aligner l'écran sur la phase dérivée.
    function syncScreen() as Void {
        var p = mEngine.getPhase();
        if (p == ScorePhase.MATCH_FINISHED) {
            mScreen = MatchScreen.MATCH_FINISHED;
        } else if (p == ScorePhase.SET_RESULT) {
            mScreen = MatchScreen.SET_RESULT;
        } else if (mScreen != MatchScreen.MENU && mScreen != MatchScreen.CONFIRM_SET) {
            mScreen = MatchScreen.SCORE;
        }
        WatchUi.requestUpdate();
    }

    function menuSelect() as Boolean {
        if (mMenuIndex == 1) {
            System.exit();
            return true;
        }
        mScreen = MatchScreen.SCORE;   // Reprendre
        WatchUi.requestUpdate();
        return true;
    }

    // ---- rendu ----

    function onUpdate(dc as Dc) as Void {
        // Fond opaque AVANT clear() — sinon les frames s'accumulent (leçon Phase 0).
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var w = dc.getWidth();
        var h = dc.getHeight();
        switch (mScreen) {
        case MatchScreen.SETUP:
            drawSetup(dc, w, h);
            break;
        case MatchScreen.SCORE:
            drawScore(dc, w, h);
            break;
        case MatchScreen.CONFIRM_SET:
            drawConfirmSet(dc, w, h);
            break;
        case MatchScreen.SET_RESULT:
            drawSetResult(dc, w, h);
            break;
        case MatchScreen.MATCH_FINISHED:
            drawMatchFinished(dc, w, h);
            break;
        case MatchScreen.MENU:
            drawMenu(dc, w, h);
            break;
        }
    }

    function drawSetup(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fMedium = dc.getFontHeight(Graphics.FONT_MEDIUM);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "FORMAT", Graphics.TEXT_CENTER);
        var y = h / 2 - (3 * fMedium / 2);
        for (var i = 0; i < MatchPresets.count(); i += 1) {
            var marker = (i == mSetupIndex) ? "> " : "  ";
            dc.drawText(w / 2, y, Graphics.FONT_MEDIUM, marker + MatchPresets.label(i), Graphics.TEXT_CENTER);
            y += 3 * fMedium / 2;
        }
        dc.drawText(w / 2, h - fSmall - h / 20, Graphics.FONT_TINY, "START = OK", Graphics.TEXT_CENTER);
    }

    function drawScore(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "SET " + mEngine.getSetNumber(), Graphics.TEXT_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getScoreMe() + " - " + mEngine.getScoreOpp(), Graphics.TEXT_CENTER);
        dc.drawText(w / 4, h / 2 + fLarge, Graphics.FONT_SMALL, "MOI", Graphics.TEXT_CENTER);
        dc.drawText(3 * w / 4, h / 2 + fLarge, Graphics.FONT_SMALL, "LUI", Graphics.TEXT_CENTER);
        dc.drawText(w / 2, h - fSmall - h / 20, Graphics.FONT_TINY,
            MatchPresets.label(mSetupIndex) + "  SETS " + mEngine.getSetsMe() + "-" + mEngine.getSetsOpp(),
            Graphics.TEXT_CENTER);
    }

    function drawConfirmSet(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 4, Graphics.FONT_SMALL, "TERMINER SET " + mEngine.getSetNumber() + " ?", Graphics.TEXT_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getScoreMe() + " - " + mEngine.getScoreOpp(), Graphics.TEXT_CENTER);
        dc.drawText(w / 2, 3 * h / 4, Graphics.FONT_SMALL, "DOWN=OUI  BACK=NON", Graphics.TEXT_CENTER);
    }

    function drawSetResult(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "SET " + mEngine.getSetNumber() + " TERMINE", Graphics.TEXT_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getLastSetScoreMe() + " - " + mEngine.getLastSetScoreOpp(), Graphics.TEXT_CENTER);
        dc.drawText(w / 2, h / 2 + fLarge, Graphics.FONT_SMALL,
            "SETS " + mEngine.getSetsMe() + "-" + mEngine.getSetsOpp(), Graphics.TEXT_CENTER);
        dc.drawText(w / 2, h - fSmall - h / 20, Graphics.FONT_TINY, "DOWN = SET SUIV.", Graphics.TEXT_CENTER);
    }

    function drawMatchFinished(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        dc.drawText(w / 2, h / 4, Graphics.FONT_SMALL, "MATCH TERMINE", Graphics.TEXT_CENTER);
        dc.drawText(w / 2, h / 2 - fLarge / 2, Graphics.FONT_LARGE,
            mEngine.getSetsMe() + " - " + mEngine.getSetsOpp(), Graphics.TEXT_CENTER);
        var winner = (mEngine.getSetsMe() > mEngine.getSetsOpp()) ? "MOI GAGNE" : "LUI GAGNE";
        dc.drawText(w / 2, h / 2 + fLarge, Graphics.FONT_SMALL, winner, Graphics.TEXT_CENTER);
        dc.drawText(w / 2, h - fSmall - h / 20, Graphics.FONT_TINY, "DOWN = NOUVEAU", Graphics.TEXT_CENTER);
    }

    function drawMenu(dc as Dc, w as Number, h as Number) as Void {
        var fSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var fMedium = dc.getFontHeight(Graphics.FONT_MEDIUM);
        dc.drawText(w / 2, h / 8, Graphics.FONT_SMALL, "MENU", Graphics.TEXT_CENTER);
        var items = ["REPRENDRE", "QUITTER"];
        var y = h / 2 - fMedium;
        for (var i = 0; i < items.size(); i += 1) {
            var marker = (i == mMenuIndex) ? "> " : "  ";
            dc.drawText(w / 2, y, Graphics.FONT_MEDIUM, marker + items[i], Graphics.TEXT_CENTER);
            y += 3 * fMedium / 2;
        }
    }
}
```

- [ ] **Step 2: Écrire `source/ui/MatchDelegate.mc`**

```monkeyc
using Toybox.WatchUi;

// BehaviorDelegate (spec §3.1) : traduit les boutons en appels de la vue.
// Aucune logique ici. onKeyPressed/onKeyReleased non utilisés (§3.2).
class MatchDelegate extends WatchUi.BehaviorDelegate {

    var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() as Boolean {
        return mView.onSelect();
    }

    function onBack() as Boolean {
        return mView.onBack();
    }

    function onPreviousPage() as Boolean {
        return mView.onUp();
    }

    function onNextPage() as Boolean {
        return mView.onDown();
    }

    function onMenu() as Boolean {
        return mView.onMenuButton();
    }
}
```

- [ ] **Step 3: Écrire `source/App.mc`**

```monkeyc
using Toybox.Application;
using Toybox.WatchUi;

// Persistance onStart/onStop : Phase 3 (spec §16). Phase 1 = session volatile.
class BadmintonApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new MatchView();
        return [view, new MatchDelegate(view)];
    }
}
```

- [ ] **Step 4: Build release sur les 5 devices (zéro warning attendu)**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
cd watch/connect-iq
for d in epix2pro42mm epix2pro47mm epix2pro51mm fr55 instinct2; do
  "$SDK/bin/monkeyc" -d "$d" -f monkey.jungle -o "bin/badmintonscore-$d.prg" -y ~/keys/developer_key.der -w -r \
    && echo "OK $d" || echo "FAIL $d"
done
ls -la bin/
```

Attendu : 5 lignes `OK`, 5 `.prg` (~15-25 Ko), **aucun warning** hors l'échelle de l'icône launcher (le PNG 36x36 est rescalé selon le device — ex. 35x35 demandé sur fr55 ; icône à redessiner plus tard).

- [ ] **Step 5: Smoke test simulateur — l'app démarre sur le Setup**

```bash
"$SDK/bin/monkeydo" bin/badmintonscore-epix2pro51mm.prg epix2pro51mm
```

Attendu (à vérifier visuellement dans le simulateur, valider avec le propriétaire s'il est dispo) : écran `FORMAT` avec `> 21 POINTS` sélectionné, `START = OK` en bas. UP/DOWN déplacent le curseur sur 11/15/21. **BACK ferme l'app** (retour cadran). Fermer le simulateur.

- [ ] **Step 6: Commit**

```bash
git add watch/connect-iq/source
git commit -m "feat(phase1): UI mono-écran (Setup/Score/ConfirmSet/SetResult/MatchFinished/Menu) + delegate §3.2 sans UNDO"
```

---

### Task 6: Match complet en simulateur, 3 profils [USER ACTION]

**Files:** aucun (exécution) · Create: `docs/superpowers/notes/phase-1-sim-results.md` (consignation)

- [ ] **Step 1: Lancer l'app sur epix2pro51mm**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
cd watch/connect-iq
"$SDK/bin/monkeydo" bin/badmintonscore-epix2pro51mm.prg epix2pro51mm
```

- [ ] **Step 2: Scénario de match complet (boutons du simulateur)**

| # | Action | Attendu |
|---|---|---|
| 1 | UP/DOWN sur SETUP | curseur 11/15/21 |
| 2 | sélectionner 21 POINTS, START | SCORE `SET 1`, `0 - 0` |
| 3 | 21× START, 18× BACK | `21 - 18`, écran `SET 1 TERMINE`, `SETS 1-0` |
| 4 | DOWN | `SET 2`, `0 - 0`, sets 1-0 |
| 5 | 18× START, 21× BACK | `SET 2 TERMINE` `18 - 21`, `SETS 1-1` |
| 6 | DOWN | `SET 3`, `0 - 0` |
| 7 | DOWN puis BACK (confirmation) | retour SCORE sans point marqué |
| 8 | 21× START, 17× BACK | `MATCH TERMINE` `2 - 1` `MOI GAGNE` |
| 9 | START en MATCH_FINISHED | sans effet |
| 10 | DOWN | retour SETUP (21 POINTS mémorisé) |
| 11 | UP-long | menu `> REPRENDRE / QUITTER` — START sur QUITTER ferme l'app |

- [ ] **Step 3: Répéter plus court sur fr55 et instinct2** (11 pts : 11-9 puis set suivant puis 11-8 → MATCH_FINISHED) et vérifier la lisibilité 2 couleurs sur instinct2.

- [ ] **Step 4: Consigner dans `docs/superpowers/notes/phase-1-sim-results.md`** (tableau attendu/observé par profil + anomalies) puis :

```bash
git add docs/superpowers/notes/phase-1-sim-results.md
git commit -m "docs(phase1): résultats simulateur match complet (3 profils)"
```

---

### Task 7: Sideload matériel + match réel sur epix Pro 51 mm [USER ACTION]

**Files:** aucun (matériel)

- [ ] **Step 1: Build + copie via openMTP**

```bash
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
cd watch/connect-iq
"$SDK/bin/monkeyc" -d epix2pro51mm -f monkey.jungle -o bin/badmintonscore-epix2pro51mm.prg -y ~/keys/developer_key.der -w -r
cp bin/badmintonscore-epix2pro51mm.prg ../sideload/ 2>/dev/null || mkdir -p ../sideload && cp bin/badmintonscore-epix2pro51mm.prg ../sideload/
```

(protocole openMTP validé Phase 0 : openMTP → `watch/connect-iq/sideload/` → `GARMIN/APPS/` → fermer openMTP → débrancher. L'app « Badminton » s'installe à côté de ButtonTest — id distinct.)

- [ ] **Step 2: Match réel complet** — refaire le scénario Task 6 Step 2 (2-1 en 21 pts) sur la montre, vérifier lisibilité à bout de bras, et : UP en SCORE = sans effet (pas d'UNDO encore), DOWN-long = hotkey musique sans effet sur le score (U2 confirmé Phase 0).

- [ ] **Step 3: Consigner** dans `docs/superpowers/notes/phase-1-sim-results.md` (section matériel) + commit :

```bash
git add docs/superpowers/notes/phase-1-sim-results.md
git commit -m "docs(phase1): validation matérielle epix Pro 51 mm (match complet aux boutons)"
```

---

### Task 8: Clôture Phase 1

- [ ] **Step 1: Vérifier le critère de sortie §16** : un match complet compté aux boutons sur epix Pro ✅ (simu Task 6 + matériel Task 7) ; mapping boutons §3.2 sur les 3 profils simu ✅.

- [ ] **Step 2: Consigner les enseignements** dans `docs/superpowers/notes/2026-09-18-phase-1-findings.md` (format libre, même esprit que Phase 0 : leçons UI, écarts entre spec et réalité, décisions pour la Phase 2).

- [ ] **Step 3: Commit + push + PR**

```bash
git add docs/superpowers/notes/
git commit -m "docs(phase1): synthèse enseignements + critère de sortie validé"
git push -u origin phase-1
gh pr create --base main --head phase-1 --title "Phase 1 : scoring minimal" --body "Moteur event-sourcing + UI mono-écran + validation simu/matériel. Voir docs/superpowers/plans/2026-09-18-phase-1-minimal-scoring.md"
```

Puis : superpowers:finishing-a-development-branch.

---

## Self-Review (fait à l'écriture du plan)

1. **Spec coverage** : §3.1/§3.2 (delegate + mapping, sauf UNDO = Phase 2) ✅ Task 5 · §4.1 (MatchConfig/presets) ✅ Task 2 · §4.2 (Rules + auto-fin) ✅ Task 2/3 · §4.3 (fin de match) ✅ Task 3 · §4.4 (confirmation inline + SET_CHANGED/SET_FINISHED) ✅ Task 3/4/5 · §5 (4 états + Setup + menu minimal validé) ✅ Task 5 · §6.2 (moteur PUR) ✅ Task 3 · §15.1 (sous-ensemble sans undo/persistance/protocole = 20 tests) ✅ Task 2-4. Écart assumé : tests sous `source/tests/` (structure Phase 1) au lieu de `tests/` racine (§6).
2. **Placeholder scan** : aucun TBD/TODO ; tout le code est écrit dans le plan ; l'assert erroné du test `test_engine_match_finished_2_sets` est corrigé dans le texte du plan (45 events, pas 4).
3. **Type consistency** : `Rules.isSetOver(config, me, opp)` utilisé par `ScoreEngine.checkAutoSetFinish` ✅ ; `MatchPresets.get/count/label` utilisés par tests + vue ✅ ; getters du moteur (getPhase/getScore*/getSets*/getSetNumber/getLastSet*/getConfig/getEvents) utilisés par tests + vue ✅ ; `ScoreEvent`/`ScorePhase` const référencés de façon cohérente ✅ ; vue : `mEngine.getSetNumber()` = set courant (SET_RESULT affiche le set qui vient de finir, la transition l'incrémente) ✅.
