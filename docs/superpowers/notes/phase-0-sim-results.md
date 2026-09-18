# Phase 0 — Résultats simulateur (button-test)

Date : 2026-09-18 · Commits prototype : 8f53feb, c68a9a9, 56e1a61, 81a2048, 5a2207c

## Checklist boutons par profil (validateur : propriétaire, simu)

| Profil | START | BACK (non-sortie) | UP | DOWN | UP-LONG→MENU | Menu UP/DOWN/START/BACK | Remplacement des frames |
|---|---|---|---|---|---|---|---|
| fr55 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (après fix) |
| instinct2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (après fix) |
| epix2pro51mm | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (après fix) |

## Sonde DeviceSettings — U3 levée

| Profil | screenWidth/Height | screenShape | isTouchScreen | isTouch |
|---|---|---|---|---|
| fr55 | 208×208 | 1 (round) | **false** | ABSENT |
| instinct2 | 176×176 | 4 (semioctagon) | **false** | ABSENT |
| epix2pro51mm | 454×454 | 1 (round) | **true** | ABSENT |

**Conclusion U3** : `System.getDeviceSettings().isTouchScreen` existe (API 1.2.0+) et reflète fidèlement le tactile ; le champ `isTouch` n'existe pas. → `DeviceInfo.mc` utilisera `isTouchScreen`.

## Leçons transférables à l'app réelle (watch/connect-iq)

1. **`dc.clear()` exige un fond opaque défini AVANT** : `setColor(WHITE, BLACK)` puis `clear()` puis `setColor(WHITE, TRANSPARENT)`. Sinon `clear()` peint le fond transparent persistant → no-op → les frames s'empilent (bug vu et corrigé en simu, commit 5a2207c).
2. **Toute géométrie verticale doit être dérivée de `dc.getFontHeight(...)`** — les offsets en pixels fixes ne passent pas d'un écran 176 px à un 454 px (polices CIQ proportionnelles à l'écran ; corrigé commit 81a2048). `Theme.mc`/layouts de l'app réelle : jamais de constantes px brutes pour les positions verticales.
3. `screenShape` (pas `shape`) est le champ réel de DeviceSettings.
4. Les polices de l'historique doivent être bornées par la hauteur d'écran disponible (pattern `mHistCap` réutilisable pour l'écran SCORE de l'app).
5. Swipes = événements UP/DOWN sur appareils tactiles (BehaviorDelegate) → l'app réelle doit consommer/ignorer les swipes sur epix pour éviter tout point fantôme en zone tactile.
