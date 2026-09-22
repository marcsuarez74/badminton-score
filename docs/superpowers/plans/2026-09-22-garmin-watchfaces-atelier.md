# Atelier garmin-watchfaces — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Créer l'atelier `garmin-watchfaces` (monorepo CIQ multi-cadrans) et livrer le gabarit v1 : une watch face configurable premium, publiée à 1,99 € sur 4 devices / 3 familles.

**Architecture:** Monorepo à sous-projets Connect IQ — un moteur partagé (`shared/source`) compilé dans chaque gabarit via `monkey.jungle` multi-source ; chaque gabarit = un listing store indépendant. Config native `<watchface-config>` (API 5.1+) avec dégradation properties GCM (4.x) et layout fixe (3.4).

**Tech Stack:** Monkey C (Connect IQ SDK 9.2.0 macOS), simulateur Garmin, GitHub.

**Références clés:**
- SDK : `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/` (`$SDK` ci-dessous)
- Sample officiel : `$SDK/samples/ConfigurableWatchFace/` (pattern `ComplicationDrawable`, `watchface-config`)
- Spéc : `docs/superpowers/specs/2026-09-22-garmin-watchfaces-atelier-design.md` (copiée dans le nouveau repo en Task 1)
- Scripts de référence : `~/Documents/badminton-score/scripts/build-release.sh`
- Clé de signature : `~/keys/developer_key_personal.der`
- Devices locaux : `epix2pro51mm`, `fr965`, `fr265`, `fr55`

---

### Task 1: Créer le repo et la structure de l'atelier

**Files:**
- Create: `~/Documents/garmin-watchfaces/.gitignore`
- Create: `~/Documents/garmin-watchfaces/README.md`
- Create: `~/Documents/garmin-watchfaces/docs/` (copie de la spec + de ce plan)

- [ ] **Step 1: Initialiser le repo**

```bash
mkdir -p ~/Documents/garmin-watchfaces && cd ~/Documents/garmin-watchfaces
git init
mkdir -p shared/source shared/resources watchfaces prompts scripts docs
```

- [ ] **Step 2: Écrire .gitignore**

```gitignore
.secrets/
*.prg
*.iq
bin/
.superpowers/
.DS_Store
```

- [ ] **Step 3: Écrire README.md**

```markdown
# garmin-watchfaces

Atelier de watch faces configurables premium pour Connect IQ.

- `shared/` — moteur partagé (complications, thèmes, économie batterie)
- `watchfaces/` — un dossier par gabarit (= un listing store)
- `prompts/` — prompts IA pour les fonds illustrés
- `scripts/` — build, RNE, packaging

Spéc : docs/superpowers/specs/2026-09-22-garmin-watchfaces-atelier-design.md
```

- [ ] **Step 4: Copier la spec et le plan**

```bash
cp ~/Documents/badminton-score/docs/superpowers/specs/2026-09-22-garmin-watchfaces-atelier-design.md ~/Documents/garmin-watchfaces/docs/superpowers/specs/ 2>/dev/null || (mkdir -p ~/Documents/garmin-watchfaces/docs/superpowers/specs ~/Documents/garmin-watchfaces/docs/superpowers/plans && cp ~/Documents/badminton-score/docs/superpowers/specs/2026-09-22-garmin-watchfaces-atelier-design.md ~/Documents/garmin-watchfaces/docs/superpowers/specs/ && cp ~/Documents/badminton-score/docs/superpowers/plans/2026-09-22-garmin-watchfaces-atelier.md ~/Documents/garmin-watchfaces/docs/superpowers/plans/)
```

- [ ] **Step 5: Commit + repo GitHub**

```bash
cd ~/Documents/garmin-watchfaces
git add -A && git commit -m "chore: atelier garmin-watchfaces — squelette + spec + plan"
gh repo create garmin-watchfaces --private --source . --push
```

Expected: repo créé et poussé sur GitHub.

---

