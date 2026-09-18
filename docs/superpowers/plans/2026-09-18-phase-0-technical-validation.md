# Phase 0 — Validation Technique (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Valider la chaîne technique Garmin Connect IQ de bout en bout : SDK installé, clé développeur, projet minimal compilable pour les 5 device IDs, prototype « button test » vérifié en simulateur ET sur le matériel réel (epix Pro 51 mm), sondes `Application.Storage` et logs — pour lever les incertitudes U1-U6 de la spec.

**Architecture:** Un prototype jetable dans `prototypes/button-test/` (séparé du futur projet `watch/connect-iq/`). Watch-app CIQ unique multi-products (`minApiLevel 3.4.0`), `BehaviorDelegate` + vue inline qui affiche le dernier événement bouton + compteur + historique + mini-menu inline avec sortie `System.exit()`. Sondes de persistance via le framework officiel Run No Evil (`-t`).

**Tech Stack:** Monkey C (Connect IQ SDK 9.2.0), Java 17 (Temurin), `monkeyc`/`monkeydo`/`connectiq` CLI, Run No Evil, openssl pour la clé, sideload par copie `/GARMIN/APPS/`.

**Référence:** Spec `docs/superpowers/specs/2026-09-18-badminton-score-design.md` (§3 boutons, §7.2 storage, §11 build/sideload, §15.2 checklist, §16 Phase 0, §17 incertitudes).

**Note:** Repo neuf, branche `main` seule — pas de worktree nécessaire (le skill en suggère un par défaut ; dérogation assumée : aucun travail parallèle en cours).

**Marquage:** Les tâches `[USER ACTION]` exigent une interaction humaine (login Garmin, montre branchée). L'agent prépare tout et s'arrête à ces étapes avec des instructions précises.

---

## File Structure (prototype)

```
prototypes/button-test/
├── manifest.xml                  # watch-app, 5 products, permission Communications
├── monkey.jungle                 # manifest + sourcePath + resourcePath
├── resources/
│   ├── strings/strings.xml       # AppName
│   └── drawables/
│       ├── drawables.xml         # LauncherIcon
│       └── launcher_icon.png     # généré par script (Task 5)
├── source/
│   ├── ButtonTestApp.mc          # AppBase : getInitialView, onStart/onStop
│   ├── ButtonTestView.mc         # rendu inline : test screen + menu
│   ├── ButtonTestDelegate.mc     # BehaviorDelegate : 5 handlers
│   ├── DeviceProbe.mc            # sonde getDeviceSettings (U3)
│   └── tests/
│       └── StorageLimitTest.mc   # Run No Evil : roundtrip + sondes capacité (U5)
└── bin/                          # .prg (gitignoré)
```

Responsabilités : `ButtonTestApp` = cycle de vie ; `ButtonTestView` = état d'affichage + rendu ; `ButtonTestDelegate` = mapping boutons ; `DeviceProbe` = logs d'inspection ; `StorageLimitTest` = preuves de capacité. Aucun partage avec le futur projet (prototype jetable).

---

### Task 1: Java 17 (requis par les CLIs Monkey C)

**Files:** aucun fichier repo (environnement système)

- [ ] **Step 1: Vérifier la version Java courante**

```bash
java -version
```

Attendu actuel : `1.8.0_292` (Java 8 — insuffisant, la doc Monkey C exige Java 11+). Si la sortie affiche déjà ≥ 17, passer à la Task 2.

- [ ] **Step 2: Installer Temurin 17 via Homebrew**

```bash
which brew && brew install --cask temurin@17
```

Attendu : installation OK. Si `brew` absent, télécharger le pkg adapté à l'archi (`uname -m` → `arm64` ou `x86_64`) :

```bash
uname -m
curl -L -o /tmp/temurin17.pkg "https://api.adoptium.net/v3/installer/latest/17/ga/mac/arm64/jdk/hotspot/normal/eclipse"
sudo installer -pkg /tmp/temurin17.pkg -target /
```

