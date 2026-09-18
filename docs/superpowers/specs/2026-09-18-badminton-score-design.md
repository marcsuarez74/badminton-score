# Spec — Badminton Score pour Garmin Connect IQ

- **Date** : 2026-09-18
- **Statut** : Design validé par le propriétaire du projet (3 blocs approuvés)
- **Portée de ce document** : Phase 0 (validation technique) + livrables d'analyse préalables à l'implémentation. Les phases 1-7 auront chacune leur spec/plan détaillé au moment venu.
- **Usage** : application personnelle, sideload uniquement, **jamais** publiée sur le Garmin Connect IQ Store.

---

## 0. Décisions validées (résumé exécutif)

| # | Décision | Choix |
|---|----------|-------|
| D1 | Cibles | epix Pro (Gen 2) 42/47/51 mm (test matériel : 51 mm) + Forerunner 55 + Instinct 2 |
| D2 | FR45 | **Hors périmètre** (watch face uniquement, pas de sync — justification en §2.2) |
| D3 | Type d'app | **Un seul projet CIQ** — Watch App multi-products, `minApiLevel 3.4.0` |
| D4 | Moteur de score | Paramétrique `targetScore / winBy / cap / setsToWin`, event-sourcing, testable sans UI |
| D5 | Règles 21 pts | Premier à 21, écart 2, plafond 30 (règles BWF classiques) |
| D6 | Règles 15 pts | Premier à 15, écart 2, plafond 21 (style format expérimental BWF 2025, choix du propriétaire) |
| D6b | Règles 11 pts | Premier à 11, écart 2, **sans plafond** (cap = 0 — déuce sans limite, choix du propriétaire) |
| D7 | UNDO | Annule le dernier événement quel qu'il soit, sauf `MATCH_FINISHED` |
| D8 | Boutons | START=POINT MOI · BACK=POINT ADVERSAIRE · UP=UNDO · DOWN=CHANGEMENT DE SET (confirmé) · UP-long=menu inline · LIGHT réservé |
| D9 | Architecture UI | Mono-écran + états rendus inline (pas de pile `pushView` en match) |
| D10 | Sync | `makeWebRequest` → backend direct (pas d'app mobile obligatoire). App compagnon React Native = Phase 4b optionnelle |
| D11 | Source de vérité | La montre pendant le match ; le backend reflète l'état |
| D12 | Tests moteur | Framework officiel Run No Evil (`monkeyc -t`, `monkeydo -t`) |
| D13 | Emplacement dépôt | `~/Documents/badminton-score` |

---

## 1. Objectif et périmètre

Compter les points d'un match de badminton **pendant le match**, d'une pression de bouton, sans regarder longtemps la montre, sans téléphone obligatoire, avec synchronisation optionnelle vers un backend puis Twitch.

Périmètre fonctionnel :
- Écran de score lisible instantanément (set, score, sets gagnés, format, état du match).
- Formats configurables : 11, 15 et 21 points.
- 4 actions boutons : point moi, point adversaire, annuler, changement de set.
- Historique d'événements complet + undo réel (event-sourcing).
- Persistance locale (survit à fermeture/redémarrage).
- Synchronisation hors-ligne-tolérante vers un backend (file d'attente d'événements).
- Backend + temps réel + bot Twitch (phases ultérieures).

Hors périmètre de ce document (specs futures) : détail API backend, dashboard, bot Twitch, app mobile.

---

## 2. Cibles matérielles — analyse de compatibilité (livrables 1-4)

### 2.1 Tableau comparatif (sources officielles en §18)

| | epix Pro (Gen 2) | Forerunner 55 | Instinct 2 / Solar |
|---|---|---|---|
| Device ID SDK | `epix2pro42mm` / `epix2pro47mm` / `epix2pro51mm` | `fr55` | `instinct2` |
| Niveau API CIQ | 5.2 | 3.4 | 3.4 |
| Type d'app retenue | Watch App **786 432 o (768 Ko)** | Watch App **131 072 o (128 Ko)** | Watch App **98 304 o (96 Ko)** |
| Écran | Rond AMOLED 390/416/454× | Rond MIP 208×208, 8 couleurs | Semi-octogone MIP 176×176, **2 couleurs** |
| Tactile | Oui | Non | Non |
| Boutons | LIGHT, UP, DOWN, BACK, START | idem | idem |
| `Application.Storage` | Oui (API 2.4+) | Oui (API 2.4+) | Oui (API 2.4+) |
| `Toybox.Communications` | Oui (watch app) | Oui (watch app) | Oui (watch app) |
| Communication téléphone | `makeWebRequest`/`transmit` ✓ | ✓ | ✓ |

Contrainte mémoire dimensionnante : **Instinct 2 = 96 Ko** pour la watch app. Le scoreur (moteur + UI texte/formes) tient en quelques Ko ; l'historique d'événements est borné (§7). Les builds se valideront systématiquement sur `instinct2` (profil le plus contraint).

Appareil de test matériel réel : **epix Pro (Gen 2) 51 mm**. FR55 et Instinct 2 : à tester sur matériel dès disponibilité, simulateur sinon.

### 2.2 Justification FR45 hors périmètre (D2)

La Forerunner 45 ne supporte **que** le type d'app « Watch Face — 49 152 octets » (table App Types officielle de sa fiche device reference ; aucune ligne Watch App/Widget/Data Field). Conséquences en cascade, toutes vérifiées :

1. Pas de Watch App possible sur FR45 (le compilateur refuse `type="watch-app"` ciblé `fr45`).
2. Les watch faces CIQ ne peuvent pas `pushView` (doc `WatchUi.pushView` : exception si appelée depuis une watch face).
3. `Toybox.Communications` n'est pas autorisé au type Watch Face (matrice App_Types) → erreur *Symbol Not Found* au runtime → **aucune communication téléphone possible**, quel que soit le code.
4. `Toybox.FitContributor` (dernière piste théorique) : réservé aux Data Field/Glance/Watch App **et** FR45 absente de sa liste d'appareils supportés.

Le Bluetooth de la FR45 reste utilisé par le firmware Garmin (sync Garmin Connect des activités), mais n'est pas exposé aux apps CIQ sur ce modèle. La FR45 pourrait être réintégrée un jour comme **watch face de secours offline** (moteur partagé), jamais comme cible de la chaîne de sync.

### 2.3 Conséquences architecturales

- Les 3 cibles étant des Watch Apps → **un seul projet CIQ**, manifest multi-products, pas de double build watch-face/app.
- `minApiLevel 3.4.0` (fr55/instinct2) ; tout ce qui est ≥ 5.x (ex. `WatchUi.configureTouchEvents`) protégé par `has` checks.
- Ressources par famille d'écran : `round-208x208`, `round-390x390`, `round-416x416`, `round-454x454`, `semioctagon-176x176`.
- Palette : noir/blanc partout (garanti 2 couleurs Instinct 2) ; accents couleur uniquement si device AMOLED (détection au runtime).

### 2.4 Version SDK

- SDK courant au moment de l'analyse : **Connect IQ 9.2.0** (page SDK officielle, 2026-08-25). Toute version ≥ 7.4.3 est requise pour sideloader vers les firmware récents « System 8+ » (annonce officielle SDK 8.2) — le SDK courant couvre largement.
- Outil de développement : **extension VS Code « Monkey C »** (officiellement recommandée ; Eclipse abandonné). CLI disponibles : `monkeyc`, `monkeydo`, `connectiq`, `mdd`.

---

## 3. Boutons : événements réels et mapping (livrables 6-8)

### 3.1 Mécanique Connect IQ

- Les événements arrivent au délégué de la vue courante (`getInitialView` / `pushView`). Deux familles :
  - `WatchUi.InputDelegate` — bas niveau : `onKey(KeyEvent)` (API 1.0.0), `onKeyPressed`/`onKeyReleased` (1.1.2).
  - `WatchUi.BehaviorDelegate` (étend InputDelegate) — haut niveau : `onSelect` (KEY_ENTER), `onBack` (KEY_ESC), `onPreviousPage` (KEY_UP), `onNextPage` (KEY_DOWN), `onMenu` (KEY_MENU = UP maintenu). Officiellement recommandé pour la portabilité.
- **Choix : `BehaviorDelegate`** + retour `true` sur chaque handler (événement consommé, le système n'intervient pas).
- Constantes `WatchUi.Key` : `KEY_ENTER`, `KEY_ESC`, `KEY_UP`, `KEY_DOWN`, `KEY_MENU`, `KEY_LIGHT`, etc. (API 1.0.0 ; `EXTENDED_KEYS` ≥ 1.1.2 à couvrir par `has` check si utilisé — non utilisé ici).

### 3.2 Mapping final (validé, à prouver empiriquement en Phase 0)

| Bouton physique | Événement CIQ | Handler | Action |
|---|---|---|---|
| **START/STOP** | `KEY_ENTER` | `onSelect()` | **POINT MOI** — immédiat, sans confirmation |
| **BACK/LAP** | `KEY_ESC` | `onBack()` → `return true` | **POINT ADVERSAIRE** — immédiat ; ne quitte jamais l'app |
| **UP** (court) | `KEY_UP` | `onPreviousPage()` | **UNDO** |
| **DOWN** (court) | `KEY_DOWN` | `onNextPage()` | **CHANGEMENT DE SET** → état de confirmation inline (DOWN=OUI, BACK=NON) |
| **UP maintenu** | `KEY_MENU` | `onMenu()` | Menu inline : Quitter · Réinitialiser · Changer de format |
| **LIGHT** | jamais délivré | — | Réservé Garmin (rétroéclairage/assistance) |

Règles d'implémentation :
- Toute pression courte déclenche l'action ; aucune confirmation pour les points.
- **Pressions longues START et BACK : aucun effet** (pas de handler distinct utilisé ; aucun risque de point accidentel). `onKeyPressed`/`onKeyReleased` ne sont **pas** utilisés.
- Le seul chemin de sortie de l'app = menu inline (UP-long) → Quitter → `System.exit()`. Cohérent avec BACK détourné en point.
- Aucune utilisation de `View.setKeyToSelectableInteraction` (elle détournerait UP/DOWN vers la navigation de sélection).

### 3.3 Réservations système et longues pressions (constats officiels/forums)

- LIGHT court = rétroéclairage, **non interceptable** ; LIGHT très-long = power/assistance, non interceptable.
- UP maintenu = menu → délivré au délégué via `onMenu()` (nous le consommons).
- DOWN maintenu = hotkey système (ex. contrôles musique) — **non bloquable**, sans impact sur le score.
- Long-press BACK : aucun comportement système documenté de force-exit sur watch app ; le FR45/FR55/Instinct ne documentent pas de maintien BACK. Sans objet de toute façon : BACK retourne `true`.
- Cas particulier documenté : pendant un `Confirmation` système, BACK peut fermer l'app entière sur certains AMOLED (forum) → **nous n'utilisons pas** `ConfirmationDelegate`/`pushView` en match (états inline à la place).

### 3.4 Tactile (epix Pro uniquement, optionnel)

- Zones tap : moitié haute écran = POINT MOI, moitié basse = POINT ADVERSAIRE (`onTap`), activé seulement si l'appareil a un écran tactile (détection §6.3). Le scoring reste **100 % opérable aux boutons** sur toutes les cibles.
- Pas de zones tactiles pour UNDO/CHANGE_SET (risque d'accident > bénéfice).

---

## 4. Règles badminton implémentées (moteur)

### 4.1 Paramétrage (aucun chiffre codé en dur)

`MatchConfig = { targetScore, winBy, cap, setsToWin }` — `cap = 0` signifie **sans plafond**.

| Format | targetScore | winBy | cap | setsToWin | Origine |
|---|---|---|---|---|---|
| 21 points | 21 | 2 | 30 | 2 | Règles BWF classiques (rally point) |
| 15 points | 15 | 2 | 21 | 2 | Choix du propriétaire (style BWF expérimental 2025) |
| 11 points | 11 | 2 | 0 (aucun) | 2 | Choix du propriétaire |

### 4.2 Règles de fin de set

Le set est gagné dès que : `score ≥ targetScore ET (score − score_adversaire ≥ winBy OU (cap > 0 ET score ≥ cap))`.

Conséquences (testées unitairement) :
- 21 pts : 21-19 gagne ; 20-20 → déuce, il faut 2 d'écart ; 29-29 → le 30e point gagne (cap).
- 15 pts : 15-13 gagne ; 14-14 → déuce ; 20-20 → le 21e point gagne (cap).
- 11 pts : 11-9 gagne ; 10-10 → déuce, il faut 2 d'écart, **sans plafond** (le set peut durer indéfiniment, ex. 16-14).
- Score maximal affichable : `cap` (30 / 21) ou non borné en mode 11 points (l'affichage réserve la place).

### 4.3 Fin de match

`setsWon[joueur] == setsToWin` → `MATCH_FINISHED` (2 sets gagnés → best-of-3).

### 4.4 Changement de set (manuel, DOWN)

1. État de confirmation inline : « TERMINER SET n ? score — [DOWN]=OUI [BACK]=NON ».
2. Confirmé → événement `SET_CHANGED` : le vainqueur courant du set n'est pas recalculé (changement manuel assumé), set suivant 0-0, `SET n+1`.
3. Si le set courant est déjà terminé automatiquement (§4.2), l'écran `SET_RESULT` s'affiche avant tout et DOWN = « set suivant » (même transition, événement `SET_FINISHED` déjà enregistré).

### 4.5 Décision UNDO (D7 — point laissé ouvert par la spec initiale)

- UNDO annule **le dernier événement de l'historique, quel qu'il soit** : `POINT_*`, `SET_FINISHED` (reprendre le set terminé), `SET_CHANGED` (revenir au set précédent).
- Exception : **`MATCH_FINISHED` ne s'annule pas** (protection du résultat final ; le menu inline propose « Réinitialiser » pour repartir de zéro).
- Implémentation : event-sourcing complet — l'état est la replay de l'historique, l'undo retire le dernier événement et rejoue. Impossible de descendre sous 0-0 (l'historique est vide → UNDO sans effet).
- Justification sûreté : CHANGE_SET passe déjà par une confirmation ; SET_FINISHED est réversible en rejouant ; l'utilisateur ne peut pas « détruire » un match par accident.

---

## 5. UX (mono-écran + états inline)

États de `MatchView` (un seul écran, rendu conditionnel) :

```
SCORE (défaut)          CONFIRM_SET             SET_RESULT              MATCH_FINISHED
┌──────────────┐       ┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│    SET 2     │       │TERMINER SET ?│        │SET 1 TERMINÉ │        │ MATCH TERMINÉ│
│              │       │   15 - 12    │        │ MOI  21 - 18 │        │              │
│    11 - 8    │       │              │        │              │        │  2 - 1       │
│  MOI    LUI  │       │DOWN=OUI      │        │ Sets : 1 - 0 │        │ MOI gagne    │
│              │       │BACK=NON      │        │DOWN=SET SUIV.│        │DOWN=NOUVEAU  │
│21 PTS SETS1-0│       │              │        │              │        │              │
└──────────────┘       └──────────────┘        └──────────────┘        └──────────────┘
```

- **SCORE** : `SET n` / gros chiffres (~40 % de l'écran) / `MOI LUI` / `21 POINTS` / `SETS 1-0`. Mise à jour instantanée, zéro animation.
- **Démarrage** : si match en cours persisté → retour direct sur SCORE. Sinon écran **Setup** (format 11/15/21 : UP/DOWN, START valider) — mémorisé pour les matchs suivants.
- **Menu inline** (UP-long) : liste verticale (DOWN/UP naviguent, START valide, BACK ferme le menu) : `Reprendre`, `Changer de format`, `Réinitialiser le match`, `Quitter`.
- Adaptations par device : layout identique, noir/blanc partout ; accents couleur + zones tap sur epix Pro uniquement.

---

## 6. Architecture de l'app montre (livrable 11)

```
watch/connect-iq/
├── manifest.xml              # watch-app ; minApiVersion 3.4.0 ; products: epix2pro42/47/51mm, fr55, instinct2
│                             # permissions: Communications
├── monkey.jungle             # base + sections par device (ressources)
├── resources/
│   ├── base/                 # layout agnostique, launcher icons
│   ├── round-208x208/ round-390x390/ round-416x416/ round-454x454/ semioctagon-176x176/
├── source/
│   ├── App.mc                # AppBase : getInitialView, onStart (restauration), onStop (sauvegarde)
│   ├── engine/               # PUR (aucun import UI/Graphics) — testable Run No Evil
│   │   ├── MatchConfig.mc    # targetScore/winBy/cap/setsToWin + presets 11/15/21
│   │   ├── ScoreEvent.mc     # types, séquence, id, timestamps
│   │   ├── ScoreEngine.mc    # mutations + replay + undo
│   │   └── Rules.mc          # fin de set / fin de match
│   ├── ui/
│   │   ├── MatchView.mc      # rendu des 4 états + menu inline + setup
│   │   ├── MatchDelegate.mc  # BehaviorDelegate (onSelect/onBack/onPreviousPage/onNextPage/onMenu)
│   │   ├── SetupView.mc
│   │   └── Theme.mc          # couleurs par capacité device
│   ├── services/
│   │   ├── StorageService.mc # Application.Storage (clé versionnée)
│   │   ├── SyncService.mc    # makeWebRequest, file pendingEvents, backoff
│   │   └── DeviceInfo.mc     # DeviceCapabilities
│   └── utils/Logger.mc
└── tests/
    ├── ScoreEngineTest.mc  RulesTest.mc  PersistenceTest.mc  EventProtocolTest.mc
```

### 6.1 DeviceCapabilities (`DeviceInfo.mc`)

Construit **exclusivement** sur des APIs vérifiées : `System.getDeviceSettings()` (screenWidth, screenHeight, shape) et `has` checks sur les symboles ≥ 3.4/5.x (ex. `WatchUi has :configureTouchEvents`). La détection tactile exacte (champ réel de DeviceSettings sur chaque firmware) fait partie des vérifications Phase 0 (§17) — **rien à inventer ici**.

### 6.2 Compatibilité moteur ↔ UI

Le moteur ne connaît ni Toybox.Graphics ni WatchUi. L'UI observe le moteur via son état (getter) et redessine. Aucune logique de score côté UI.

---

## 7. Modèle de données & persistance (livrable 17)

### 7.1 Entités

```monkeyc
// MatchConfig
{ targetScore: Int, winBy: Int, cap: Int /* 0 = sans plafond */, setsToWin: Int }

// ScoreEvent
{
  id: String,           // "<matchId>:<sequence>" — unique, idempotent
  type: Enum,           // POINT_ME | POINT_OPPONENT | UNDO | SET_CHANGED | SET_FINISHED | MATCH_FINISHED
  matchId: String,      // généré à la création du match
  set: Int,             // numéro de set au moment de l'événement
  previousScore: {me, opponent},
  newScore: {me, opponent},
  timestamp: Long,      // System.getTimer() / horloge système
  sequence: Int         // croissant, sans trou, depuis 1
}
```

### 7.2 Persistance (`Application.Storage`)

- Disponible sur les 3 cibles (API 2.4+ ; notre minApi 3.4). Limites documentées : **8 Ko par valeur**, 128 Ko au total.
- **Découpage en plusieurs clés** (une valeur de 8 Ko max chacune) :
  - `match_meta_v1` → `{ schemaVersion, matchId, config, currentSet, setsWon, status, lastSequence }` (état dérivé, quelques octets)
  - `match_events_v1.<n>` → lots d'événements (~25-30 par clé, sérialisation compacte : tableaux positionnels plutôt que JSON verbeux)
  - `match_pending_v1.<n>` → événements non acquittés (même format)
- Écriture **à chaque mutation** (setValue synchrone) + `onStop`. Volume : ~150-250 o/événement compacté → un match de ~120 points tient dans 4-6 clés, marge confortable.
- **Restauration** : lecture de `match_meta_v1` (état dérivé stocké) + événements ; **pas de replay complet nécessaire** (l'undo n'utilise que le(s) dernier(s) événement(s), la sync n'utilise que les événements non acquittés). L'historique est borné à **200 événements** ; au-delà, les plus anciens sont purgés par lots (jamais le dernier événement, jamais un événement non acquitté).
- **Overflow `pendingEvents`** : si la file dépasse la capacité (match complet hors-ligne), réémission de **l'historique complet** par lots à la reconnexion — l'idempotence backend (`matchId:sequence` unique) rend la réémission sans risque. Aucun point n'est jamais perdu.
- Survit à : fermeture app, redémarrage app, redémarrage montre.

---

## 8. Protocole d'événements (livrable 14)

### 8.1 Envoi (montre → backend)

```
POST https://<backend>/api/matches/{matchId}/events
Headers: Authorization: Bearer <token device>
Body:    { deviceId, matchId, events: [ ScoreEvent, ... ] }   // batch ≤ 5, ~150-250 o/event
```

Réponse ACK :
```
200 { matchId, lastAcceptedSequence: Int }
```

- `lastAcceptedSequence` → retrait de la file des événements `sequence ≤ lastAcceptedSequence`.
- Déclenchements : après chaque point (asynchrone, jamais bloquant), et à chaque lancement d'app (flush).

### 8.2 Idempotence et ordre

- `event.id = matchId:sequence` ; backend : contrainte unique `(match_id, sequence)` → doublons ignorés, hors-ordre trié par `sequence`.
- `sequence` croît sans trou depuis 1 (également comptée sur UNDO/SET_* — tout est événement).

### 8.3 Lecture d'état (clients : dashboard, bot)

```
GET https://<backend>/api/matches/{matchId}/state
→ { matchId, config, status, currentSet, score, setsWon, lastSequence }
```

---

## 9. Stratégie offline & synchronisation (livrables 15-16)

1. **Scoring 100 % local** : un point est appliqué et persisté avant toute tentative réseau. Le téléphone n'est jamais requis.
2. **File d'attente** : chaque événement rejoint `pendingEvents` ; envoi best-effort.
3. **Erreurs BLE/HTTP** (`-2 BLE_HOST_TIMEOUT`, `-104 BLE_CONNECTION_UNAVAILABLE`, `-300 NETWORK_REQUEST_TIMED_OUT`, `-402` réponse trop grande) → backoff exponentiel (10 s → 2 min), file **jamais vidée sur erreur** ; reprise automatique au prochain déclenchement. Cas documenté « callback jamais appelé » (GCM endormi) → timeout applicatif côté montre et réémission (idempotence = sans risque).
4. **Reprise après déconnexion** : au lancement de l'app, si `pendingEvents` non vide → flush immédiat.
5. **Conflits** : la montre est source de vérité (D11). Le backend n'envoie jamais d'état vers la montre en 4a. `GET_MATCH_STATE` est à destination des clients (dashboard/bot) uniquement. Nouveau `matchId` par match → aucune collision inter-matchs. Si la montre redémarre un match neuf, c'est un nouveau `matchId` — l'historique distant du match précédent est conservé.
6. Débit BLE ~400-800 o/s (doc Garmin) → batch ≤ 5 événements, ≥ 5 s entre requêtes.

---

## 10. Sécurité (livrable de la spec d'origine, §24)

- **Aucun secret dans le repo** : URL backend + token device configurés via les **settings CIQ de l'app** (éditables dans Garmin Connect / Garmin Express — mécanisme officiel `App.Properties`/settings).
- Backend : auth par token device (généré côté backend, un par appareil), validation stricte (types d'événements connus, `sequence` croissante par `matchId`, cohérence des scores), rate-limit par device.
- Twitch : credentials (OAuth) uniquement dans le backend (variables d'environnement). Jamais dans la montre, jamais dans une app mobile, jamais dans le repo.
- Repo : `.gitignore` couvrant `bin/`, clés `.der/.pem`, `.env`, dossiers SDK.

---

## 11. Build, sideload, debug (livrables 9-10) — procédures réelles

### 11.1 Installation environnement (macOS)

1. **Java 11+** (Java 8 présent → installer Temurin 17) — requis par la doc Monkey C CLI/VS Code.
2. **SDK Manager** : `connectiq-sdk-manager.dmg` (page SDK officielle) → login compte Garmin → installer le SDK courant (9.2.0) → onglet **Devices** : télécharger `fr55`, `instinct2`, `epix2pro42mm/47mm/51mm`.
3. PATH CLI : `export PATH=$PATH:$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")/bin`
4. **VS Code + extension Monkey C** ; générer/pointage de la clé : Settings → *Monkey C: Developer Key Path*.

### 11.2 Clé développeur (une fois, hors repo)

```
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

Format **DER** requis par `monkeyc -y`. Toute build (même perso/sideload) est signée avec cette clé. La conserver (nécessaire pour signer des mises à jour).

### 11.3 Boucle de développement

```
# simulateur
connectiq
monkeyc -d fr55 -f monkey.jungle -o bin/badminton-fr55.prg -y ~/keys/developer_key.der -w -r
monkeydo bin/badminton-fr55.prg fr55
# tests moteur (simulateur)
monkeyc -d fr55 -f monkey.jungle -o bin/tests.prg -y key.der -t && monkeydo bin/tests.prg fr55 -t
# ou tout via VS Code : Run (simu, breakpoints) / Monkey C: Build for Device (PRG)
```

Répéter par device : `-d fr55`, `-d instinct2`, `-d epix2pro51mm` (+ 42/47 pour la CI).

### 11.4 Sideload (sans Store, les 3 cibles)

1. Connecter la montre en USB (câble data FR55 ; USB-C epix Pro/Instinct 2).
2. Copier `badminton-<device>.prg` dans **`/GARMIN/APPS/`** (sur les montres MTP modernes, PRG copié quand même à cet emplacement — comportement confirmé sur les forums développeurs ; à vérifier empiriquement au premier sideload, §17).
3. Débrancher ; l'app apparaît dans la liste d'activités/apps.
- **Remplacer une version** : recopier le nouveau `.prg` (même UUID manifest) — l'ancienne version est remplacée.
- **Désinstaller** : Garmin Express (méthode recommandée par le staff Garmin sur les forums) ; store app on-device en alternative si disponible.
- **Jamais de publication Store** ; option officielle « Beta Apps » du dashboard Garmin documentée en secours (permet settings via Garmin Connect), non requise.

### 11.5 Debug sur matériel

- `System.println` → fichier **`/GARMIN/APPS/LOGS/<NOM_DU_PRG>.TXT`** (créer le fichier vide manuellement ; roll-over ~5 Ko → .BAK).
- Crash logs : `/GARMIN/APPS/LOGS/CIQ_LOG.YAML` (ou `CIQ_LOG.TXT` sur anciens firmware).
- Debugger complet (breakpoints) : **simulateur uniquement** (limite officielle) ; sur matériel = logs.

---

## 12. Architecture mobile (livrable 12) — Phase 4b, optionnelle

Reportée (D10). Si activée plus tard : app React Native + TypeScript recevant les événements via le pont **Connect IQ Mobile SDK** (SDK natif Garmin iOS/Android + bridge RN communautaire — pas de support RN officiel à ce jour), affichage score/sets/connexion, buffer d'événements, relay vers backend. Ne devient jamais nécessaire au scoring (contrainte de la spec d'origine conservée). Spécification détaillée à ce moment-là.

---

## 13. Architecture backend (livrable 13) — Phases 5-6, aperçu

- **Stack** : Node.js + TypeScript + Fastify + PostgreSQL + WebSocket (ws).
- **Modules** : `matches`, `events`, `devices` (auth token), `sync`, `realtime` (WS), `twitch`.
- **Tables** : `matches` (id, config, status), `events` (id texte `matchId:sequence` UNIQUE, type, payload JSONB, sequence, timestamp), `devices` (deviceId, token_hash).
- **Règles** : validation stricte à l'ingestion, idempotence par contrainte d'unicité, `GET_MATCH_STATE` calculé depuis les événements, broadcast WS sur chaque événement accepté.
- Spécification détaillée dans le cycle de design de la Phase 5.

---

## 14. Twitch bot (livrable 18) — Phase 7, aperçu

- `tmi.js`, connecté avec OAuth backend (env), lit les événements du backend (WS), **jamais** de lien direct avec la montre.
- Commandes : `!score` → `🏸 Moi 11 - 8 Lui | Set 2 | Match en 21 points` ; `!badminton`, `!match`, `!sets` (variantes : score final, sets gagnés).
- Annonce automatique à chaque événement `POINT_*` : `🏸 Point pour Moi ! 12 - 8`.
- Secrets uniquement côté backend.

---

## 15. Stratégie de tests (livrable 19)

### 15.1 Moteur — Run No Evil (officiel, tourne dans le simulateur)

| Cas | Entrée → action | Attendu |
|---|---|---|
| Score initial | new(21) | 0-0, set 1, sets 0-0 |
| Point moi | POINT_ME | 1-0 |
| Point adversaire | POINT_OPPONENT | 1-1 |
| Undo simple | POINT_ME puis UNDO | retour état précédent exact |
| Undo multi | 3 points puis 3× UNDO | 0-0, pas de négatif |
| Undo vide | UNDO sur historique vide | sans effet |
| Déuce 21 | 20-20 → POINT_ME | 21-20, set **non** fini |
| Cap 21 pts | 29-29 → POINT_ME (config 21) | 30-29, SET_FINISHED |
| Écart 15 pts | 14-14 → POINT_ME | 15-14, set non fini |
| Déuce 11 pts | 10-10 → POINT_ME | 11-10, set non fini |
| Sans cap (11 pts) | déuce prolongée 10-10 → 16-14 | SET_FINISHED à 16-14 (aucun plafond) |
| Cap 15 pts | 20-20 → POINT_ME (config 15) | 21-20, SET_FINISHED |
| Set fini normal | 21-19 (config 21) | SET_FINISHED, sets 1-0 |
| Changement de set | confirmé | set suivant 0-0, SET_CHANGED |
| Undo SET_FINISHED | UNDO après fin auto | set repris, sets recalculés |
| Undo SET_CHANGED | UNDO après changement confirmé | retour au set précédent |
| Fin de match | sets 2-0 | MATCH_FINISHED, UNDO inopérant |
| Persistance | save → new engine → restore | état identique (état dérivé + événements, clés multiples < 8 Ko) |
| Événements | chaque mutation | id unique, séquence sans trou, previous/new cohérents |

### 15.2 Checklist matérielle (à cocher sur le matériel possédé)

Pour chaque cible (epix Pro 51 mm ; FR55 ; Instinct 2 quand disponibles) :
- [ ] Les 4 boutons en pression courte déclenchent les 4 actions (prototype Phase 0 puis app)
- [ ] Maintiens longs (START, BACK, DOWN) : aucun point accidentel ; UP-long ouvre le menu inline
- [ ] LIGHT : rétroéclairage uniquement, aucun effet score
- [ ] Confirmation changement de set : DOWN=OUI / BACK=NON, aucun point marqué pendant la confirmation
- [ ] Fermeture forcée de l'app pendant un match → relance → score exact retrouvé
- [ ] Redémarrage complet de la montre → reprise du match
- [ ] Affichage correct (rond 3 tailles / semi-octogone 2 couleurs), lisible à bout de bras
- [ ] Sideload : installation, remplacement de version, désinstallation via Garmin Express
- [ ] Logs `/GARMIN/APPS/LOGS/` opérationnels
- [ ] (Phases 4a+) sync via Garmin Connect Mobile : points envoyés, file vidée après reconnexion, sans perte

---

## 16. Plan de développement (livrable 20)

| Phase | Contenu | Critère de sortie |
|---|---|---|
| **0 — Validation technique** | Install SDK + clé ; projet minimal ; prototype « button test » (affiche l'événement reçu) ; sideload réel sur epix 51 mm (+ FR55/Instinct si matériel) ; test persistence/storage ; test logs | Les 4 événements reçus/affichés sur chaque cible ; .prg installé/remplacé/désinstallé |
| 1 — Scoring minimal | Moteur de base (points, affichage) + mapping boutons sur les 3 profils simu | Un match complet compté aux boutons sur epix Pro |
| 2 — Moteur complet | Règles §4, sets, undo, événements + tests Run No Evil | Suite de tests verte (cas §15.1) |
| 3 — Persistance | StorageService, reprise, pendingEvents | Kill/restart sans perte ; cas persistance verts |
| 4a — Communication | SyncService makeWebRequest → backend stub | Événements reçus et acquittés côté stub |
| 5 — Backend | API + PostgreSQL + WS (spec dédiée) | Dashboard/CLI voit le score live |
| 6 — Temps réel | Broadcast WS complet | Clients à jour à chaque point |
| 7 — Twitch | Bot + commandes | `!score` répond ; annonces automatiques |
| 4b (option) | App mobile compagnon (spec dédiée) | — |

Chaque phase : petites étapes, code compilable à chaque commit, tests, documentation des contraintes Garmin rencontrées.

---

## 17. Incertitudes à lever en Phase 0 (rien à inventer)

| # | Incertitude | Méthode de levée |
|---|---|---|
| U1 | Livraison réelle de `onMenu` (UP-long) sur fr55/instinct2 | Prototype boutons sur matériel |
| U2 | Comportement cosmétique DOWN-long (hotkey) sur les 3 cibles | Prototype sur matériel |
| U3 | Champ exact de détection tactile dans `System.getDeviceSettings()` (existe-t-il un flag isTouchScreen ?) | Inspection profils SDK + `has` checks + doc API au moment du code |
| U4 | Visibilité/écriture de `/GARMIN/APPS` en MTP sur epix Pro 51 mm et Instinct 2 | Premier sideload réel |
| U5 | Limites réelles du `Application.Storage` par device (les 8 Ko/128 Ko sont les valeurs documentées globales) | Test de charge en simu + vérif sur matériel |
| U6 | Comportement du fichier de logs si le PRG est renommé | Test sideload |
| U7 | Fiabilité GCM (garanties de callback makeWebRequest) sur les 3 cibles | Test Phase 4a, timeouts applicatifs prévus |

---

## 18. Sources officielles (vérifiées le 2026-09-18)

**Garmin developer (docs et API refs)** :
- Compatible devices (API levels, écrans) : https://developer.garmin.com/connect-iq/compatible-devices/
- Device reference (tables App Types par appareil) : `…/connect-iq/articles/device-reference/{fr45,fr55,instinct2,epix2pro42mm,epix2pro47mm,epix2pro51mm}.html`
- App types & règle « Symbol Not Found » : https://developer.garmin.com/connect-iq/articles/connect-iq-basics/App_Types.html
- API `Toybox.Communications` (App Types + Supported Devices) : https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html
- API `Toybox.FitContributor` : https://developer.garmin.com/connect-iq/api-docs/Toybox/FitContributor.html
- API `Toybox.WatchUi` (Key enum, pushView, configureTouchEvents) : https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi.html
- `BehaviorDelegate` / `KeyEvent` / `InputDelegate` : https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/{BehaviorDelegate,KeyEvent,InputDelegate}.html
- `Application.Storage` : https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html
- Persisting Data : https://developer.garmin.com/connect-iq/articles/core-topics/Persisting_Data.html
- Input handling : https://developer.garmin.com/connect-iq/articles/core-topics/Input_Handling.html
- Manifest & permissions : https://developer.garmin.com/connect-iq/articles/core-topics/Manifest_and_Permissions.html
- Debugging : https://developer.garmin.com/connect-iq/articles/core-topics/Debugging.html
- SDK & SDK Manager : https://developer.garmin.com/connect-iq/sdk/
- Compiler options (`-y` clé, `-t` tests) : https://developer.garmin.com/connect-iq/monkey-c/compiler-options/
- Monkey C command line setup (clé openssl, PATH) : https://developer.garmin.com/connect-iq/reference-guides/monkey-c-command-line-setup/
- UX guidelines (mapping boutons 5-touches) : https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Designing_Workflows_and_Interactions.html
- Beta Apps (distribution privée officielle, non utilisée) : https://developer.garmin.com/connect-iq/core-topics/beta-apps/

**Garmin developer forum (preuves de terrain)** :
- LIGHT/DOWN-long non bloquables, LIGHT jamais délivré : forums.garmin.com/developer/connect-iq/f/discussion/428083 et /405694
- `onBack` interceptable (return true) / sortie via System.exit : /215681, /363568
- Sideload = copie `.prg` vers `/GARMIN/APPS` (toutes montres) : /419051 ; instruction FR55/FR45 par flowstate : /281696
- Désinstallation sideload via Garmin Express (staff) : i/bug-reports/sideloaded-watch-faces-cannot-be-removed-from-forerunner-255
- makeWebRequest réel sur FR55 (repo + manifest `fr55` + permission Communications) : /435465 ; sur Instinct 2S : /307542
- Fiabilité GCM (BLE_HOST_TIMEOUT, callbacks) : /306706 ; quirk BACK dans ConfirmationDelegate sur AMOLED : /362301
- Fuite mémoire réponses > 2 Ko : i/bug-reports/communications-web-request-memory-leak

**Règles badminton** : format 21 points = règles BWF en vigueur (rally point, écart 2, plafond 30). Format 15 points = choix explicite du propriétaire (D6), à recouper avec le format expérimental BWF 2025 en Phase 2 si besoin.

---

## 19. Journal des décisions (ADR condensé)

- **ADR-001 — FR45 hors périmètre** : watch-face-only + pas de Communications + pas de FitContributor → sync impossible et UI contrainte à un cadran. Coût/risque > valeur. Réintégrable un jour comme watch face offline.
- **ADR-002 — Un seul projet CIQ multi-products** : les 3 cibles sont des watch apps ; minApi 3.4.0 ; `has` checks pour 5.x.
- **ADR-003 — Event-sourcing complet** : tout est événement (points, sets, undo, fin) → undo trivial, persistance = replay, protocole sync naturellement idempotent.
- **ADR-004 — BehaviorDelegate + return true partout** : portabilité officielle, BACK détourné sans risque, sortie contrôlée par menu inline.
- **ADR-005 — Mono-écran + états inline** : zéro pushView en match (évite le quirk BACK/Confirmation AMOLED), latence minimale, testable.
- **ADR-006 — makeWebRequest direct (4a) avant app compagnon (4b)** : atteindre backend/Twitch sans dépendre d'un bridge RN non officiel ; la montre reste la source de vérité.
- **ADR-007 — Moteur Monkey C unique, non dupliqué en TypeScript** : le backend reflète les événements sans réimplémenter les règles (pas de divergence possible). Les tests moteur tournent via Run No Evil dans le simulateur.
