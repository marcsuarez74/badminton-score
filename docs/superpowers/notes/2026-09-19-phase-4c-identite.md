# Phase 4c — Identité de l'app (icône + nom)

Date : 2026-09-19. Branche : `phase-4c-identite`.

## Décisions (choix du propriétaire)
- Nom de l'app : **BadScore** (avant : « Badminton ») — `resources/strings/strings.xml` `AppName`.
- Icône launcher : volant de badminton issu de la **référence icons8** validée par le propriétaire
  (https://icones8.fr/icon/24314/volant-de-badminton), **recoloré** aux couleurs de la direction B :
  - plumes → vert Garmin `#2FE05C` (ombrages d'origine préservés par remap luminance),
  - liège bleu → blanc `#F4F4F4` (léger ombrage),
  - fond transparent.

## Fichiers
- `resources/drawables/launcher_icon.png` — 60×60 (défaut ; epix2pro51mm = 60×60 exact).
- `resources-round-208x208/drawables/launcher_icon.png` — 35×35 (fr55 = 35×35 exact).
- Remplacement de l'ancienne icône 36×36 (étirée → warnings de build).

## ⚠️ Licence icons8
Format **SVG payant**, PNG gratuit **avec attribution obligatoire** si diffusion. L'app n'est pas
distribuée en store (sideload uniquement) ; si un jour on publie, ajouter l'attribution ou acheter
la licence. Source brute conservée : `/tmp/watchdesign/icons8-volant.png` (200×200 RGBA) — non
committée.

## Leçons
1. **fr55 = famille `round-208x208`, PAS 260x260** — l'écran du FR55 fait 208×208
   (`$SDK/bin/default.jungle` : `fr55 = $(round-208x208)`, resourcePath famille `resources-round-208x208`).
   Un qualifier `resources-round-260x260` est silencieusement ignoré pour fr55 (le warning
   « launcher icon scaled » persiste — c'est comme ça qu'on le détecte).
2. La taille exacte de l'icône launcher par device élimine le warning « launcher icon (NxN) isn't
   compatible » — baseline warnings release : 17 → 15 (2 warnings icône supprimés).
3. Pipeline de génération : PNG source → canvas recolor in-browser (playwright) → dataURL →
   base64 → fichiers. `playwright-cli run-code --filename=X.js` refuse `require('fs')` au début du
   fichier (le wrapper parse le code en expression) — retourner les dataURLs et décoder côté shell.
4. `window.__volant = x` obligatoire (pas `let __volant`) si un script externe attend la variable.

## Validation
- 55/55 RNE × epix2pro51mm + fr55.
- Builds test + release : 0 warning launcher icon, 0 erreur.
- Sideload régénéré (les deux .prg embarquent icône + nom BadScore).