(sur Intel : remplacer `arm64` par `x64` dans l'URL)

- [ ] **Step 3: Vérifier que Java 17 est actif**

```bash
java -version
```

Attendu : `openjdk version "17.x.x"`. Si encore 1.8 (JAVA_HOME épinglé), ajouter à `~/.zshrc` :

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
export PATH="$JAVA_HOME/bin:$PATH"
```

puis `source ~/.zshrc` et re-vérifier `java -version`.

---

### Task 2: SDK Manager + SDK 9.2.0 + profils devices [USER ACTION]

**Files:** aucun fichier repo (environnement système)

- [ ] **Step 1: Télécharger et installer SDK Manager**

L'utilisateur télécharge `connectiq-sdk-manager.dmg` depuis https://developer.garmin.com/connect-iq/sdk/ (bouton *Download SDK Manager for Mac*), ouvre le dmg, glisse **Connect IQ SDK Manager** dans Applications, puis le lance.

- [ ] **Step 2: Login Garmin + installation du SDK**

Dans SDK Manager : login compte Garmin → onglet **SDKs** → installer le SDK courant (**9.2.0** ou plus récent).

- [ ] **Step 3: Télécharger les profils devices**

Onglet **Devices** : installer les 5 profils — `fr55`, `instinct2`, `epix2pro42mm`, `epix2pro47mm`, `epix2pro51mm`.

- [ ] **Step 4: Vérifier l'installation**

```bash
cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
```

Attendu : un chemin absolu vers le SDK (ex. `.../ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0.../`), sans erreur.

---

### Task 3: PATH des CLIs + vérification

**Files:** `~/.zshrc` (hors repo)

- [ ] **Step 1: Ajouter le PATH SDK au shell**

```bash
printf '\n# Garmin Connect IQ SDK\nexport PATH="$PATH:$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")/bin"\n' >> ~/.zshrc
source ~/.zshrc
```

- [ ] **Step 2: Vérifier les 3 CLIs**

```bash
which monkeyc monkeydo connectiq
```

Attendu : les 3 chemins résolvent dans `<sdk>/bin/`. Si `which` échoue, tester en absolu : `ls "$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")/bin"`.

---

### Task 4: Clé développeur (une fois, hors repo)

**Files:** `~/keys/developer_key.pem`, `~/keys/developer_key.der` (hors repo ; `.gitignore` couvre déjà `*.pem`/`*.der`)

- [ ] **Step 1: Générer la paire de clés**

```bash
mkdir -p ~/keys
openssl genrsa -out ~/keys/developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in ~/keys/developer_key.pem -out ~/keys/developer_key.der -nocrypt
```

- [ ] **Step 2: Vérifier le format DER**

```bash
file ~/keys/developer_key.der
```

Attendu : `data` (binaire DER). Conserver ces fichiers : toute build est signée avec ; indispensable pour signer les mises à jour.

---

### Task 5: Squelette du projet prototype

**Files:**
- Create: `prototypes/button-test/manifest.xml`
- Create: `prototypes/button-test/monkey.jungle`
- Create: `prototypes/button-test/resources/strings/strings.xml`
- Create: `prototypes/button-test/resources/drawables/drawables.xml`
- Create: `prototypes/button-test/resources/drawables/launcher_icon.png` (générée)

- [ ] **Step 1: Créer l'arborescence**

```bash
mkdir -p prototypes/button-test/source/tests prototypes/button-test/resources/drawables prototypes/button-test/resources/strings prototypes/button-test/bin
```