### Task 2: Gabarit v1 minimal — compile et tourne sur simulateur

**Files:**
- Create: `watchfaces/gabarit-un/manifest.xml`
- Create: `watchfaces/gabarit-un/monkey.jungle`
- Create: `watchfaces/gabarit-un/resources/strings/strings.xml`
- Create: `watchfaces/gabarit-un/resources/drawables/drawables.xml` + `launcher_icon.png`
- Create: `watchfaces/gabarit-un/source/GabaritUnApp.mc`, `GabaritUnView.mc`, `GabaritUnDelegate.mc`

- [ ] **Step 1: Générer l'UUID de l'app**

```bash
uuidgen | tr -d '-' | tr 'a-z' 'A-Z'
```

Noter la valeur (32 hex majuscules) — l'utiliser en Step 2.

- [ ] **Step 2: Écrire manifest.xml**

```xml
<iq:manifest version="3" xmlns:iq="http://www.garmin.com/xml/connectiq">
    <iq:application id="UUID_GENERE" version="0.1.0" minSdkVersion="3.4.0" minApiLevel="3.4.0" entry="GabaritUnApp" type="watchface" name="@Strings.AppName" launcherIcon="@Drawables.LauncherIcon">
        <iq:products>
            <iq:product id="epix2pro51mm"/>
            <iq:product id="fr965"/>
            <iq:product id="fr265"/>
            <iq:product id="fr55"/>
        </iq:products>
        <iq:permissions/>
        <iq:languages>
            <iq:language>eng</iq:language>
        </iq:languages>
    </iq:application>
</iq:manifest>
```

- [ ] **Step 3: Écrire monkey.jungle (avec le moteur partagé dès maintenant)**

```
project.manifest = manifest.xml
base.sourcePath = source;../../shared/source
base.resourcePath = resources;../../shared/resources
```

