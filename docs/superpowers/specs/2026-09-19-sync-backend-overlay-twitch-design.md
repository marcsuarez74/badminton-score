# Spec complémentaire — Synchronisation, Backend, Overlay OBS & Twitch

- **Date** : 2026-09-19
- **Statut** : conception approuvée en séance (connectivité vérifiée sur docs officielles + SDK local) — document à relire par le propriétaire
- **Portée** : complément technique à `2026-09-18-badminton-score-design.md` (ci-après « spec principale »), qui reste la source de vérité pour tout ce qui n'est pas explicitement amendé ici. Couvre les phases 4a/5/6/7 de la spec principale.
- **Usage** : personnel, **un seul streameur** (le propriétaire), hébergement **Supabase free tier (~0 €)**, URL overlay en sous-domaine fourni.
- **Convention de traçabilité** : chaque fait est marqué `[SPEC]` (spec principale), `[DOC]` (doc officielle, lien en §20), `[SDK]` (api.debug.xml/api.mir local SDK 9.2.0), `[PROPO]` (proposition d'architecture de ce document), `[À TESTER]` (hypothèse à confirmer sur matériel).

---

## 0. Amendements explicites à la spec principale

Toutes les décisions existantes restent valables **sauf** les trois points ci-dessous, amendés en connaissance de cause :

| # | Décision amendée | Ancien libellé | Nouveau libellé | Justification |
|---|---|---|---|---|
| A1 | **D10 (sync)** | « `makeWebRequest` → backend direct (pas d'app mobile obligatoire) » | « `makeWebRequest` → relais **Garmin Connect Mobile** (téléphone appairé, app installée) → backend direct. **Aucune app compagnon CUSTOM obligatoire** (4b reste optionnelle) » | Chaîne officielle : la montre n'a pas d'accès Internet direct ; GCM est le proxy BLE→Internet (« JSON REST Requests via Mobile Proxy ») [DOC core topic HTTPS ; DOC forum 422118]. Impact scoring : **aucun** (offline-first inchangé, contrainte « jamais de téléphone obligatoire pour le score local » préservée). |
| A2 | **§13 (stack backend)** | Node.js + TypeScript + Fastify + PostgreSQL + WebSocket (ws), auto-hébergé | **Supabase managé** : PostgreSQL + Edge Functions (ingestion) + Realtime (WSS). PostgreSQL conservé ; Fastify remplacé par 1 Edge Function ; module `ws` remplacé par Supabase Realtime | Comparatif §6 de cette spec. Le contrat d'API §8 de la spec principale est **conservé** (voir §13 ici). |
| A3 | **§13 (état) + §7.1 (newScore)** | « `GET_MATCH_STATE` calculé depuis les événements » ; `ScoreEvent` contient `newScore` | L'état diffusé (`match_state`) est le **snapshot fourni par la montre** (source de vérité, ADR-007), recalculé par personne. Le payload de sync reprend le format plat de la montre `[type, arg, sequence, ts, prevMe, prevOpp]` — **sans** `newScore` ni n° de set par événement (non stockés par le moteur Phase 2-3, aucun consommateur n'en a besoin ; le snapshot porte l'état courant) | Éviter de réimplémenter les règles côté backend (violerait ADR-007) ; le format plat existe déjà dans la montre. Exemple payload du présent document remplace l'exemple illustratif de la mission. |

Une conséquence d'implémentation (détail moteur, pas une décision de spec) : le `matchId` généré Phase 2 (ms depuis boot) n'est pas globalement unique entre redémarrages → **génération à randomiser** au startMatch (voir §4.2), à faire en Phase 4a.

---

## 1. Architecture

```
                         ┌──────────────┐
                         │    Twitch    │
                         └──────▲───────┘
                                │ RTMP (stream)
                         ┌──────┴───────┐
                         │     OBS      │
                         │ BrowserSource│   configuré UNE fois, jamais retouché par match
                         └──────▲───────┘
                                │ HTTPS (page statique) + WSS (realtime)
                         ┌──────┴────────────┐
                         │ Overlay Web       │
                         │ GitHub Pages      │   page statique + supabase-js (clé publique)
                         └──────▲────────────┘
                                │ Realtime (Postgres Changes) + GET initial (REST)
                         ┌──────┴────────────┐
                         │ Supabase          │
                         │  Edge Function    │   POST /sync — auth device key, validation, idempotence
                         │  PostgreSQL       │   matches / events / match_state / devices
                         │  Realtime         │   WSS Postgres Changes (RLS SELECT public)
                         └──────▲────────────┘
                                │ HTTPS POST (réponse < 200 o)
                         ┌──────┴────────────┐
                         │ Téléphone         │
                         │ Garmin Connect M. │   relais BLE→Internet — requis pour la sync (A1)
                         └──────▲────────────┘
                                │ BLE 400-800 o/s [DOC FAQ REST]
                         ┌──────┴───────┐
                         │ Garmin Watch │   source de vérité, offline-first
                         │ (epix/fr55/  │
                         │  instinct2)  │
                         └──────────────┘
```

| Composant | Rôle | Logique métier de score ? |
|---|---|---|
| Montre (existant + `SyncService`) | Scoring, persistance, file d'attente, envoi | **Oui (unique détenteur)** [SPEC D11, ADR-007] |
| Garmin Connect Mobile | Relais BLE→Internet, rien d'autre | Non |
| Supabase PostgreSQL | Stockage événements + snapshot | Non (contraintes d'intégrité seulement) |
| Edge Function `sync` | Auth device key, validation forme, insert idempotent, ACK | Non (ADR-007) |
| Supabase Realtime | Fan-out WSS vers overlay | Non |
| Overlay (GitHub Pages) | Rendu score, abonnement realtime | Non (lecture seule) |
| OBS | Composition vidéo (caméra + overlay) | Non |
| Twitch | Diffusion (niveau 1) ; API/bot plus tard | Non |
| Bot (Phase G) | Chat/annonces, lit le realtime | Non (affiche seulement) |

Fonctionne sans Twitch, sans OBS, sans backend, sans téléphone : le scoring local ne dépend d'aucun d'entre eux [SPEC D10-D11].

## 2. Flux de données

### 2.1 Flux nominal (un point → overlay)

1. **Montre** : bouton → moteur applique + persiste + journal (Phase 3) → pointeur pending `pf` avance côté envoie [~0 ms, local]
2. **SyncService** : batch (≤ 5 events + snapshot) → `makeWebRequest` → BLE → GCM → HTTPS [BLE ~0,5-1 s + requête ~0,2-0,5 s]
3. **Edge Function** : auth key → validation → upsert `events` (ignore-duplicates) + upsert `match_state` (snapshot) → ACK `{matchId, lastAcceptedSequence}` [~50 ms ; cold start 0,3-1 s sur la 1re requête]
4. **Realtime** Postgres Changes sur `match_state` → overlay [p95 ≈ 228 ms, bench officiel Supabase [DOC]]
5. **Overlay** : re-render

**Latence cible end-to-end : ≤ 5 s p95** (typique 1,5-4 s). Les points rapides sont regroupés en batch (≤ 5, ≥ 5 s entre requêtes [SPEC §9]) → l'overlay rattrape par bonds ; acceptable pour un overlay TV. **Latence affichée en direct ≠ latence de la montre** : la montre reste instantanée (contrainte originelle).

### 2.2 Flux secondaires

| Flux | Comportement |
|---|---|
| Offline / backend down | File locale jamais vidée ; scoring inchangé ; rattrapage au retour |
| Reprise après redémarrage app | Flush immédiat de `pf..lastSequence` au lancement [SPEC §9.4] |
| Réception dans le désordre | DB trie par `sequence` ; le snapshot `match_state` est toujours l'état courant de la montre → l'overlay est juste même si les events arrivent en désordre |
| Doublons | Contrainte unique `(match_id, sequence)` + `ignore-duplicates` → sans effet |
| Match terminé | Event `MATCH_FINISHED` (type 5) + snapshot `status=match_finished` → overlay fige le résultat |
| Nouveau match | Nouveau matchId → nouvelle ligne `match_state` active → l'overlay bascule automatiquement (§8.4) |
| Match jamais synchronisé | N'existe pas côté backend (création paresseuse au 1er POST) — aucun artefact |
| Bot (Phase G) | Lit les INSERT sur `events` (realtime) → annonces chat |

## 3. Connectivité Garmin — analyse vérifiée

Réponses aux 10 questions posées (sources : SDK local 9.2.0 + docs officielles + forums en §20) :

1. **Une app CIQ peut-elle faire une requête HTTP ?** Oui : `Toybox.Communications.makeWebRequest(url, parameters, options, responseCallback)` [SDK bin/api.mir:10143]. HTTPS obligatoire (`SECURE_CONNECTION_REQUIRED=-1001` sinon) [SDK]. Methods GET/PUT/POST/DELETE ; Content-Type JSON ou URL-encoded ; responseType JSON/TEXT/… ; option `:context` pour un callback 3-arg. **Pas d'option `:timeout` ni de `maxResponseSize`** — la liste d'options est exhaustive dans l'annotation [SDK bin/api.mir:10143].
2. **Dans quelles conditions ?** Permission manifest `<iq:uses-permission id="Communications"/>` (accordée à l'installation, **pas de prompt runtime** pour une watch app) [SDK Manifest_and_Permissions]. Réponses et requêtes petites (voir 5), HTTPS, app au premier plan (la requête vit tant que l'app vit).
3. **Connexion Internet directe ?** **Non.** Le module est documenté « communicate with a mobile phone via BLE. The mobile phone may act as a bridge between the app and the Internet » [DOC Toybox/Communications]. Chaîne officielle : watch → BLE → **Garmin Connect Mobile** (« JSON REST Requests via Mobile Proxy ») → Internet [DOC core topic HTTPS].
4. **Quand passer par le téléphone ?** Toujours pour HTTP. Alternative = app compagnon custom (`Communications.transmit` + `registerForPhoneAppMessages`) → c'est la Phase 4b optionnelle [SPEC D10/ADR-006], non nécessaire ici.
5. **Rôle de GCM ?** Proxy systématique. Android : redémarrée automatiquement par un service système même si fermée → requêtes passent quasi toujours ; iOS : GCM doit être lancée (avant/arrière-plan) sinon `-104` immédiat [DOC forum 422118]. **Installée + appairée obligatoires.**
6. **Différences entre les 3 modèles ?** `makeWebRequest` présent et officiellement supporté sur epix Pro (Gen 2) 42/47/51 mm, fr55, instinct2 [DOC Supported Devices ; SDK Devices/<id>/*.api.debug.xml]. Aucune API Wi-Fi CIQ (l'epix Pro a du Wi-Fi matériel pour sync/musique, **non pilotable par une app**) [DOC forum 1248]. fr55/instinct2 : BLE+téléphone uniquement. Aucune cible LTE. → **une architecture commune** (décision D10 inchangée sur ce point).
7. **Sans GCM ouverte au premier plan ?** Android : oui (arrière-plan, relais automatique) ; iOS : GCM doit tourner (arrière-plan suffit si active) ; sinon `-104` [DOC forum 422118]. Le téléphone n'est **jamais requis pour le score local**.
8. **Limitations makeWebRequest** : débit BLE « 400-800 octets/s » [DOC FAQ] ; erreur `-101 BLE_QUEUE_FULL` si trop de requêtes simultanées (nombre non publié) ; `-102 BLE_REQUEST_TOO_LARGE` (requête, seuil non publié) ; `-402 NETWORK_RESPONSE_TOO_LARGE` (observé ~32 Ko sur un setup, 44 Ko passent ailleurs — **non documenté officiellement** ; viser < 2 Ko par sécurité) ; `-403` OOM (fuites mémoire documentées sur appels répétés [DOC forum 4102]) ; `-300` timeout réseau ; `-2 BLE_HOST_TIMEOUT` (GCM silencieuse) ; callback **peut ne jamais être appelé** (bug reports officiels) → **timeout applicatif obligatoire côté app** [DOC forums].
9. **Réception des réponses ?** Callback asynchrone unique `method(responseCode as Number, data as Dictionary or String or Null)` ; `responseCode` = code HTTP **ou** code d'erreur `< 0` ; `data = null` en erreur. Fire-and-forget : une requête perdue n'est jamais rejouée par la plateforme → réémission applicative (idempotence requise).
10. **Architecture viable pour les 3 modèles ?** Une seule : watch app → GCM → HTTPS. Le simulateur sort par le réseau du Mac **sans téléphone** (le sim ≠ device, comportements différents documentés) → développement et POC possibles sans matériel [DOC forums 406613/414966].

Canaux écartés : `openWebPage()` (ouvre une page sur le téléphone, sans callback — noté pour un futur flow OAuth) ; ANT+/BLE GATT (périphériques, pas d'Internet) ; `CompanionPlugin` (n'existe pas dans l'API 9.2.0).

## 4. Match ID

### 4.1 Cycle de vie

```
Création (startMatch, offline, montre)      Configuration (Setup avant start)
        │                                             ▲
        ▼                                             │
Début du match ──▶ points/event-sourcing ──▶ 1er POST = création paresseuse du match côté backend
        │                                             │
        ▼                                             ▼
Envoi des événements (batchs idempotents) ──▶ Synchronisation (ACK lastAcceptedSequence)
        │
        ▼
Overlay (match_state actif, auto-suivi) ──▶ Fin du match (MATCH_FINISHED → status=match_finished)
        │
        ▼
Archivage (status=archived après 30 jours, cron optionnel — jamais supprimé)
```

### 4.2 Format et génération `[PROPO]`

- **Format** : 8 caractères **Crockford base32** (`0123456789ABCDEFGHJKMNPQRSTVWXYZ` — pas de I/L/O/U), ex. `B7K2QM9X`. 40 bits d'entropie.
- **Génération** : sur la montre, au `startMatch`, mélange `Math.rand()` ×2 + `System.getTimer()`, encodé base32. **Amendement d'implémentation** : remplace le matchId « ms boot » de Phase 2 (non unique entre redémarrages).
- **Unicité** : aléatoire 40 bits (~1,1×10¹² combinaisons ; risque de collision sur la vie du projet ≈ 10⁻⁴) + contrainte PK `(match_id, sequence)` et PK `matches.match_id` en filet ; en cas de 409 → l'app régénère (jamais d'upsert aveugle du match).
- **Durée de vie** : `active` → `finished` (event MATCH_FINISHED) → `archived` (optionnel, > 30 j). Jamais supprimé (500 Mo DB ≈ ~10⁵ matchs à ~5 Ko, non dimensionnant).
- **deviceId** : UUID d'installation généré au 1er lancement de l'app et stocké dans `Application.Storage` (meta) — stable, offline, par montre. Champ `device_id` des POST.
- **Utilisateur** : aucun compte (usage personnel). `matches.channel` = chaîne Twitch du propriétaire, constante de config backend (un seul streameur, cf. réponse utilisateur).
- **Session Twitch / overlay** : voir §8.4 et §10 — l'association est **implicite et automatique** (l'overlay suit le match actif de la chaîne), pas de manipulation par match.
- **Sécurité** : deviner un matchId ne donne que la **lecture** (données de toute façon publiées sur le stream). 40 bits rendent l'énumération impraticable. L'**écriture** exige le device secret (§11). Rejoindre depuis un navigateur : l'URL `?match=<id>` le permet, en lecture seule.

### 4.3 Lien matchId ↔ chain

`montre` (génère, possède) → inclus dans chaque POST → `backend` (PK de matches/events/match_state) → diffusé par realtime → `overlay` (filtre match_id ou suit l'actif) → `OBS` (URL stable, sans id) → `Twitch` (le stream contient l'overlay ; bot filtré par `matches.channel`).

## 5. Backend (Supabase)

| Pièce | Contenu |
|---|---|
| **PostgreSQL** | 4 tables (§12), migrations SQL versionnées (repo, `supabase/`), RLS, publication `supabase_realtime` |
| **Edge Function `sync`** (Deno/TS) | Routing `/sync/matches/{matchId}/events` ; auth `X-Device-Key` (sha256 vs `devices.device_key_hash`) ; validation forme ; upsert events `ignore-duplicates` + upsert `match_state` (snapshot) ; ACK ; `verify_jwt = false` (auth custom) [DOC] |
| **Realtime** | Publication des 3 tables ; Postgres Changes consommé par overlay (et bot Phase G) |
| **(option)** `keepalive` | Edge Function + cron pour limiter la pause free tier — aucune garantie officielle que ça empêche la pause [À TESTER ; §19] |

Règles backend : **ne calcule jamais le score** (ADR-007) ; n'écrit jamais dans la montre ; ne modifie un état que sur POST authentifié par la device key ; idempotent ; région eu (latence France). Bootstrap de la device key : `openssl rand -base64 32` → hash sha256 inséré via migration (la clé en clair ne va jamais dans git) → collée dans les settings CIQ de l'app.

**Pause free tier** : projet suspendu après ~1 semaine d'inactivité, dépause manuelle au dashboard (autant de fois que voulu) [DOC pricing]. Pour un usage week-end : dépause le samedi matin, ou upgrade Pro 25 $/mois sans pause. Accepté (réponse utilisateur).

## 6. Évaluation Supabase (réponse à la question principale)

**Une app Garmin peut-elle parler à Supabase assez simplement et fiablement ?** Oui, mais **pas directement au REST de la base** : elle parle à **une Edge Function** (HTTPS POST simple, exactement ce que `makeWebRequest` sait faire). Le realtime est consommé par l'overlay navigateur, pas par la montre (pas de WebSocket dans CIQ [DOC]).

| | **A. Garmin → REST Supabase direct** | **B. Garmin → Edge Function → Supabase** ✅ | **C. Garmin → backend custom (Node/Fastify) → Supabase** |
|---|---|---|---|
| Avantages | Zéro code backend | Auth/validation/ACK propres ; clé publique jamais use-rights ; 1 seule fonction à maintenir ; gratuit | Contrôle total ; toujours possible plus tard |
| Inconvénients | **Sécurité** : RLS ne distingue pas ta montre d'un navigateur (l'anon key est publique par design) → écriture publique du score impossible à empêcher ; pas d'ACK `lastAcceptedSequence` propre ; erreurs PostgREST verbeuses pour la montre | Cold start 0,3-1 s (1re requête) ; code Deno à écrire (petit) | **Hébergement/maintenance à charge** (VPS, déploiements, WS, supervision) ; gratuit seulement en bricolant ; surdimensionné pour 1 utilisateur |
| Complexité | Minimale mais fragile | Faible | Élevée |
| Fiabilité | Moyenne (pas de validation) | Bonne (validation + idempotence en DB) | Bonne si bien opérée |
| Sécurité | **Insuffisante** | Bonne (device key + RLS lecture seule) | Bonne |
| Compat Garmin | OK (POST HTTPS) | OK | OK |
| Maintenance | ~0 | ~0 | Continue |
| Coût | 0 € | 0 € (free tier) | ~5 €/mois VPS |
| UX | Identique | Identique | Identique |
| Verdict | **Rejetée** (sécurité) | **Retenue** (B-lite) | Rejetée pour ce projet ; **fallback documenté** si Supabase limite un jour (le protocole montre ne change pas : il vise une URL HTTPS) |

## 7. Synchronisation

Principe conservé [SPEC] : `Score local → Persistence → Pending queue → Synchronisation`.

**File pending** : déjà matérialisée en Phase 3 (journal plat + pointeur `pf` dans la meta, purge durable à la purge). `SyncService` envoie `pf..lastSequence` ; l'ACK fait avancer `pf`.

| Sujet | Règle |
|---|---|
| Déclencheurs | Après chaque mutation (throttlé : 1 requête en vol max, ≥ 5 s entre requêtes [SPEC §9.6]) + flush au lancement si file non vide |
| Batch | ≤ 5 événements + snapshot courant (~500 o) ; si > 5 en attente → batchs successifs espacés |
| Retry / backoff | Erreurs `-2/-101/-102/-104/-300/-402/-403/HTTP ≥ 500` → backoff exponentiel 10 s → 2 min, file jamais vidée sur erreur [SPEC §9.3] |
| Callback jamais appelé | Timeout applicatif **30 s** → traité comme erreur, réémission (idempotence = sans risque) |
| Événements déjà envoyés | `sequence ≤ lastAcceptedSequence` → retirés de la file à l'ACK |
| Désordre / doublons | DB unique `(match_id, sequence)` + `ignore-duplicates` ; snapshot toujours correct |
| Reprise après redémarrage | `pf` persisté → flush au lancement [SPEC §9.4] |
| Match terminé hors ligne | File + snapshot `status=match_finished` persistés → envoyés à la prochaine ouverture de l'app |
| Sync non configurée | `backendUrl`/`deviceKey` vides → SyncService inactif, scoring 100 % local (dégradation gracieuse) |
| Jamais | Le réseau ne bloque jamais le scoring ; aucune écriture du backend vers la montre en 4a [SPEC §9.5] |

## 8. Overlay Web

### 8.1 Fiche technique

| Sujet | Décision |
|---|---|
| URL | `https://<user>.github.io/badminton-overlay/` (stable, bookmark OBS une fois pour toutes). Override optionnel : `?match=<matchId>` |
| Hébergement | GitHub Pages (statique, gratuit, HTTPS) — les Edge Functions ne servent du `text/html` **qu'avec domaine custom payant** [DOC] |
| Authentification | Aucune. Clé publique (`sb_publishable_`) embarquée ; lecture seule garantie par RLS |
| Récupération initiale | `match_state` du match actif de la chaîne (ou `?match=`), via supabase-js (REST GET sous le capot) |
| Realtime | Postgres Changes WSS sur `match_state` (et `matches` pour l'auto-suivi), filtre RLS SELECT public |
| Reconnexion | supabase-js reconnecte ; à la reconnexion **refetch** (Postgres Changes sans replay) ; limite de 24 h des connexions publiques → refetch couvre [DOC] |
| Offline backend | Dernier état affiché + indicateur discret « connexion perdue », retry auto |
| Latence | Voir §2.1 (≤ 5 s p95 end-to-end) |
| Match terminé | « MATCH TERMINÉ » + score final + sets, affiché jusqu'au prochain match actif |

### 8.2 Affichage

Joueurs, score, sets, format (depuis `config`), statut, service **calculable côté overlay** (rally scoring : le serveur = vainqueur du rally précédent, dérivable du score — option Phase E) ; nom de tournoi/logo = config statique de la page (personnel). Rendu noir/transparent pour incrustation OBS.

### 8.3 Payload realtime (réel, remplace l'exemple de la mission — cf. amendement A3)

Change event Postgres Changes sur `match_state` :

```json
{
  "type": "UPDATE",
  "table": "match_state",
  "new": {
    "match_id": "B7K2QM9X",
    "status": "active",
    "current_set": 2,
    "score_me": 17, "score_opp": 16,
    "sets_me": 1, "sets_opp": 0,
    "last_sequence": 42,
    "config": { "targetScore": 21, "winBy": 2, "cap": 30, "setsToWin": 2, "labels": { "me": "Marc", "opp": "Adversaire" } },
    "updated_at": "2026-09-19T14:32:01.482Z"
  }
}
```

### 8.4 Auto-suivi (association match ↔ overlay)

L'overlay s'abonne aussi aux changements de `matches` : dès qu'une ligne `status=active` existe pour la chaîne (ou en change), il bascule dessus et refetch son état. **Résultat : OBS est configuré une fois ; avant un match, aucune manipulation** (réponse à la mission §6 : les options 1/2/4 — code OBS, page web, QR — sont écartées car elles ajoutent une manipulation par match ; l'option 3 est simplifiée en binding serveur à utilisateur unique ; l'option 5, URL avec matchId, reste disponible en override `?match=`).

## 9. OBS

Configuration **une seule fois** : Sources → Browser Source → URL (§8.1) → taille (ex. 500×150) → « Shutdown source when not visible » = **Off** et « Refresh when scene becomes active » = **Off** (défauts, pour que le score continue d'arriver même hors scène active) [DOC] → FPS 30 (défaut). OBS = couche de composition : `Caméra + Overlay + autres sources → OBS → Twitch`. **Aucune logique métier dans OBS** (contrainte respectée).

| Situation | Comportement |
|---|---|
| OBS fermé | Le stream n'a juste pas d'overlay ; backend/montre inchangés |
| Twitch déconnecté | OBS gère sa reconnexion RTMP ; overlay indépendant |
| Overlay ouvert avant le match | Placeholder « En attente de match » ; bascule auto au premier match actif |
| Montre sans connexion | File locale ; overlay figé sur le dernier état reçu ; rattrapage au retour (snapshot courant, §7) |
| Backend indisponible | Montre : file + backoff ; overlay : dernier état + indicateur + retry ; rien n'est perdu |

## 10. Twitch (3 niveaux)

**Niveau 1 — Overlay (Phase F)** : le score arrive dans le stream via OBS. Aucune API Twitch requise. Le système fonctionne sans Twitch.

**Niveau 2 — Twitch API (optionnel, Phase F+)** : statut LIVE de la chaîne sur l'overlay (badge). `client_credentials` → app access token (aucun scope pour `getStreams`/`getUsers` [DOC]) stocké en **variable d'env Edge Function**, jamais côté client. App token non rafraîchissable (~58 j) → re-fetch automatique. Rate limit Helix par token bucket (très au-dessus du besoin). Association match↔chaîne : `matches.channel`, déjà couverte.

**Niveau 3 — Chat bot (Phase G)** : **script Node/tmi.js sur le PC de stream** (pas chez l'hébergeur : une Edge Function ne peut pas tenir une connexion IRC/EventSub longue, wall-clock 150 s [DOC]). Lit le realtime Supabase (anon, lecture seule) ; commandes `!score` `!badminton` `!match` `!sets` ; annonces automatiques sur les events (`POINT_*` → « Point pour Moi ! 12-8 » ; `SET_FINISHED`, `MATCH_FINISHED`). IRC `wss://irc-ws.chat.twitch.tv:443`, scopes `chat:read` + `chat:edit`, compte bot dédié, limite 20 msg/30 s (100 si mod) [DOC]. Token du bot : user token (authorization code flow), stocké **sur le PC uniquement** (`.env` local gitigné). Jamais dans la montre [SPEC §10].

## 11. Sécurité

| Sujet | Mécanisme |
|---|---|
| Authentification montre | **Device secret** : 32 octets aléatoires (base64url), stocké dans les settings CIQ (`App.Properties`, type string) ; envoyé en header `X-Device-Key` de chaque POST [SPEC §10 adapté : token device conservé] |
| Vérification | Edge Function : sha256(key) vs `devices.device_key_hash` ; 401 si absent/faux, 403 si `device_id` du body ≠ device du match |
| Backend | Service role **uniquement dans l'Edge Function** (jamais exposé) ; `verify_jwt=false` sur cette fonction seulement |
| Overlay | Lecture seule : `REVOKE ALL ... FROM anon` puis `GRANT SELECT` sur les 3 tables + policies `for select to anon` (piège officiel : les policies ne révoquent pas les grants) [DOC RLS] |
| Écriture navigateur | Impossible : aucun grant/policy INSERT pour anon → 401/403 [DOC] |
| Endpoints | Validation stricte : types 0-5, `sequence` entier > 0, batch ≤ 10 (marge de validation ; le protocole montre envoie ≤ 5, §7), body < 16 Ko, snapshot bien formé ; 400 sinon |
| Rate limiting | Limites plateforme Supabase + Edge (suffisant, usage personnel) ; pas de rate-limit custom en MVP (YAGNI, à revoir si exposition publique) |
| Idempotence | `UNIQUE (match_id, sequence)` + `ignore-duplicates` (réémissions sans effet) |
| Validation événements | Forme seulement (types, séquence, cohérence snapshot) — **jamais** le score (la montre est la vérité) |
| Usurpation de matchId | Lecture publique assumée (données diffusées au stream) ; écriture impossible sans device key |
| Secrets | Device key : settings montre + hash en DB ; service key : env Supabase ; Twitch : env/PC ; **rien dans le repo ni la montre au-delà du device key** [SPEC §10] |

## 12. Modèles de données

```sql
create table matches (
  match_id   text primary key,                -- 8 chars Crockford base32 (§4.2)
  device_id  text not null,                   -- UUID d'installation (meta montre)
  channel    text not null default 'marc',    -- chaîne Twitch (un seul streameur)
  config     jsonb not null,                  -- {targetScore, winBy, cap, setsToWin, labels?}
  status     text not null default 'active',  -- active | finished | archived
  started_at timestamptz,                     -- déclarée par la montre (1er batch), optionnelle
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table events (
  id        text primary key,                 -- "<matchId>:<sequence>" [SPEC §7.1]
  match_id  text not null references matches(match_id),
  sequence  int  not null check (sequence > 0),
  type      int  not null check (type between 0 and 5),  -- 0=POINT_ME 1=POINT_OPPONENT 2=UNDO(réservé 4a) 3=SET_CHANGED 4=SET_FINISHED 5=MATCH_FINISHED
  arg       int  not null default 0,
  prev_me   int, prev_opp int,                -- format plat de la montre [type, arg, seq, ts, prevMe, prevOpp]
  ts        bigint,                           -- timer de la montre (ms)
  created_at timestamptz not null default now(),
  unique (match_id, sequence)                 -- idempotence [SPEC §8.2]
);

create table match_state (                    -- snapshot fourni par la montre (amendement A3)
  match_id      text primary key references matches(match_id),
  status        text not null,                -- phase montre : active | set_result | match_finished
  current_set   int  not null default 1,
  score_me      int  not null default 0,
  score_opp     int  not null default 0,
  sets_me       int  not null default 0,
  sets_opp      int  not null default 0,
  last_sequence int  not null default 0,
  config        jsonb not null,               -- copie pour l'overlay (pas de join)
  updated_at    timestamptz not null default now()
);

create table devices (
  device_id        text primary key,          -- UUID d'installation
  device_key_hash  text not null,             -- sha256(device secret)
  label            text,
  created_at       timestamptz not null default now()
);

-- RLS (piège officiel : REVOKE avant GRANT)
revoke all on matches, events, match_state from anon, authenticated;
grant select on matches, events, match_state to anon;
alter table matches     enable row level security;
alter table events      enable row level security;
alter table match_state enable row level security;
create policy "public read matches"     on matches     for select to anon using (true);
create policy "public read events"      on events      for select to anon using (true);
create policy "public read state"       on match_state for select to anon using (true);

-- Realtime
alter publication supabase_realtime add table matches, events, match_state;
```

Volumes : un batch ≈ 500 o ; un match de 120 points ≈ 60 batchs ≈ 30 Ko en DB — free tier (500 Mo) = des années.

## 13. API

**Endpoint unique (Edge Function `sync`)** — la forme de la spec principale §8 est conservée, seule la racine change :

```
POST https://<PROJECT_REF>.supabase.co/functions/v1/sync/matches/{matchId}/events
Headers: X-Device-Key: <secret>
Body:
{
  "deviceId": "3f9c...-install-uuid",
  "config":   { "targetScore": 21, "winBy": 2, "cap": 30, "setsToWin": 2 },
  "snapshot": { "status": "active", "currentSet": 2, "scoreMe": 17, "scoreOpp": 16,
                "setsMe": 1, "setsOpp": 0, "lastSequence": 42 },
  "events": [                               // ≤ 5, format plat de la montre
    { "type": 0, "arg": 0, "sequence": 38, "ts": 15230417, "prevMe": 16, "prevOpp": 16 },
    { "type": 0, "arg": 0, "sequence": 39, "ts": 15231298, "prevMe": 17, "prevOpp": 16 }
  ]
}
→ 200 { "matchId": "B7K2QM9X", "lastAcceptedSequence": 39 }     // ACK [SPEC §8.1]
```

Codes : `200` ACK · `400` validation · `401` device key · `403` device_id ≠ propriétaire du match · `404` jamais (match créé paresseusement) · `409` collision matchId → la montre régénère · `413` body trop grand · `5xx` → backoff montre.

**Lecture d'état** (clients : overlay, bot, dashboard) — PostgREST public, RLS SELECT :

```
GET https://<PROJECT_REF>.supabase.co/rest/v1/match_state?match_id=eq.B7K2QM9X&select=*
Headers: apikey: <publishable key>
→ 200 [ { ...match_state } ]
```

Realtime (overlay/bot) : Postgres Changes sur `match_state` (score) et `events` (annonces bot), cf. §14.

## 14. Realtime

| Sujet | Choix |
|---|---|
| Mécanisme | **Postgres Changes** (déclaratif, RLS-native, 1 table = 1 abonnement) ; **Broadcast** gardé en réserve si latence insuffisante (nécessite trigger `realtime.send()`) |
| URL | `wss://<PROJECT_REF>.supabase.co/realtime/v1/websocket?apikey=<publishable>` [DOC] |
| Auth | Anon + RLS SELECT (lecture publique) |
| Limites free | 200 connexions, 100 msg/s, payload 1 Mo — usage réel : 1-3 connexions, ~1 msg/5 s, ~300 o [DOC] |
| Latence | p95 ≈ 228 ms (bench officiel) [DOC] |
| Connexions publiques | 24 h max → refetch à la reconnexion (supabase-js) ; Postgres Changes sans replay → refetch systématique |
| Consommateurs | Overlay (match_state) ; bot Phase G (events). **Jamais la montre** (pas de WSS en CIQ) |

## 15. MVP

**Test minimal de viabilité (à faire EN PREMIER, ~1 journée)** — répond à la question « Garmin → backend viable ? » sans rien construire d'autre :

1. Projet Supabase créé ; Edge Function `sync` minimale (log + insert `events`) + table `events`.
2. App de test montre (réutilise le prototype button-test) : bouton → `makeWebRequest` POST d'un event factice → responseCode affiché.
3. **Simulateur** (réseau du Mac, sans téléphone) : la ligne apparaît dans le dashboard Supabase → le CODE est bon.
4. **Matériel epix + GCM (Android)** : même test → la chaîne réelle est bonne (c'est le seul vrai risque, cf. §19).

**MVP complet** (toute la chaîne) :

1. Créer un match (11 points) sur la montre → matchId généré ;
2. Jouer quelques points (offline OK) ;
3. Lancer l'app → flush automatique → événements + snapshot dans Supabase ;
4. Ouvrir l'overlay (GitHub Pages) dans un navigateur → le score évolue en temps réel ;
5. Ajouter l'overlay comme Browser Source dans OBS ;
6. Lancer un stream Twitch de test (même juste l'aperçu OBS) → l'overlay est dans le stream.

Definition of done MVP : étapes 1-6 sans intervention entre le premier point et l'affichage overlay < 5 s ; kill de l'app → relance → rattrapage complet (aucune perte) ; backend coupé pendant 5 min → file locale → rattrapage.

## 16. Plan d'implémentation

Correspondance avec la spec principale §16 : A = préparation 4a ; B+C = 5 ; D = 4a ; E = 6 (+ partie overlay) ; F+G = 7.

| Phase | Objectif | Fichiers / modules | API | Tests | Critère de validation | Dépendances |
|---|---|---|---|---|---|---|
| **A — POC connectivité** | Prouver Garmin → Supabase (simu PUIS matériel) | `prototypes/sync-test/` (app minimaliste) ; projet Supabase ; `supabase/functions/sync` squelette ; `events` table | POST minimal | Manuel : dashboard | Ligne créée depuis **epix matériel via GCM** ; responseCode 200 ; latence notée | Compte Supabase |
| **B — Schéma + matchId** | Modèle SQL complet, RLS, publication, génération matchId côté montre | `supabase/migrations/*.sql` ; `engine/ScoreEngine.mc` (matchId 8 chars §4.2) ; meta `deviceId` | — | SQL (policies anon : SELECT ok, INSERT 401) ; RNE : unicité, format | Re-POST idempotent ; anon ne peut pas écrire ; matchId unique sur relances | A |
| **C — Edge Function sync** | Ingestion authentifiée + snapshot + ACK | `supabase/functions/sync/` (Deno) ; table `devices` + bootstrap key | §13 complet | `deno test` : auth, validation, idempotence, ACK, 409 | curl e2e : batch, doublons, désordre, mauvaise key | B |
| **D — SyncService montre** (4a) | File → batchs → backoff → settings | `source/services/SyncService.mc` (cœur pur testable + adaptateur makeWebRequest) ; manifest properties `backendUrl`/`deviceKey` ; App.mc flush | §13 | RNE : sérialiseur plat→JSON, batch ≤ 5, backoff FSM, timeout 30 s ; simu : e2e avec fonction réelle ; **matériel epix** | Points joués → dashboard en < 5 s ; kill/relance → rattrapage ; avion → file → rattrapage ; scoring jamais bloqué | C |
| **E — Overlay + realtime** (6) | Page statique live + OBS config | `overlay/` (HTML/JS supabase-js, deploy GH Pages) ; §8.4 auto-suivi | REST GET + WSS | Manuel : simu match + overlay navigateur ; OBS ; kill backend | Score visible < 5 s après le point ; reconnexion OK ; placeholder / match terminé OK | D |
| **F — Twitch niveau 1/2** | Stream réel avec overlay ; (option) badge LIVE | Env Edge Function `TWITCH_CLIENT_ID/SECRET` ; proxy getStreams (optionnel) | Helix getStreams (option) | Manuel : stream test | L'overlay est visible dans le stream Twitch réel | E |
| **G — Twitch bot** (7) | Commandes + annonces auto | `bot/` (Node, tmi.js, sur le PC) ; realtime events | IRC wss | Manuel : comptes de chat | `!score` répond ; annonce à chaque point | E |
| **H — Durcissement (optionnel)** | Archivage > 30 j, keepalive pause, métriques | cron/pg_cron ou Edge Function | — | — | Matches archivés ; pause maîtrisée | B |

Chaque phase : code compilable à chaque commit, petits pas, contraintes Garmin documentées dans les notes (comme les phases précédentes).

## 17. Tests

| Niveau | Outil | Cas |
|---|---|---|
| Moteur/sync pur | Run No Evil (`monkeyc -t`) | Sérialisation event plat → JSON ; batch ≤ 5 + découpage ; FSM backoff (erreurs → délais croissants, succès → reset) ; timeout 30 s ; flush au lancement ; sync non configurée = inactif |
| SQL/RLS | psql / supabase CLI | anon SELECT ok sur les 3 tables ; anon INSERT/UPDATE/DELETE → refus ; contrainte `(match_id, sequence)` ; publication realtime |
| Edge Function | `deno test` | Key absente/fausse → 401 ; body malformé → 400 ; batch > 10 → 400 ; doublons → 200 sans dupliquer ; désordre → ACK au max ; snapshot écrase l'ancien ; device mismatch → 403 |
| E2E simu | monkeydo + curl/overlay | Scénario complet du MVP §15 (sans OBS) |
| Matériel | epix + GCM Android | Checklist : sync live en match réel ; mode avion → rattrapage ; kill app → flush au relance ; GCM fermée Android → relais auto ; (iOS si un jour : GCM à lancer) ; latence mesurée |

## 18. Décisions

| # | Décision | Statut |
|---|---|---|
| S1 | Architecture **B-lite** : montre → GCM → Edge Function `sync` → PostgreSQL → Realtime → overlay | Validée (conception + docs) |
| S2 | Amendements A1/A2/A3 (§0) : D10 reformulé, §13 stack → Supabase, état = snapshot montre | Validés (signalés) |
| S3 | Supabase **free tier**, dépause manuelle acceptée ; Pro 25 $/mois = plan B sans pause | Validée (réponse propriétaire) |
| S4 | Côté montre : **POST HTTPS simple uniquement** (pas de WSS) ; realtime = côté navigateur | Validée [DOC] |
| S5 | Un seul streameur → pas de comptes ; `matches.channel` = config backend ; overlay auto-suivi (OBS configuré une fois) | Validée (réponse propriétaire) |
| S6 | matchId 8 chars Crockford base32, généré à la startMatch sur la montre (amendement d'implémentation du ms-boot), collision → régénération | Validée [PROPO → à figer en Phase B] |
| S7 | Idempotence : `UNIQUE (match_id, sequence)` + upsert `ignore-duplicates` ; ACK `{matchId, lastAcceptedSequence}` (contrat §8 conservé) | Validée |
| S8 | État diffusé = snapshot fourni par la montre (aucune règle de score côté backend, ADR-007) | Validée |
| S9 | Overlay : page statique GitHub Pages + supabase-js, Postgres Changes, refetch à la reconnexion ;Broadcast = réserve | Validée [PROPO] |
| S10 | Bot Twitch : Node/tmi.js **sur le PC de stream**, credentials locaux | Validée |
| S11 | Sécurité : device secret en settings CIQ + header `X-Device-Key` + hash en DB ; RLS lecture seule publique (REVOKE→GRANT) | Validée [PROPO] |
| S12 | Batchs ≤ 5 events, ≥ 5 s, timeout applicatif 30 s, backoff 10 s → 2 min | Validée [SPEC §8-§9 + DOC] |
| S13 | Fallback si Supabase insuffisant un jour : backend custom derrière la même URL HTTPS — le protocole montre ne change pas | Validée [PROPO] |

## 19. Open Questions (à tester sur matériel réel)

| # | Question | Montres concernées | Comment la lever |
|---|---|---|---|
| OQ1 | Latence réelle watch → GCM → Edge Function en match (cible ≤ 5 s p95 ?) | epix 51 mm | Phase A matériel, mesure 20 batchs |
| OQ2 | Relais GCM Android sur le téléphone réel : batterie optimisée ? GCM fermée à la main ? | epix 51 mm | Phase A/D : tuer GCM, mode économie d'énergie, observer `-104/-2` et le rattrapage |
| OQ3 | Seuil réel `-402` (réponse trop grande) et `-102` (requête trop grande) — nous visons < 2 Ko mais le plafond réel est inconnu | epix, fr55, instinct2 | Phase A : réponses de tailles croissantes |
| OQ4 | Settings CIQ (backendUrl/deviceKey) éditables dans GCM pour une app **sideloadée** sur le téléphone réel | epix 51 mm | Phase D : vérifier la présence de l'UI settings dans GCM Android |
| OQ5 | Callback perdu : fréquence réelle du « jamais appelé » et du `-2 BLE_HOST_TIMEOUT` | epix 51 mm | Phase D : compteurs de timeout dans les logs |
| OQ6 | Fuite mémoire sur appels répétés (forum) : impact réel à ~60 POST/match ? | epix 51 mm | Phase D : mémoire avant/après un match complet |
| OQ7 | Cold start Edge Function : impact sur la 1re requête après inactivité (week-end) | — | Phase A : mesurer le 1er POST après pause |
| OQ8 | Latence realtime ressentie sur l'overlay (bench officiel 228 ms p95, à confirmer dans OBS) | — | Phase E : délai visuel point → overlay |
| OQ9 | La pause free tier se produit-elle malgré un usage week-end + keepalive ? | — | Phase H : observation sur 3-4 semaines |
| OQ10 | `Math.rand()` : distribution/qualité suffisante pour 40 bits de matchId | epix, fr55, instinct2 | Phase B : test statistique léger en RNE |

## 20. Sources

**Spec existante** `[SPEC]` : `docs/superpowers/specs/2026-09-18-badminton-score-design.md` (décisions D1-D13, ADR-001..007, protocole §8, offline §9, sécurité §10, phases §16).

**Documentation officielle Garmin** `[DOC]` / `[SDK]` :
- Toybox.Communications (makeWebRequest, erreurs) : https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html
- Core topic HTTPS / « JSON REST Requests via Mobile Proxy » : https://developer.garmin.com/connect-iq/core-topics/https/ (+ copie locale SDK `doc/docs/Core_Topics/HTTPS.html`)
- FAQ REST (débit 400-800 o/s) : SDK local `doc/docs/Connect_IQ_FAQ/How_Do_I_Use_REST_Services.html`
- Manifest & permissions : SDK local `doc/docs/Core_Topics/Manifest_and_Permissions.html` (+ page en ligne)
- Properties & App Settings : SDK local `doc/docs/Core_Topics/Properties_and_App_Settings.html`
- Annotations makeWebRequest/erreurs : SDK 9.2.0 local `bin/api.mir` (~l.9738-10540), `bin/api.debug.xml`
- Support par device : SDK local `Devices/{epix2pro47mm,fr55,instinct2}/*.api.debug.xml`, `compiler.json`

**Forums développeurs Garmin** `[DOC]` :
- iOS vs Android GCM (422118) · Wi-Fi non exposé aux apps (1248) · limite -402 variable (414966) · sim ≠ device (406613) · fuite mémoire makeWebRequest (4102, 411443) · callback jamais appelé (bug reports « callback in background never called », « background process exits before timeout »)

**Supabase** `[DOC]` :
- API keys (publishable/secret, déprecation JWT 2026) : https://supabase.com/docs/guides/getting-started/api-keys
- PostgREST (insert multi-lignes, upsert, erreurs) : https://postgrest.org/en/stable/references/api/tables_views.html + /references/errors.html
- Realtime (postgres-changes, broadcast, protocol, limits) : https://supabase.com/docs/guides/realtime/…
- RLS (piège REVOKE/GRANT) : https://supabase.com/docs/guides/database/postgres/row-level-security
- Edge Functions (limits, CORS, verify_jwt) : https://supabase.com/docs/guides/functions/…
- Pricing / pause free tier : https://supabase.com/pricing

**OBS / Twitch** `[DOC]` :
- Browser Source (CEF, options par défaut, CSS, FPS) : https://obsproject.com/kb/browser-source + https://github.com/obsproject/obs-browser
- Twitch authentication (flows, durées de tokens) : https://dev.twitch.tv/docs/authentication/
- Helix API (getStreams/getUsers, rate limits) : https://dev.twitch.tv/docs/api/reference/ + /docs/api/guide/
- IRC chat (wss, scopes, limites) : https://dev.twitch.tv/docs/chat/irc/ + /docs/chat/
- EventSub (webhook vs websocket, user token requis en WS) : https://dev.twitch.tv/docs/eventsub/

**Propositions d'architecture** `[PROPO]` : tout ce qui n'est ni `[SPEC]` ni `[DOC]`/`[SDK]` dans ce document — notamment le choix B-lite, l'auto-suivi overlay, le snapshot `match_state`, le bot sur PC, le fallback S13. **À tester** `[À TESTER]` : tout §19.