- [ ] **Step 2: Écrire `prototypes/button-test/manifest.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<iq:manifest xmlns:iq="http://www.garmin.com/wadl/connectiq" version="3">
    <iq:application id="com.marcsuarez.badminton.buttontest" version="0.1.0" minSdkVersion="3.4.0" minApiLevel="3.4.0" entry="ButtonTestApp">
        <iq:products>
            <iq:product id="epix2pro42mm"/>
            <iq:product id="epix2pro47mm"/>
            <iq:product id="epix2pro51mm"/>
            <iq:product id="fr55"/>
            <iq:product id="instinct2"/>
        </iq:products>
        <iq:permissions>
            <iq:permission id="Communications"/>
        </iq:permissions>
        <iq:languages>
            <iq:language>eng</iq:language>
        </iq:languages>
    </iq:application>
</iq:manifest>
```

- [ ] **Step 3: Écrire `prototypes/button-test/monkey.jungle`**

```
project.manifest = manifest.xml
base.sourcePath = source
base.resourcePath = resources
```

- [ ] **Step 4: Écrire `prototypes/button-test/resources/strings/strings.xml`**

```xml
<strings>
    <string id="AppName">ButtonTest</string>
</strings>
```

- [ ] **Step 5: Écrire `prototypes/button-test/resources/drawables/drawables.xml`**

```xml
<drawables>
    <bitmap id="LauncherIcon" filename="launcher_icon.png"/>
</drawables>
```

- [ ] **Step 6: Générer l'icône launcher (PNG 36×36, python3 natif)**

```bash
python3 - <<'EOF'
import struct, zlib
W = H = 36
row = b'\x00' + b'\x3c\x78\xc8' * W
raw = row * H
def chunk(t, d):
    c = t + d
    return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(raw))
png += chunk(b'IEND', b'')
open('prototypes/button-test/resources/drawables/launcher_icon.png', 'wb').write(png)
EOF
file prototypes/button-test/resources/drawables/launcher_icon.png
```

Attendu : `PNG image data, 36 x 36, 8-bit/color RGB, non-interlaced`. Si `python3` absent : installer les Xcode CLT (`xcode-select --install`) puis relancer.

- [ ] **Step 7: Commit**

```bash
git add prototypes/button-test
git commit -m "feat(phase0): squelette prototype button-test (manifest 5 devices, jungle, ressources)"
```

---

### Task 6: Application minimale compilable (code complet)

**Files:**
- Create: `prototypes/button-test/source/ButtonTestApp.mc`
- Create: `prototypes/button-test/source/ButtonTestView.mc`
- Create: `prototypes/button-test/source/ButtonTestDelegate.mc`
- Create: `prototypes/button-test/source/DeviceProbe.mc`

- [ ] **Step 1: Écrire `source/DeviceProbe.mc` (sonde U3 — try/catch sur champs candidats, compile-safe)**

```monkeyc
using Toybox.System;

module DeviceProbe {

    function run() as Void {
        var s = System.getDeviceSettings();
        System.println("[probe] screenWidth=" + s.screenWidth);
        System.println("[probe] screenHeight=" + s.screenHeight);
        System.println("[probe] shape=" + s.shape);
        probeField(s, "isTouchScreen");
        probeField(s, "isTouch");
    }

    function probeField(s as Object, name as String) as Void {
        try {
            var v = s.property(name);
            System.println("[probe] " + name + "=" + v);
        } catch (e) {
            System.println("[probe] " + name + " ABSENT");
        }
    }
}
```

Note : si `Object.property(name)` n'existe pas dans le SDK courant (à vérifier dans https://developer.garmin.com/connect-iq/api-docs/Toybox/Lang/Object.html), remplacer `probeField` par cette variante en accès direct (compilée dynamiquement, échec attrapé au runtime) :

```monkeyc
    function probeField(s as Object, name as String) as Void {
        if (name.equals("isTouchScreen")) {
            try {
                System.println("[probe] isTouchScreen=" + s.isTouchScreen);
            } catch (e) {
                System.println("[probe] isTouchScreen ABSENT");
            }
        } else {
            try {
                System.println("[probe] isTouch=" + s.isTouch);
            } catch (e) {
                System.println("[probe] isTouch ABSENT");
            }
        }
    }
```

