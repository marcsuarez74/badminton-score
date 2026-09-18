# Phase 3 — Findings (2026-09-19)

## Ce qui a été construit

- **MatchStore** (`source/MatchStore.mc`) : encapsulation `Application.Storage` — meta Dictionary (`mid`, `pi`, `ls`, `pf`, base) + événements en **lots plats** de 30 (6 Numbers/event, jamais d'imbrication) + préfs format (`badminton_prefs_v1`, clampé). `saveMatch` (purge éventuelle → lots → suppression orphelins → meta en dernier), `loadMatch`, `clearMatch`, `savePresetIndex/loadPresetIndex`.
- **Moteur base+tail** : `replay()` = base + journal ; `restore(base, events)` (+ `setLastSequence` monotone, filet D-2 après undo) ; `trimEvents(maxKeep)` purge les plus anciens en avançant la base (jamais le dernier event, clamp maxKeep ≥ 1) — UNDO reste correct après purge/restore.
- **Câblage** : reprise au lancement (§5 — écran dérivé de la phase), sauvegarde à chaque mutation (`syncScreen`) + filet `onStop`, purge au DOWN sur MATCH_FINISHED (`mEngine = null` → durable), format du match figé (`mMatchPresetIndex` ≠ sélection Setup), menu inline depuis tous les écrans de match (§3.2).
- **39 tests Run No Evil verts × 3 profils** (+9 vs Phase 2) ; critère de sortie §16 « kill/restart sans perte » validé au simu (epix + fr55) — `phase-3-sim-results.md`.

## Décisions & arbitrages (à porter plus loin)

1. **Meta = état de base** (pas l'état dérivé complet) : état reconstruit = replay(base + tail ≤ 175). Conforme à l'esprit §7.2 ; le tail est trivial à rejouer.
2. **Purge 200 → 175** : batch aligné, base avancée par le même `applyEvent` (zéro logique dupliquée). Nuance « jamais un event non acquitté » reportée en Phase 4a (rien n'est acquitté en Phase 3, `pf = 1`).
3. **`pf` (pendingFrom) dans la meta** : la file `match_pending_v1.<n>` n'est PAS dupliquée en Phase 3 (YAGNI — sans ACK tout est pending) ; la Phase 4a saura d'où réémettre.
4. **Match fini** : reste persisté (relance ré-affiche le résultat) ; DOWN le purge définitivement (`mEngine = null` empêche tout re-save) ; BACK sur Setup post-purge ferme l'app (comportement pré-match).

## Vigilances Phase 4a (protocole/sync)

- **Fenêtre de crash après purge** (revue Task 2) : crash entre l'écriture des lots (décalés après trim) et la meta → journal reconstruit faux, silencieux (probabilité minuscule, récupérable). Correctifs candidats : `"nev"` (nb d'events) dans la meta + troncation au load, ou validation de la chaîne de séquence au load. À traiter quand la sync rendra la corruption non récupérable.
- `loadMatch` devra exposer `"v"` et `"pf"` ; les retours `setValue/deleteValue` sont ignorés (quota 128 Ko — log inutile sur matériel, U6) ; hardening `saved["pi"] == null`.
- **D-2 confirmé** : séquence jamais réutilisée, y compris à travers save/load + undo (testé) ; la représentation réseau de l'undo (event `TYPE_UNDO` / DELETE / réémission) reste à trancher.
- Refactor candidat : `syncScreen` viole CQS (dérive l'écran ET sauvegarde) — spliter `saveNow()`/`deriveScreen()` si la Phase 4a complexifie les flux ; `drawMenu`/`drawSetup` partagèrent déjà un algorithme (Phase 2).

## Faits SDK 9.2.0 (nouveaux, à réutiliser)

- `Application.Storage` : `setValue/getValue/deleteValue/clearValues` — **pas de `remove`**.
- `AppBase.onStop(state as Dictionary or Null)` : **1 paramètre obligatoire** (api.debug.xml l.11178).
- Retourner null : unions `Dictionary or Null` + cast `as Dictionary` ; `import` (pas `using`) pour résoudre `Dictionary` en annotation.
- `Application.Storage` fonctionne tel quel dans le runner Run No Evil (tests store verts, pollution résiduelle gérée par `clearMatch` en tête de test).

## Leçons processus

- 3 Important attrapés par les revues sur un câblage « simple » (format figé, purge durable, RESET/menu) : le câblage UI mérite la même rigueur de revue que le moteur — les flux d'états croisés (menu × phases × purge) sont là où les bugs se cachent.
- Le pseudo-code du plan doit être relu contre les scénarios de validation de la tâche suivante (l'écart mScreen=SCORE a été attrapé par la revue spec, pas par l'exécution).
