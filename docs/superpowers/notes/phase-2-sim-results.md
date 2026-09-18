# Phase 2 — Résultats simulateur (undo + menu)

Date : 2026-09-19 · Branche `phase-2` · Build final : commit `822f997` · Tests : 30/30 × 3 profils

## Scénario validé par le propriétaire (epix2pro51mm, simu)

1. **UNDO points** : 3 points → UP×3 → 0-0, UP supplémentaire sans effet (pas de négatif) ✅
2. **UNDO fin de set** : 21-19 (SET_RESULT, sets 1-0) → UP → retour SCORE 21-19, sets 0-0 (set repris) ✅ *(nécessité le fix `662aeb7`)*
3. **UNDO changement de set** : DOWN (set 2) → UP → retour « SET 1 TERMINE », sets 1-0 ✅
4. **Verrou D7** : match fini 2-0 → UP inopérant (comportement attendu ; sortie par menu) ✅
5. **Menu inline 4 items** : REPRENDRE/FORMAT/RESET/QUITTER, navigation UP/DOWN, BACK ferme ✅ *(fix `822f997`)*
6. **FORMAT** → Setup → START → nouveau match ✅
7. **RESET** → 0-0 set 1 immédiat ✅
8. **QUITTER** → `System.exit()` ✅

## Profils

| Profil | Undo (points/fin de set/changement) | Menu 4 items (corde/octogone) | Lisibilité |
|---|---|---|---|
| epix2pro51mm (rond 454, AMOLED) | ✅ ×3 | ✅ items MEDIUM, bas 374 ≤ 397 | ✅ |
| fr55 (rond 208, MIP) | ✅ | ✅ items SMALL, bas 180 ≤ 182 | ✅ |
| instinct2 (semi-octogone 176, 2 couleurs) | ✅ | ✅ items SMALL, bas 153 ≤ 154 | ✅ blanc/noir |

## Fixes issus de la validation (commits après `145996c`)

1. `662aeb7` — UP=UNDO actif aussi depuis SET_RESULT (le scénario exigeait de reprendre un set terminé ; le plan Task 4 ne l'avait branché que sur SCORE).
2. `dfd1ff1` — BACK sur SETUP avec match en cours = annuler (retour à l'écran de la phase) au lieu de fermer l'app — chemin MENU → FORMAT (I-1 revue qualité).
3. `822f997` — menu borné à 7h/8 + items SMALL si h < 300 : sur fr55, 4 items MEDIUM sortaient de la corde du bas (153px vs corde 140).

## Leçons pour les phases suivantes

- Le scénario de validation doit être écrit **avant** le code de la tâche UI (ici le branchement SET_RESULT manquait car seul le §3.2 « UP=UNDO » générique avait servi de référence).
- Règle établie : **tout écran ajouté doit borner son contenu à 7h/8** comme les footers (le menu l'a redécouvert à ses dépens) ; polices : MEDIUM si h ≥ 300, SMALL sinon pour les listes.
- Menu/écrans : tester le rendu sur fr55 (rond le plus petit) avant instinct2 — la corde y est la plus contraignante.