- [ ] **Step 2: Écrire `source/ButtonTestView.mc`**

```monkeyc
using Toybox.Graphics;
using Toybox.System;
using Toybox.WatchUi;

class ButtonTestView extends WatchUi.View {

    var mMode = 0;                 // 0 = écran test, 1 = menu inline
    var mMenuIndex = 0;
    var mLastEvent = "AUCUN";
    var mCount = 0;
    var mHistory = [];
    var mMenuItems = ["CONTINUER", "QUITTER"];

    function initialize() {
        View.initialize();
    }

    function record(label as String) as Void {
        mLastEvent = label;
        mCount = mCount + 1;
        pushHistory(mCount + ": " + label);
        WatchUi.requestUpdate();
    }

    function openMenu() as Void {
        mMode = 1;
        mMenuIndex = 0;
        WatchUi.requestUpdate();
    }

    function closeMenu() as Void {
        mMode = 0;
        WatchUi.requestUpdate();
    }

    function menuSelect() as Boolean {
        if (mMenuIndex == 1) {
            System.exit();
            return true;
        }
        closeMenu();
        return true;
    }

    function menuUp() as Boolean {
        mMenuIndex = (mMenuIndex + mMenuItems.size() - 1) % mMenuItems.size();
        WatchUi.requestUpdate();
        return true;
    }

    function menuDown() as Boolean {
        mMenuIndex = (mMenuIndex + 1) % mMenuItems.size();
        WatchUi.requestUpdate();
        return true;
    }

    function pushHistory(s as String) as Void {
        if (mHistory.size() >= 6) {
            var next = [];
            for (var i = 1; i < mHistory.size(); i += 1) {
                next.add(mHistory[i]);
            }
            mHistory = next;
        }
        mHistory.add(s);
    }

    function onUpdate(dc as Dc) as Void {
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 10, Graphics.FONT_SMALL, "BUTTON TEST", Graphics.TEXT_CENTER);
        if (mMode == 1) {
            dc.drawText(w / 2, h / 4, Graphics.FONT_MEDIUM, "MENU", Graphics.TEXT_CENTER);
            var y = h / 2 - 20;
            for (var i = 0; i < mMenuItems.size(); i += 1) {
                var marker = (i == mMenuIndex) ? "> " : "  ";
                dc.drawText(w / 2, y, Graphics.FONT_MEDIUM, marker + mMenuItems[i], Graphics.TEXT_CENTER);
                y += 30;
            }
            return;
        }
        dc.drawText(w / 2, h / 2 - 40, Graphics.FONT_LARGE, mLastEvent, Graphics.TEXT_CENTER);
        dc.drawText(w / 2, h / 2 + 20, Graphics.FONT_MEDIUM, "N=" + mCount, Graphics.TEXT_CENTER);
        var y2 = h - 15 - (mHistory.size() - 1) * 18;
        for (var j = 0; j < mHistory.size(); j += 1) {
            dc.drawText(w / 2, y2 + j * 18, Graphics.FONT_TINY, mHistory[j], Graphics.TEXT_CENTER);
        }
    }
}
```

- [ ] **Step 3: Écrire `source/ButtonTestDelegate.mc`**

```monkeyc
using Toybox.WatchUi;

class ButtonTestDelegate extends WatchUi.BehaviorDelegate {

    var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() as Boolean {
        if (mView.mMode == 1) { return mView.menuSelect(); }
        mView.record("START");
        return true;
    }

    function onBack() as Boolean {
        if (mView.mMode == 1) { mView.closeMenu(); return true; }
        mView.record("BACK");
        return true;
    }

    function onPreviousPage() as Boolean {
        if (mView.mMode == 1) { return mView.menuUp(); }
        mView.record("UP");
        return true;
    }

    function onNextPage() as Boolean {
        if (mView.mMode == 1) { return mView.menuDown(); }
        mView.record("DOWN");
        return true;
    }

    function onMenu() as Boolean {
        if (mView.mMode == 1) { return true; }
        mView.record("UP-LONG");
        mView.openMenu();
        return true;
    }
}
```

