# Atelier garmin-watchfaces — design

**Date :** 2026-09-22 · **Statut :** validé (brainstorming)
**Repo à créer :** `~/Documents/garmin-watchfaces` (GitHub)

## 1. Intention

Un **atelier de watch faces configurables premium** pour Connect IQ : des gabarits
à zones paramétrables (styles, complications, couleurs) au-dessus des mécanismes
natifs Garmin, avec des univers visuels forts (illustrations IA). Le store montre
que les cadrans, même payants, sont la catégorie au plus gros volume — le projet
capitalise là-dessus avec un moteur unique mutualisé.

## 2. Décisions de cadrage

| Décision | Choix |
|---|---|
| Périmètre | **Atelier multi-cadrans** (monorepo, publication store sérielle) |
| Familles v1 | **round-454x454** (epix2 Pro 51mm + FR965) · **round-416x416** (FR265) · **round-208x208** (FR55) = 3 familles / 4 devices |
| Concept | **Cadrans configurables premium** — zones = slots libres, catalogue complet Garmin |
| Illustrations | **Fonds IA générés** (prompts fournis par l'atelier) — **mécanique d'abord** (placeholders neutres) |
| Prix | **Payant d'entrée : 1,99 €** |

## 3. Architecture du repo

```
garmin-watchfaces/
├── shared/
│   ├── source/                     # moteur Monkey C compilé dans chaque gabarit
│   └── resources/                  # polices + chaînes communes
├── watchfaces/
│   └── <gabarit>/                  # un dossier = un listing store
│       ├── manifest.xml            # UUID propre, type watchface, prix 1,99 €
│       ├── monkey.jungle           # sources : gabarit + ../shared/
│       ├── resources/
│       │   ├── configs/watchface.xml   # styles + complications + couleurs (API 5.1+)
│       │   └── round-454x454/ | round-416x416/ | round-208x208/   # fonds IA (PNG)
│       └── source/                 # l'esthétique propre au gabarit
├── prompts/                        # prompts IA par gabarit × famille × univers
└── scripts/                        # build-release.sh, RNE, packaging store
```

Règles :
- **Un gabarit = un listing store** (UUID, prix, évolutions indépendantes)
- **Aucun réseau** dans les cadrans (autonomie + règles Garmin)
- Secrets de signature hors git (`.secrets/`, même paire `developer_key_personal.der` que badminton-score)

## 4. Le moteur partagé (`shared/source`)

- **`ThemeEngine`** : palette du gabarit (accent, fond, textes) centralisée — changer d'univers = un fichier
- **`ComplicationLayer`** : dessine une complication (label + valeur formatée : `8,4k`, `78%`, `62 bpm`) à une position, adapté au rond (évitement du cut)
- **Catalogue de complications** : mapping *type → source de données → format*, commun aux deux voies de configuration. Types officiels `Toybox.Complications` disponibles sur epix2 Pro (37) :
  - Santé : HEART_RATE, BODY_BATTERY, PULSE_OX, RESPIRATION_RATE, STRESS, RECOVERY_TIME
  - Activité : STEPS, CALORIES, FLOORS_CLIMBED, INTENSITY_MINUTES, WEEKLY_RUN_DISTANCE, WEEKLY_BIKE_DISTANCE
  - Environnement : ALTITUDE, SEA_LEVEL_PRESSURE, CURRENT_WEATHER, FORECAST_WEATHER, CURRENT_TEMPERATURE, HIGH_LOW_TEMPERATURE, SOLAR_INPUT, SUNRISE, SUNSET
  - Système : BATTERY, NOTIFICATION_COUNT, CALENDAR_EVENTS, DATE, WEEKDAY_MONTHDAY, TRAINING_STATUS, VO2, RACE_PREDICTOR…
- **Niveaux d'API** (pattern `has()` CIQ) :
  - **API 5.1+** (epix2 Pro, FR965) : configuration native via `<watchface-config>` — l'utilisateur choisit styles, complications (slots) et couleurs dans l'éditeur GCM / sur-montre
  - **API 4.x** (FR265) : données `Toybox.Complications` (4.2.0) mais pas l'éditeur → sélection des complications via **properties GCM**
  - **API 3.4** (FR55) : **aucun module Complications** → sources directes (`ActivityMonitor`, `Battery`, `Time.Gregorian`) + properties GCM (toggles afficher/masquer)
- **Économie batterie** : rendu 1 Hz, `onPartialUpdate` pour les zones qui changent seules, secondes optionnelles (style)
- **`UserSettings`** : respect du 12h/24h, unités, thème système (app review)

## 5. Le gabarit v1

- **Heure centrale** — 3 styles : `HH` / `HH:MM` / `HH:MM:SS`
- **Date** — jour de semaine + jour/mois
- **2 complications paramétrables** en bas (slots libres — catalogue ci-dessus)
- **Couleur d'accent** configurable (défaut vert `#2FE05C`, 4-5 propositions)
- **Placeholder** : fond abstrait neutre rendu en code (RNE) ; les fonds réels = PNG IA par famille
- **Univers** : la mécanique n'en dépend pas — les prompts des 3 univers (néon/cyber sport, sommets/crépuscule, chrono squelette) sont livrés ; décision esthétique au moment de générer les fonds

## 6. Build, RNE, Store, Tests

- **Build** : `WF=<nom> scripts/build-release.sh` (adapté de badminton-score : cibles par famille, clés partagées, sorties versionnées)
- **RNE** : *pas de famille activée sans RNE PASSED + capture* ; v1 = 4 devices / 3 familles
- **Store** : wizard payant 1,99 €, screenshots par famille, description « premium configurable »
- **Tests** : RNE simulateur par famille (filet principal) + tests unitaires moteur (formatage valeurs, 12h/24h, positionnement) via `Toybox.Test`

## 7. Hors périmètre v1

- Le pont avec BadScore (dernier score affiché sur le cadran) — voir ci-dessous
- Always-on display (AOD), cadran multi-univers en un seul listing
- Familles carrées (Venu) et 218x218 (FR165) — v2

## 8. Ouverts / à décider plus tard

- **Le pont BadScore** : une watch face CIQ ne partage pas le storage de l'app et a des quotas réseau stricts — toute idée de « score live sur cadran » est reportée ; le pont v1 = esthétique/cross-promo uniquement
- Le nom commercial du premier gabarit
