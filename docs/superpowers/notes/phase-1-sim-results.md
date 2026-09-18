# Phase 1 — Résultats simulateur (match complet)

Date : 2026-09-18 · Branche `phase-1` · Build final : commit `824dd89`

## Validation matérielle (epix Pro 51 mm réel, 2026-09-19)

- Sideload openMTP → `GARMIN/APPS/` OK (app « Badminton » à côté de ButtonTest, id distinct)
- **Match complet 2-1 en 21 points compté aux boutons** : ✅ (critère de sortie §16 atteint)
- BACK = point adversaire sans quitter ✅ · UP en SCORE = sans effet (UNDO Phase 2) ✅ · DOWN-long = hotkey musique, score intact (U2 Phase 0 confirmé) ✅
- Lisibilité à bout de bras ✅ · Aucun texte hors cadre après les fixes UI

## Checklist match complet par profil (validateur : propriétaire, simu)

| Profil | Setup 3 formats | Match complet 21 pts (2-1) | Match 11 pts (2-0) | Confirm. set (DOWN=OUI/BACK=NON) | Menu inline (UP-long) | Lisibilité | Sortie du cadre / chevauchements |
|---|---|---|---|---|---|---|---|
| epix2pro51mm (rond 454, AMOLED) | ✅ | ✅ | — | ✅ (aide 2 lignes) | ✅ depuis SCORE | ✅ | ✅ après 5 fixes UI |
| fr55 (rond 208, MIP) | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ après fixes |
| instinct2 (semi-octogone 176, 2 couleurs) | ✅ | — | ✅ | ✅ | ✅ | ✅ blanc/noir lisible | ✅ après fixes |

Détail du scénario epix : setup 21 pts → 21-18 (SET_RESULT auto, sets 1-0) → DOWN → 18-21 (sets 1-1) → DOWN → confirmation DOWN/BACK sans point → 21-17 → MATCH_FINISHED 2-1 MOI GAGNE → START sans effet (verrou) → DOWN retour SETUP (format mémorisé) → menu Reprendre/Quitter (System.exit OK).

## Fixes UI découverts et corrigés pendant la validation (commits badfc38 → 824dd89)

1. **Footers FONT_TINY illisibles sur AMOLED 454** → FONT_SMALL avec repli TINY si largeur insuffisante (getTextWidthInPixels, seuil final `2/3·w`).
2. **Textes du bas hors du cercle** (écrans ronds : corde quasi nulle au bas) → zone sûre bas à `7h/8`, sous-lignes calées au-dessus du footer (`subLineY`).
3. **Setup chevauchait le footer** (item « 21 POINTS » à l'init) → bloc d'items calé entre titre et footer, spacing adaptatif.
4. **Aide « DOWN=OUI BACK=NON » intrinsèquement trop longue** pour la bande basse d'un rond, même en TINY (359px vs corde 314 sur epix) → aide sur **2 lignes** (DOWN = OUI / BACK = NON).
5. **Sous-lignes (MOI/LUI, SETS, gagnant) chevauchaient le footer** sur fr55/instinct2 → clamp `min(h/2+fLarge, footerTop−fSmall)`.

Méthode : métriques de police **mesurées au simulateur** (sondes jetables) — epix S51/M59/L65/T45 ; fr55 S27/M34/L34/T25 ; instinct2 S24/M27/L31/T23. Aucune constante px verticale : tout dérive de `getFontHeight` + fractions de h.

## Leçons pour les phases suivantes

- Sur écran rond, TOUT texte bas doit être validé contre la **corde du cercle à son y** (largeur utile, pas w).
- Les paddings de cellules MIP (fr55/instinct2) rendent les collisions de cellules visibles (contrairement à l'AMOLED) → tester les petits écrans d'abord pour le layout.
- Le label du format au footer du Score utilise `shortLabel()` (« 21 PTS ») — la version longue ne tient pas dans la corde.
- Le menu inline n'existe que depuis SCORE (comportement conforme §5) — ne pas le tester depuis SETUP.
