# Phase 4c — Identité de l'app (icône + nom)

Date : 2026-09-19. Branche : `phase-4c-identite`.

## Décisions (choix du propriétaire)
- Nom de l'app : **BadScore** (avant : « Badminton ») — `resources/strings/strings.xml` `AppName`.
- Icône launcher : **wordmark « Bad »** en vert Garmin `#2FE05C` sur fond transparent — du texte pur,
  vectoriel 100 % maison, **aucune ressource externe, aucune licence**. Le propriétaire a écarté
  successivement : volants dessinés (3 itérations), volant icons8 (licence refusée par le
  propriétaire), volant CC0 Wikimedia, compositions « 15|0 » — choix final : simplicité du mot.

## Fichiers
- `resources/drawables/launcher_icon.png` — 60×60 (défaut ; epix2pro51mm = 60×60 exact).
- `resources-round-208x208/drawables/launcher_icon.png` — 35×35 (fr55 = 35×35 exact).
- Remplacement de l'ancienne icône 36×36 (étirée → warnings de build).

## Licence
Aucune : icône générée à partir d'un SVG texte écrit pour le projet (pipeline : HTML/SVG →
playwright canvas → PNG). Historique exploré (non retenu) : icons8 id 24314 (SVG payant, PNG avec
attribution — écarté), `Badminton shuttlecock.svg` Wikimedia **CC0** (générique, écarté).

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