- [ ] **Step 4: Écrire `source/ButtonTestApp.mc`**

```monkeyc
using Toybox.Application;
using Toybox.System;
using Toybox.WatchUi;

class ButtonTestApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new ButtonTestView();
        return [view, new ButtonTestDelegate(view)];
    }

    function onStart(state) {
        System.println("=== ButtonTest onStart ===");
        DeviceProbe.run();
    }

    function onStop(state) {
        System.println("=== ButtonTest onStop ===");
    }
}
```

- [ ] **Step 5: Build pour les 5 devices (le test ultime : profils devices présents + signature + limites mémoire)**

```bash
cd prototypes/button-test
for d in epix2pro42mm epix2pro47mm epix2pro51mm fr55 instinct2; do
  monkeyc -d "$d" -f monkey.jungle -o "bin/buttontest-$d.prg" -y ~/keys/developer_key.der -w -r \
    && echo "OK $d" || echo "FAIL $d"
done
ls -la bin/
```

Attendu : 5 lignes `OK …`, 5 fichiers `.prg` de ~20-60 Ko. **`instinct2` doit réussir** (profil le plus contraint, 96 Ko). En cas d'erreur « unknown device » : profil device non téléchargé (Task 2 Step 3). En cas d'erreur de signature : chemin de la clé (`-y`) ou format DER (Task 4).

- [ ] **Step 6: Commit**

```bash
git add prototypes/button-test/source prototypes/button-test/manifest.xml prototypes/button-test/monkey.jungle
git commit -m "feat(phase0): app button-test compilable (BehaviorDelegate, vue inline, menu inline, sonde device)"
```

---

### Task 7: Test boutons en simulateur (les 3 profils d'écran)

**Files:** aucun (exécution)

- [ ] **Step 1: Lancer sur fr55 (MIP rond 208, 8 couleurs)**

```bash
cd prototypes/button-test
monkeydo bin/buttontest-fr55.prg fr55
```

Le simulateur s'ouvre. Dans la fenêtre simulateur, cliquer chaque bouton et vérifier l'écran :