Créer aussi `shared/source/` et `shared/resources/` vides (le build exige qu'ils existent) :

```bash
mkdir -p ../../shared/source ../../shared/resources
```

- [ ] **Step 4: Écrire strings.xml**

```xml
<resources>
    <strings>
        <string id="AppName">BadFace</string>
    </strings>
</resources>
```

- [ ] **Step 5: Écrire drawables.xml et copier un launcher icon**

```xml
<resources>
    <drawables>
        <bitmap id="LauncherIcon" filename="launcher_icon.png"/>
    </drawables>
</resources>
```

```bash
cp "$SDK/samples/ConfigurableWatchFace/resources/drawables/launcher_icon.png" resources/drawables/
```

(`$SDK` = le chemin SDK du header)

- [ ] **Step 6: Écrire GabaritUnApp.mc**

```monkeyc
using Toybox.Application;
using Toybox.WatchUi;

class GabaritUnApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }
    function getInitialView() as [WatchUi.View, WatchUi.InputDelegate] {
        return [new GabaritUnView(), new GabaritUnDelegate()];
    }
}
```

- [ ] **Step 7: Écrire GabaritUnDelegate.mc**

```monkeyc
using Toybox.WatchUi;

class GabaritUnDelegate extends WatchUi.WatchFaceDelegate {
    function initialize() {
        WatchFaceDelegate.initialize();
    }
}
```

- [ ] **Step 8: Écrire GabaritUnView.mc (heure + date centrées)**

```monkeyc
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.UserSettings;
using Toybox.WatchUi;

class GabaritUnView extends WatchUi.WatchFace {
    function initialize() {
        WatchFace.initialize();
    }
    function onLayout(dc as Dc) as Void {
    }
    function onUpdate(dc as Dc) as Void {
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var heure = heureFormat(now);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 - 40, heure, Graphics.FONT_NUMBER_LARGE, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 + 30, Lang.format("$1$ $2$", [now.day_of_week, now.day.format("%d")]), Graphics.FONT_TINY, Graphics.TEXT_JUSTIFY_CENTER);
    }
    private function heureFormat(now as Lang.Dictionary) as Lang.String {
        var hour = now.hour;
        if (!UserSettings.is24Hour()) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        return Lang.format("$1$:$2$", [hour.format("%02d"), now.min.format("%02d")]);
    }
}
```

- [ ] **Step 9: Compiler (typecheck strict) pour les 4 devices**

```bash
cd watchfaces/gabarit-un
for d in epix2pro51mm fr965 fr265 fr55; do
  "$SDK/bin/monkeyc" -f monkey.jungle -d $d -o bin/gabarit-un-$d.prg -l 3 -w
done
```

Expected: 4 fichiers .prg, aucune erreur.

- [ ] **Step 10: Lancer sur simulateur (epix2pro51mm) et vérifier**

```bash
"$SDK/bin/monkeydo" bin/gabarit-un-epix2pro51mm.prg epix2pro51mm
```

Expected: la montre simulée affiche l'heure (HH:MM) et la date, rafraîchie chaque minute. Quitter le simulateur.

- [ ] **Step 11: Commit**

```bash
git add -A && git commit -m "feat(gabarit-un): squelette watch face — heure + date sur 4 devices"
```

---

### Task 3: Fond placeholder + esthétique « univers » en code

**Files:**
- Modify: `watchfaces/gabarit-un/source/GabaritUnView.mc`
- Create: `shared/source/ThemeEngine.mc`

- [ ] **Step 1: Écrire ThemeEngine.mc (palette centralisée)**

```monkeyc
using Toybox.Graphics;

module ThemeEngine {
    const ACCENT = 0x2FE05C;        // vert BadScore
    const BG_TOP = 0x06251A;        // vert très sombre
    const BG_BOTTOM = 0x010503;     // noir
    const TEXT_MAIN = 0xEAFFF3;     // blanc verdâtre
    const TEXT_DIM = 0x5A6A60;      // gris verdâtre

    // Fond dégradé (bandes verticales — placeholder univers néon)
    function drawBackground(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var steps = 8;
        for (var i = 0; i < steps; i++) {
            var ratio = i * 1.0 / (steps - 1);
            var r = (BG_TOP >> 16 & 0xFF) + ((BG_BOTTOM >> 16 & 0xFF) - (BG_TOP >> 16 & 0xFF)) * ratio;
            var g = (BG_TOP >> 8 & 0xFF) + ((BG_BOTTOM >> 8 & 0xFF) - (BG_TOP >> 8 & 0xFF)) * ratio;
            var b = (BG_TOP & 0xFF) + ((BG_BOTTOM & 0xFF) - (BG_TOP & 0xFF)) * ratio;
            dc.setColor(r.toNumber() << 16 | g.toNumber() << 8 | b.toNumber(), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, h * i / steps, dc.getWidth(), h / steps + 1);
        }
    }
}
```

- [ ] **Step 2: Adapter GabaritUnView.onUpdate (fond ThemeEngine + heure accent)**

Dans `GabaritUnView.mc`, remplacer `dc.clear()` par `ThemeEngine.drawBackground(dc)` et changer la couleur de l'heure :

```monkeyc
    function onUpdate(dc as Dc) as Void {
        ThemeEngine.drawBackground(dc);
        var w = dc.getWidth();
        var h = dc.getHeight();
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        dc.setColor(ThemeEngine.ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 - 40, heureFormat(now), Graphics.FONT_NUMBER_LARGE, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(ThemeEngine.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 + 30, Lang.format("$1$ $2$", [now.day_of_week, now.day.format("%d")]), Graphics.FONT_TINY, Graphics.TEXT_JUSTIFY_CENTER);
    }
```

- [ ] **Step 3: Compiler + vérifier sur simulateur (les 3 familles)**

```bash
cd watchfaces/gabarit-un
for d in epix2pro51mm fr265 fr55; do
  "$SDK/bin/monkeyc" -f monkey.jungle -d $d -o bin/gabarit-un-$d.prg -l 3 -w
done
"$SDK/bin/monkeydo" bin/gabarit-un-epix2pro51mm.prg epix2pro51mm
```

Expected: fond dégradé sombre, heure verte lisible sur les 3 formes d'écran.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(moteur): ThemeEngine + fond placeholder univers néon"
```

---

### Task 4: ComplicationLayer — catalogue + rendu par slot

**Files:**
- Create: `shared/source/Catalogue.mc` (types → sources → formats)
- Create: `shared/source/ComplicationLayer.mc` (rendu d'un slot)
- Modify: `watchfaces/gabarit-un/source/GabaritUnView.mc` (2 slots en bas)

- [ ] **Step 1: Écrire Catalogue.mc (mapping type → valeur → format)**

```monkeyc
using Toybox.ActivityMonitor;
using Toybox.Lang;
using Toybox.Sensor;
using Toybox.System;

module Catalogue {
    const STEPS = 1;
    const CALORIES = 2;
    const FLOORS = 3;
    const BATTERY = 4;
    const HEART_RATE = 5;
    const BODY_BATTERY = 6;

    // La valeur brute pour un type, ou null si non disponible.
    function valeur(type as Lang.Number) as Lang.Object or Null {
        if (type == STEPS) { return ActivityMonitor.getInfo().steps; }
        if (type == CALORIES) { return ActivityMonitor.getInfo().calories; }
        if (type == FLOORS) { return ActivityMonitor.getInfo().floorsClimbed; }
        if (type == BATTERY) { return System.getSystemStats().battery; }
        if (type == HEART_RATE) {
            var h = ActivityMonitor.getHeartRateHistory(1, true);
            if (h.size() > 0 && h[0] != null) { return h[0].heartRate; }
            return null;
        }
        if (type == BODY_BATTERY) {
            if (has(Sensor, "getBodyBatteryHistory")) {
                var b = Sensor.getBodyBatteryHistory(1);
                if (b.size() > 0 && b[0] != null) { return b[0].value; }
            }
            return null;
        }
        return null;
    }

    // La valeur formatée pour l'affichage.
    function formate(type as Lang.Number, valeur as Lang.Object or Null) as Lang.String or Null {
        if (valeur == null) { return "--"; }
        var n = valeur.toNumber();
        if (type == BATTERY) { return n + "%"; }
        if (type == STEPS && n >= 1000) {
            var k = n / 1000.0;
            return Lang.format("$1$, $2$k", [k.toNumber().format("%d"), (k * 10 % 10).toNumber().format("%d")]);
        }
        return n.format("%d");
    }
}
```

- [ ] **Step 2: Écrire ComplicationLayer.mc (rendu d'un slot)**

```monkeyc
using Toybox.Graphics;
using Toybox.Lang;

module ComplicationLayer {
    // Dessine label (valeur) + titre en un point du bas de l'écran.
    function dessine(dc as Graphics.Dc, x as Lang.Number, type as Lang.Number, accent as Lang.Number) as Void {
        var valeur = Catalogue.formate(type, Catalogue.valeur(type));
        var titre = titreDe(type);
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, h - h / 6, valeur, Graphics.FONT_MEDIUM, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(ThemeEngine.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, h - h / 6 + 26, titre, Graphics.FONT_TINY, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function titreDe(type as Lang.Number) as Lang.String {
        if (type == Catalogue.STEPS) { return "PAS"; }
        if (type == Catalogue.CALORIES) { return "KCAL"; }
        if (type == Catalogue.FLOORS) { return "ETG"; }
        if (type == Catalogue.BATTERY) { return "BATT"; }
        if (type == Catalogue.HEART_RATE) { return "FC"; }
        if (type == Catalogue.BODY_BATTERY) { return "ENRG"; }
        return "";
    }
}
```

- [ ] **Step 3: Ajouter les 2 slots dans GabaritUnView.onUpdate (avant les textes de date pour l'ordre de dessin)**

```monkeyc
        ComplicationLayer.dessine(dc, w / 4, Catalogue.STEPS, ThemeEngine.ACCENT);
        ComplicationLayer.dessine(dc, 3 * w / 4, Catalogue.BATTERY, ThemeEngine.ACCENT);
```

- [ ] **Step 4: Tests unitaires (Toybox.Test) — Create `shared/source/CatalogueTest.mc`**

```monkeyc
using Toybox.Lang;
using Toybox.Test;

(:test)
function testFormateStepsK(logger as Lang.Object) as Void {
    Test.assertEqual("8, 4k", Catalogue.formate(Catalogue.STEPS, 8400), "8400 pas -> 8,4k");
}

(:test)
function testFormateBatterie(logger as Lang.Object) as Void {
    Test.assertEqual("78%", Catalogue.formate(Catalogue.BATTERY, 78), "batterie en %");
}

(:test)
function testFormateValeurNulle(logger as Lang.Object) as Void {
    Test.assertEqual("--", Catalogue.formate(Catalogue.HEART_RATE, null), "FC indisponible -> --");
}

(:test)
function testFormateSimple(logger as Lang.Object) as Void {
    Test.assertEqual("62", Catalogue.formate(Catalogue.HEART_RATE, 62), "FC entière");
}
```

- [ ] **Step 5: Compiler avec tests + exécuter dans le simulateur**

```bash
cd watchfaces/gabarit-un
"$SDK/bin/monkeyc" -f monkey.jungle -d epix2pro51mm -o bin/gabarit-un-test.prg -l 3 -t -w
"$SDK/bin/monkeydo" bin/gabarit-un-test.prg epix2pro51mm
```

Expected: dans la console du simulateur, les 4 tests PASS (le simulateur exécute les `(:test)` au lancement). Quitter.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(moteur): catalogue complications + ComplicationLayer + tests unitaires"
```

---

### Task 5: Configuration native (API 5.1+) — styles + complications éditables

**Files:**
- Create: `watchfaces/gabarit-un/resources/configs/watchface.xml`
- Create: `watchfaces/gabarit-un/source/CadranDrawable.mc` (adapté de `ComplicationDrawable` du sample)
- Modify: `watchfaces/gabarit-un/source/GabaritUnView.mc`

- [ ] **Step 1: Écrire configs/watchface.xml (l'éditeur natif)**

```xml
<resources xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://developer.garmin.com/downloads/connect-iq/resources.xsd">
    <watchface-config>
        <styles>
            <style id="1" label="@Strings.styleHHMM"/>
            <style id="2" label="@Strings.styleHHMMSS" default="true"/>
        </styles>
        <accentColors allowAny="true"/>
        <data>
            <complication id="1" allowAny="true"/>
            <complication id="2" allowAny="true"/>
        </data>
        <dataColors>
            <color label="@Strings.colorVert" default="true">0x2FE05C</color>
            <color label="@Strings.colorBlanc">0xFFFFFF</color>
            <color label="@Strings.colorCyan">0x00E5FF</color>
            <color label="@Strings.colorOrange">0xFF8A3D</color>
        </dataColors>
    </watchface-config>
</resources>
```

Compléter strings.xml :

```xml
<string id="styleHHMM">Heure HH:MM</string>
<string id="styleHHMMSS">Heure HH:MM:SS</string>
<string id="colorVert">Vert</string>
<string id="colorBlanc">Blanc</string>
<string id="colorCyan">Cyan</string>
<string id="colorOrange">Orange</string>
```

- [ ] **Step 2: Copier le ComplicationDrawable officiel du sample et le renommer**

```bash
cp "$SDK/samples/ConfigurableWatchFace/source/ComplicationDrawable.mc" watchfaces/gabarit-un/source/CadranDrawable.mc
```

Puis renommer dans le fichier : `class ComplicationDrawable` → `class CadranDrawable` (et la référence interne). C'est le drawable natif qui lit la complication choisie par l'utilisateur (id 1 / 2) et la rend centrée.

- [ ] **Step 3: Brancher les drawables dans GabaritUnView (onLayout + onUpdate)**

Ajouter dans `GabaritUnView.mc` :

```monkeyc
    function onLayout(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        setLayout([
            new CadranDrawable({ :identifier => "complication1", :locX => w / 4 - 50, :locY => h - h / 6, :width => 100, :height => 40 }),
            new CadranDrawable({ :identifier => "complication2", :locX => 3 * w / 4 - 50, :locY => h - h / 6, :width => 100, :height => 40 })
        ]);
    }
```

Et dans `onUpdate`, après le fond, appeler `Drawable.draw(dc)` pour chaque enfant (le pattern du sample `ConfigurationWatchFaceView`) — les slots natifs remplacent les slots du catalogue quand le device les supporte. Conserver les slots Catalogue comme rendu de secours si `WatchUi.Complications` n'est pas disponible.

- [ ] **Step 4: Compiler + vérifier l'éditeur sur epix2pro51mm**

```bash
cd watchfaces/gabarit-un
"$SDK/bin/monkeyc" -f monkey.jungle -d epix2pro51mm -o bin/gabarit-un-epix2pro51mm.prg -l 3 -w
"$SDK/bin/monkeydo" bin/gabarit-un-epix2pro51mm.prg epix2pro51mm
```

Expected: compile sans erreur ; sur simulateur, la montre propose la page de configuration du cadran (choix du style, des complications, de la couleur).

- [ ] **Step 5: Vérifier que FR55 et FR265 compilent toujours (config ignorée ou sans éditeur)**

```bash
"$SDK/bin/monkeyc" -f monkey.jungle -d fr55 -o bin/gabarit-un-fr55.prg -l 3 -w
"$SDK/bin/monkeyc" -f monkey.jungle -d fr265 -o bin/gabarit-un-fr265.prg -l 3 -w
```

Expected: compile. Si le SDK 3.4 rejette `<watchface-config>` (erreur de parse resource), déplacer `configs/watchface.xml` dans un dossier qualifié par device (`resources-epix2pro51mm/`, `resources-fr965/`) et relancer les 4 builds.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(gabarit-un): éditeur natif (styles/complications/couleurs) sur API 5.1+"
```

---

### Task 6: Mode dégradé — properties GCM (4.x et 3.4)

**Files:**
- Create: `watchfaces/gabarit-un/resources/settings.xml`
- Modify: `watchfaces/gabarit-un/source/GabaritUnView.mc`

- [ ] **Step 1: Écrire settings.xml (choix des complications en GCM pour les vieux devices)**

```xml
<properties>
    <property id="slot1" type="number">
        <setting-property-key>@Strings.slot1</setting-property-key>
        <setting-config>
            <configList>
                <listEntry value="1">@Strings.slotSteps</listEntry>
                <listEntry value="2">@Strings.slotKcal</listEntry>
                <listEntry value="3">@Strings.slotEtages</listEntry>
                <listEntry value="5">@Strings.slotFc</listEntry>
                <listEntry value="6">@Strings.slotBodyBattery</listEntry>
            </configList>
        </setting-config>
    </property>
    <property id="slot2" type="number">
        <setting-property-key>@Strings.slot2</setting-property-key>
        <setting-config>
            <configList>
                <listEntry value="4" default="true">@Strings.slotBatterie</listEntry>
                <listEntry value="1">@Strings.slotSteps</listEntry>
                <listEntry value="5">@Strings.slotFc</listEntry>
            </configList>
        </setting-config>
    </property>
</properties>
<settings>
    <setting propertyKey="@Properties.slot1" title="@Strings.slot1Title">
        <setting-config>
            <configList>
                <listEntry value="1">@Strings.slotSteps</listEntry>
                <listEntry value="2">@Strings.slotKcal</listEntry>
                <listEntry value="3">@Strings.slotEtages</listEntry>
                <listEntry value="5">@Strings.slotFc</listEntry>
                <listEntry value="6">@Strings.slotBodyBattery</listEntry>
            </configList>
        </setting-config>
    </setting>
    <setting propertyKey="@Properties.slot2" title="@Strings.slot2Title">
        <setting-config>
            <configList>
                <listEntry value="4" default="true">@Strings.slotBatterie</listEntry>
                <listEntry value="1">@Strings.slotSteps</listEntry>
                <listEntry value="5">@Strings.slotFc</listEntry>
            </configList>
        </setting-config>
    </setting>
</settings>
```

Compléter strings.xml : `slot1`/`slot2` (« Complication gauche/droite »), `slot1Title`/`slot2Title`, `slotSteps`/`slotKcal`/`slotEtages`/`slotBatterie`/`slotFc`/`slotBodyBattery` (« Pas », « Calories », « Étages », « Batterie », « Fréquence cardiaque », « Énergie corps »).

- [ ] **Step 2: Lire les properties dans GabaritUnView**

```monkeyc
using Toybox.Application.Properties;

// dans GabaritUnView :
    private var mSlot1 = Catalogue.STEPS;
    private var mSlot2 = Catalogue.BATTERY;
    function onShow() as Void {
        mSlot1 = Properties.getValue("slot1").toNumber();
        mSlot2 = Properties.getValue("slot2").toNumber();
    }
```

Sur les devices API 5.1+, utiliser les valeurs de l'éditeur natif ; sinon les slots Catalogue lisent les properties. La règle : **une seule source de vérité par device** — `has(WatchUi, "Complications")` décide.

- [ ] **Step 3: Compiler + vérifier sur simulateur FR55 (layout fixe avec toggles GCM)**

```bash
cd watchfaces/gabarit-un
"$SDK/bin/monkeyc" -f monkey.jungle -d fr55 -o bin/gabarit-un-fr55.prg -l 3 -w
"$SDK/bin/monkeydo" bin/gabarit-un-fr55.prg fr55
```

Expected: compile + affiche ; dans GCM (ou simulateur → File → Settings), le changement de slot se propage après re-validation des réglages.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(gabarit-un): mode dégradé — complications via properties GCM (4.x/3.4)"
```

---

### Task 7: Script de build

**Files:**
- Create: `scripts/build-release.sh`

- [ ] **Step 1: Écrire build-release.sh (adapté de badminton-score)**

```bash
#!/bin/bash
# build-release.sh — construit les .prg/.iq d'un gabarit pour tous les devices.
# Usage: WF=gabarit-un scripts/build-release.sh [--store]
set -euo pipefail

SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
WF="${WF:?WF=<nom-gabarit> requis}"
DEVICES=(epix2pro51mm fr965 fr265 fr55)
KEY="$HOME/keys/developer_key_personal.der"
OUT="watchfaces/$WF/bin/v-$(grep -o 'version="[^"]*"' watchfaces/$WF/manifest.xml | head -1 | cut -d'"' -f2)"
STORE="${1:-}"

mkdir -p "$OUT"
for d in "${DEVICES[@]}"; do
  echo "== $d =="
  if [ "$STORE" = "--store" ]; then
    "$SDK/bin/monkeyc" -f "watchfaces/$WF/monkey.jungle" -d "$d" -e -y "$KEY" -o "$OUT/$WF-$d.iq" -l 3 -w
  else
    "$SDK/bin/monkeyc" -f "watchfaces/$WF/monkey.jungle" -d "$d" -o "$OUT/$WF-$d.prg" -l 3 -w
  fi
done
echo "Sorties dans $OUT"
```

- [ ] **Step 2: Tester le script (sideloads)**

```bash
chmod +x scripts/build-release.sh
WF=gabarit-un scripts/build-release.sh
```

Expected: 4 .prg dans `watchfaces/gabarit-un/bin/v-0.1.0/`.

- [ ] **Step 3: Commit**

```bash
git add scripts/build-release.sh && git commit -m "feat(scripts): build-release.sh multi-familles (sideloads + store)"
```

---

### Task 8: RNE — recette par famille + captures

**Files:**
- Create: `docs/rne/gabarit-un/` (captures)

- [ ] **Step 1: RNE epix2pro51mm (rond 454)**

```bash
"$SDK/bin/monkeydo" watchfaces/gabarit-un/bin/v-0.1.0/gabarit-un-epix2pro51mm.prg epix2pro51mm
```

Vérifier + capturer (simulateur → Screen Capture) : heure lisible, fond sans artefact de dégradé, 2 complications avec valeurs, date correcte, pas de chevauchement heure/complications. Sauver la capture dans `docs/rne/gabarit-un/epix2pro51mm.png`.

- [ ] **Step 2: RNE fr965 (rond 454)** — mêmes vérifications, `fr965.prg` → `fr965.png`.

- [ ] **Step 3: RNE fr265 (rond 416)** — mêmes vérifications + l'éditeur GCM absent (les properties s'appliquent) → `fr265.png`.

- [ ] **Step 4: RNE fr55 (rond 208)** — vérifier la lisibilité à petite taille (l'heure ne doit pas toucher les complications) → `fr55.png`.

- [ ] **Step 5: Règle d'entrée — aucune famille sans PASSED**

Si une famille échoue : corriger le layout (positions relatives), re-compiler, re-tester. Ne pas avancer tant que les 4 ne sont pas PASSED.

- [ ] **Step 6: Commit**

```bash
git add docs/rne && git commit -m "test(rne): gabarit-un PASSED sur epix2pro51mm, fr965, fr265, fr55"
```

---

### Task 9: Packaging store + publication

**Files:**
- Create: `beta-store/gabarit-un/v-0.1.0/` (.iq, gitigné)

- [ ] **Step 1: Construire les packages store**

```bash
WF=gabarit-un scripts/build-release.sh --store
```

Expected: 4 .iq signés dans `watchfaces/gabarit-un/bin/v-0.1.0/` (le script sort dans `bin/`, vérifier le chemin affiché). Les .iq sont gitignés par défaut — déplacer les .iq à publier dans `beta-store/gabarit-un/v-0.1.0/` si on veut les garder, hors git ou dans le repo selon le choix.

- [ ] **Step 2: Préparer les assets store (dans `prompts/` et `docs/store/`)**

- Description du listing (anglais + français) : cadrans configurables premium, zones au choix, catalogue de complications
- Screenshots par device (captures RNE)
- Prompts IA pour les fonds réels (3 univers : néon/cyber sport, sommets/crépuscule, chrono squelette) — un fichier par univers, avec les variantes 454/416/208 et la consigne de cadrage pour écrans ronds

- [ ] **Step 3: Publication wizard (manuel, compte dev Garmin)**

1. Wizard Connect IQ → Add Application → Upload `gabarit-un-epix2pro51mm.iq` (+ les 3 autres)
2. **Prix : 1,99 €** (payant d'entrée — décision du 22/09)
3. Devices : epix2 Pro 51mm, FR965, FR265, FR55
4. Description + screenshots + capture vidéo si demandée
5. Soumettre en **beta gratuite d'abord** pour la review Garmin si le wizard l'exige, puis basculer payant — OU publier direct payant si proposé

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore(store): préparation publication gabarit-un (1,99 €)"
```

---

## Récap des filets de test

| Filet | Quand | Commande |
|---|---|---|
| Typecheck strict | chaque compilation | `monkeyc ... -l 3 -w` |
| Tests unitaires | Task 4 (et après chaque modif du moteur) | `monkeyc -t` + simulateur |
| RNE visuel | Task 8, et à chaque changement de layout | `monkeydo` + captures |
| Batterie | après Task 5 (simulateur : mode économie) | contrôle visuel du draw rate |
