# Phase 3 — Résultats simulateur (kill/restart)

Date : 2026-09-19 · Branche `phase-3` · Build final : commit `b49de4b` · Tests : 39/39 × 3 profils

## Scénario validé par le propriétaire (epix2pro51mm, simu — relance de l'app = kill/restart)

1. **Reprise SCORE** : match 7-3 → QUITTER → relance → retour direct SCORE 7-3 ✅
2. **Reprise SET_RESULT** : 21-19 (SET 1 TERMINE, sets 1-0) → QUITTER → relance → « SET 1 TERMINE » restauré (pas SCORE) ✅ → UP → retour SCORE 21-19, sets 0-0 (undo après reprise) ✅
3. **Reprise MATCH_FINISHED + purge** : match fini 2-0 → QUITTER (menu, cf. fix 3) → relance → « MATCH TERMINE » affiché ✅ → DOWN → Setup (purge) → relance → **Setup propre** ✅
4. **Format 11 pts + mémoire** : match 11 pts en cours → QUITTER → relance → reprise 11 PTS ✅ ; menu → FORMAT → Setup présélectionne « 11 POINTS » → BACK → match intact (format figé, cf. fix 2) ✅
5. **fr55** : match en cours → QUITTER → relance → reprise directe SCORE ✅

## Fixes issus de la validation (commits après `12e89fc`)

1. `fb15b20` — écran initial de reprise dérivé de la phase (SET_RESULT/MATCH_FINISHED restaurés sur le bon écran ; le plan initial mettait SCORE inconditionnellement — écart détecté en revue spec).
2. `12e89fc` — 3 Important de la revue qualité : format du match **figé** (`mMatchPresetIndex` dissocié de la sélection Setup — BACK-cancel ne corrompt plus les règles) ; purge au DOWN **durable** (`mEngine = null` — onStop ne re-persiste plus le match purgé) ; RESET sort du menu (régression via syncScreen).
3. `b49de4b` — **menu inline accessible depuis tous les écrans de match** (§3.2 : unique chemin de sortie) ; fermeture du menu → retour à l'écran de la phase.

## Leçons pour les phases suivantes

- Le pseudo-code du plan peut contredire ses propres scénarios de validation (mScreen = SCORE vs dérivation) : relire les scénarios Task N+1 AVANT de figer le pseudo-code Task N.
- SDK 9.2.0 : `Application.Storage.deleteValue` (pas de `remove`) ; `AppBase.onStop(state as Dictionary or Null)` = 1 paramètre ; unions `Dictionary or Null` nécessaires pour retourner null ; `import` (pas `using`) pour le type `Dictionary`.
- La reprise doit dériver l'écran de la phase restaurée (jamais d'écran codé en dur).
- Toute purge de données persistées doit être « durable » : vérifier qu'aucun filet (onStop, syncScreen) ne la réécrit — d'où `mEngine = null`.