| Action simulateur | Affichage attendu |
|---|---|
| clic START | gros texte `START`, N augmente, ligne historique `n: START` |
| clic BACK | `BACK` (l'app **ne quitte pas**) |
| clic UP | `UP` |
| clic DOWN | `DOWN` |
| UP maintenu (clic long) | `UP-LONG` puis écran MENU (CONTINUER/QUITTER) |
| dans MENU : DOWN, UP | curseur `>` bouge |
| dans MENU : BACK | retour écran test |
| dans MENU : START sur QUITTER | app fermée (retour cadran simu) |

Relancer (`monkeydo …`) et vérifier aussi la console : lignes `[probe] …` présentes au lancement (les copier pour U3).

- [ ] **Step 2: Idem sur instinct2 (semi-octogone 176, 2 couleurs)**

```bash
monkeydo bin/buttontest-instinct2.prg instinct2
```

Même checklist. Vérifier lisibilité 2 couleurs (texte blanc sur fond noir, aucun gris illisible).

- [ ] **Step 3: Idem sur epix2pro51mm (AMOLED rond 454)**

```bash
monkeydo bin/buttontest-epix2pro51mm.prg epix2pro51mm
```

Même checklist.

- [ ] **Step 4: Consigner les résultats simulateur** (boutons OK/KO par profil + sortie `[probe]`) dans un brouillon `docs/superpowers/notes/phase-0-sim-results.md` :

```markdown
# Phase 0 — Résultats simulateur (button-test)

| Profil | START | BACK | UP | DOWN | UP-LONG→MENU | Menu UP/DOWN/START/BACK | Sonde [probe] |
|---|---|---|---|---|---|---|---|
| fr55 | | | | | | | |
| instinct2 | | | | | | | |
| epix2pro51mm | | | | | | | |

Sortie [probe] brute (U3) :
```

---

### Task 8: Sondes Application.Storage — Run No Evil (U5)

**Files:**
- Create: `prototypes/button-test/source/tests/StorageLimitTest.mc`

- [ ] **Step 1: Écrire `source/tests/StorageLimitTest.mc`**

```monkeyc
using Toybox.Application.Storage;
using Toybox.System;
using Toybox.Test;

class StorageLimitTest extends Test.Logger {

    function initialize() {
        Test.Logger.initialize();
    }

    // Roundtrip basique (prérequis Phase 3)
    function test_set_get_roundtrip() as Void {
        var key = "bt_roundtrip";
        var data = {"me" : 12, "opponent" : 8, "label" : "score"};
        Storage.setValue(key, data);
        var read = Storage.getValue(key);
        Test.assertEqual(12, read["me"], "roundtrip me");
        Test.assertEqual(8, read["opponent"], "roundtrip opponent");
        Test.assertEqual("score", read["label"], "roundtrip label");
        Storage.removeItem(key);
    }

    // U5a : la limite documentée « 8 Ko par valeur » est-elle réelle ?
    function test_single_value_at_least_8k() as Void {
        var key = "bt_single_8k";
        var stored = false;
        try {
            Storage.setValue(key, repeatString("x", 8192));
            stored = true;
        } catch (e) {
            System.println("single 8K store failed: " + e.getErrorMessage());
        }
        Test.assertEqual(true, stored, "une valeur de 8192 caracteres doit tenir (doc : 8 Ko/valeur)");
        if (stored) { Storage.removeItem(key); }
    }

    // U5b : la limite documentée « 128 Ko au total » est-elle réelle ?
    function test_total_capacity_at_least_128k() as Void {
        var stored = 0;
        for (var i = 0; i < 160; i += 1) {
            try {
                Storage.setValue("bt_total_" + i, repeatString("y", 1024));
                stored += 1;
            } catch (e) {
                System.println("total probe stopped at " + stored + " Ko");
                break;
            }
        }
        System.println("[probe-storage] total stored = " + stored + " Ko (cible >= 128)");
        Test.assertEqual(true, stored >= 128, "le total doit accepter >= 128 Ko (obtenu " + stored + " Ko)");
        for (var j = 0; j < stored; j += 1) {
            Storage.removeItem("bt_total_" + j);
        }
    }

    // Sérialisation compacte (préfiguration §7.2 : tableaux positionnels)
    function test_compact_array_roundtrip() as Void {
        var key = "bt_compact";
        // [sequence, typeCode, set, scoreMe, scoreOpp]
        var event = [7, 0, 2, 11, 8];
        Storage.setValue(key, event);
        var read = Storage.getValue(key);
        Test.assertEqual(7, read[0], "compact sequence");
        Test.assertEqual(0, read[1], "compact typeCode");
        Test.assertEqual(2, read[2], "compact set");
        Test.assertEqual(11, read[3], "compact scoreMe");
        Test.assertEqual(8, read[4], "compact scoreOpp");
        Storage.removeItem(key);
    }

    function repeatString(c as String, n as Number) as String {
        var out = "";
        for (var i = 0; i < n; i += 1) {
            out += c;
        }
        return out;
    }
}
```

Note d'exécution : si `Test.assertEqual` ne résout pas (variation d'API Run No Evil), utiliser `self.assertEqual(expected, actual, message)` — les deux formes existent selon les versions du SDK ; la compile indiquera immédiatement la bonne.

- [ ] **Step 2: Compiler et exécuter les tests (fr55)**

