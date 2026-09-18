# Phase 1 — Findings (2026-09-18/19)

## Ce qui a été construit

- `watch/connect-iq/` : la vraie app (id `59EEABC3...`, 5 devices, sans permission) — moteur PUR event-sourcing (`engine/` : MatchConfig/ScoreEvent/Rules/ScoreEngine) + UI mono-écran 6 écrans (`ui/` : MatchView/MatchDelegate) + `App.mc`.
- **21 tests Run No Evil verts × 3 profils** (formule §4.2 complète, replay, fin de set auto, transitions manuelles, verrou MATCH_FINISHED).
- Validation : simu 3 profils (match 2-1 en 21 pts) + **matériel epix Pro 51 mm (match complet 2-1 réel)** — critère de sortie §16 atteint. Résultats : `phase-1-sim-results.md`.

## Découvertes Monkey C / SDK 9.2.0 (transférables)

1. **`me` est un mot réservé** (paramètre de fonction interdit) — nommer `nMe`/`mSide`.
2. **`Graphics.TEXT_CENTER` n'existe pas** → `TEXT_JUSTIFY_CENTER` (piège d'API ; vérifier `api.debug.xml` avant d'écrire le code de rendu).
3. **`using X` ne résout pas les types en annotation** (`as Dc`, `as Boolean`) → `import Toybox.X` partout où l'on annote.
4. **monkeyc exige la classe d'entry point du manifest dès le premier build** — pas de build « partiels » possible (stub obligatoire).
5. `System.exit()` non retournant → warning « unreachable » si du code suit ; structurer en if/else à sortie unique.
6. `monkeydo` retourne 1 même en succès ; le verdict fiable = ligne `PASSED (passed=N, failed=0, errors=0)`. Après `pkill` du simulateur, le relancer via `open ConnectIQ.app` avant monkeydo.
7. **Métriques de police mesurées au simu** (sondes jetables) : epix 454 S51/M59/L65/T45 ; fr55 208 S27/M34/L34/T25 ; instinct2 176 S24/M27/L31/T23 — les hauteurs de cellule sont énormes sur AMOLED 454, aucun layout px fixe ne passe.

## Leçons majeure : layout sur écran rond

- TOUT texte du bas doit tenir dans la **corde du cercle à son y** (pas `w`) : au bas du cercle, la largeur utile tend vers 0.
- Bande footer sûre : bas à `7h/8` ; sous-lignes clampées `min(h/2+fLarge, footerTop−fSmall)` ; bloc du Setup calé entre titre et footer (spacing adaptatif).
- Un texte d'aide long (« DOWN=OUI BACK=NON ») ne tient pas sur une ligne dans la bande basse → **2 lignes courtes**.
- Les collisions de cellules MIP (fr55/instinct2) sont visibles, pas celles AMOLED → **tester le layout sur les petits écrans d'abord**.
- `getTextWidthInPixels` + repli de police = pattern standard (`drawFooter`).

## Décisions pour la Phase 2 (moteur complet)

- **UNDO prêt à brancher** : pop du dernier event + replay ; le verrou §4.5 est déjà journalisé (MATCH_FINISHED poussé par `checkAutoSetFinish` ET `changeSet`) — refuser le pop si le dernier event est TYPE_MATCH_FINISHED, tester les cas §15.1 (undo SET_FINISHED reprend le set, undo SET_CHANGED retour au set précédent, undo multi, undo vide).
- Menu inline complet (§5, 4 items) : Réinitialiser = `newMatch(config)` (déjà implémenté + testé) ; Changer de format = `newMatch(MatchPresets.get(i))` — faciles.
- Événements/protocole (§8) : le journal positionnel est en place ; la séquence = index (sans trou par construction).
- Persistance (Phase 3) : journal = tableaux positionnels déjà compatibles §7.2 ; budget storage < ~110 Ko largement tenu (46 events ≈ quelques centaines d'octets).
- Dérogation assumée §4.4 à re-confirmer en Phase 2 : SET_CHANGED manuel crédite le leader strict (égalité → personne) — testé `test_engine_manual_set_change_*`.