```bash
cd prototypes/button-test
monkeyc -d fr55 -f monkey.jungle -o bin/tests-fr55.prg -y ~/keys/developer_key.der -t
monkeydo bin/tests-fr55.prg fr55 -t
```

Attendu dans la console simulateur : les 4 tests en `PASS`, résumé final sans `FAIL`. La sonde totale peut prendre quelques dizaines de secondes (concaténations) — normal.

- [ ] **Step 3: Exécuter aussi sur instinct2 et epix2pro51mm**

```bash
monkeyc -d instinct2 -f monkey.jungle -o bin/tests-instinct2.prg -y ~/keys/developer_key.der -t && monkeydo bin/tests-instinct2.prg instinct2 -t
monkeyc -d epix2pro51mm -f monkey.jungle -o bin/tests-epix2pro51mm.prg -y ~/keys/developer_key.der -t && monkeydo bin/tests-epix2pro51mm.prg epix2pro51mm -t
```

Attendu : vert sur les 3 profils ; noter le total Ko réel observé par device (peut différer de 128).

- [ ] **Step 4: Commit**

```bash
git add prototypes/button-test/source/tests/StorageLimitTest.mc
git commit -m "test(phase0): sondes Application.Storage Run No Evil (roundtrip, 8 Ko/valeur, 128 Ko total, tableau compact)"
```

---

### Task 9: Sideload réel sur epix Pro 51 mm + logs [USER ACTION]

**Files:** aucun (matériel)

- [ ] **Step 1: Copier le .prg sur la montre (U4)**

1. Brancher l'epix Pro 51 mm en USB-C (câble data). Vérifier que le volume **GARMIN** apparaît dans le Finder.
2. Copier `prototypes/button-test/bin/buttontest-epix2pro51mm.prg` vers **`GARMIN/APPS/`** (copier dans APPS même si la montre expose aussi APPS/DATA : comportement MTP confirmé par les forums, à prouver ici).
3. Éjecter le volume, débrancher.
4. Sur la montre : liste des apps/activités → **ButtonTest** doit apparaître. Le lancer : écran `BUTTON TEST / AUCUN / N=0`.

- [ ] **Step 2: Activer les logs (U6) et vérifier**

1. Rebrancher en USB. Créer le dossier/fichier de logs : `GARMIN/APPS/LOGS/BUTTONTEST-EPIX2PRO51MM.TXT` (nom attendu = nom du `.prg` sans extension, en majuscules ; si la montre écrit dans un autre nom, c'est la réponse à U6 — la noter).

```bash
mkdir -p /Volumes/GARMIN/APPS/LOGS
touch "/Volumes/GARMIN/APPS/LOGS/BUTTONTET-EPIX2PRO51MM.TXT"
```

(si le montage n'est pas `/Volumes/GARMIN`, adapter le chemin d'après le Finder)

2. Débrancher, lancer ButtonTest sur la montre, rebrancher, lire le fichier : les lignes `=== ButtonTest onStart ===` et `[probe] …` doivent y être.

- [ ] **Step 3: Checklist matérielle boutons (U1, U2 + critère de sortie Phase 0)**

Sur la montre, pour chaque action vérifier l'affichage identique au simulateur :

- [ ] START → `START`, compteur +1
- [ ] BACK → `BACK`, app ne quitte pas
- [ ] UP → `UP`
- [ ] DOWN → `DOWN`
- [ ] UP maintenu → `UP-LONG` puis MENU inline (**U1 levé : onMenu délivré sur epix ?**)
- [ ] MENU : DOWN/UP déplacent le curseur, BACK ferme, START sur QUITTER ferme l'app
- [ ] DOWN maintenu → noter le comportement système observé (hotkey musique ?) (**U2**)
- [ ] LIGHT → rétroéclairage uniquement, aucun effet score

- [ ] **Step 4: Test de remplacement de version**

Modifier `version="0.1.0"` → `"0.1.1"` dans `prototypes/button-test/manifest.xml`, rebuilder puis recopier :

```bash
cd prototypes/button-test
monkeyc -d epix2pro51mm -f monkey.jungle -o bin/buttontest-epix2pro51mm.prg -y ~/keys/developer_key.der -w -r
```

Copier à nouveau vers `GARMIN/APPS/`, éjecter : l'app sur la montre doit être remplacée sans doublon (même `id` manifest).

- [ ] **Step 5: Désinstallation**

Garmin Express → appareil epix Pro → Applications → ButtonTest → Supprimer. Vérifier la disparition de la liste d'apps sur la montre.

- [ ] **Step 6: Restaurer la version 0.1.0 et re-sideloader** (l'app reste sur la montre pour la suite des phases) :

```bash
cd prototypes/button-test
git checkout -- manifest.xml
monkeyc -d epix2pro51mm -f monkey.jungle -o bin/buttontest-epix2pro51mm.prg -y ~/keys/developer_key.der -w -r
```

puis recopier vers `GARMIN/APPS/`.

---

### Task 10: Synthèse des enseignements + mise à jour spec

**Files:**
- Create: `docs/superpowers/notes/2026-09-18-phase-0-findings.md`
- Modify: `docs/superpowers/specs/2026-09-18-badminton-score-design.md` (§17)

- [ ] **Step 1: Écrire `docs/superpowers/notes/2026-09-18-phase-0-findings.md`**

```markdown
# Phase 0 — Findings (2026-09-18)

## Environnement
- SDK installé : <version exacte>
- Java : <version exacte>
- Build OK sur : epix2pro42mm / epix2pro47mm / epix2pro51mm / fr55 / instinct2
- Tailles .prg : <copier ls -la bin/>

## Incertitudes levées
| # | Incertitude | Résultat | Preuve |
|---|---|---|---|
| U1 | onMenu (UP-long) sur les cibles | <délivré ou non, par device> | checklist T9 S3 |
| U2 | DOWN-long (hotkey) | <comportement observé> | checklist T9 S3 |
| U3 | Détection tactile getDeviceSettings | <champ présent/absent, valeur> | logs [probe] simu + matériel |
| U4 | MTP /GARMIN/APPS epix 51mm | <copie OK/KO, particularités> | T9 S1 |
| U5 | Limites réelles Application.Storage | <8 Ko/valeur ? total Ko par device> | Run No Evil T8 |
| U6 | Logs si nom de PRG | <fichier utilisé, roll-over> | T9 S2 |

## Résultats simulateur
<copier le tableau de phase-0-sim-results.md>

## Surprises / contraintes Garmin découvertes
<liste libre — alimente les phases suivantes>

## Décisions pour la Phase 1
<ex. : rien à changer au design / ajustements…>
```

- [ ] **Step 2: Pointer les résultats depuis la spec §17**

Dans `docs/superpowers/specs/2026-09-18-badminton-score-design.md`, juste après le tableau §17, ajouter :

```markdown
> **Résultats Phase 0 (U1-U6 levées) :** voir `docs/superpowers/notes/2026-09-18-phase-0-findings.md`.
```

- [ ] **Step 3: Commit + push**

```bash
git add docs/superpowers/notes/2026-09-18-phase-0-findings.md docs/superpowers/specs/2026-09-18-badminton-score-design.md
git commit -m "docs(phase0): synthèse enseignements + statut incertitudes U1-U6"
git push origin main
```

---

## Critère de sortie Phase 0 (rappel spec §16)

- Les 4 événements boutons reçus/affichés sur chaque cible : simulateur (fr55, instinct2, epix2pro51mm) ✅ Task 7 ; matériel réel epix 51 mm ✅ Task 9 Step 3 (FR55/Instinct 2 physiques : à refaire quand le matériel sera disponible).
- `.prg` installé / remplacé / désinstallé ✅ Task 9 Steps 1, 4, 5.
- Incertitudes U1-U6 consignées ✅ Task 10.
