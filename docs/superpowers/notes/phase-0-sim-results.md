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

## Sonde Application.Storage — U5 levée (Run No Evil, commits ba7af87 + ec1d061)

| Device | 8 Ko / valeur (U5a) | Total mesuré (U5b) | Verdict |
|---|---|---|---|
| fr55 | ✅ 8192 caractères stockés + relecture intacte | **113 Ko** (2 runs identiques) | **< doc (128 Ko)** |
| instinct2 | ✅ idem | **113 Ko** | **< doc (128 Ko)** |
| epix2pro51mm | ✅ idem | **≥ 160 Ko** (plafond de sonde atteint, mur non atteint) | ≥ doc |

Détails : 4 tests Run No Evil (roundtrip dictionnaire, valeur unique 8 Ko avec read-back, capacité totale 160×1 Ko avec sweep anti-clés orphelines + purge systématique, tableau positionnel compact). Sonde idempotente entre sessions (le Storage persiste dans le simu). Note : les totaux excluent les noms de clés et la surcharge de sérialisation → légèrement optimistes.

**Conclusion U5** : la limite réelle est **par device**. Budget de conception Phase 3 : l'app doit tenir sous **~110 Ko** sur fr55/instinct2 (clés + surcharge comprises). Le design §7.2 (clés multiples < 8 Ko, historique borné à 200 events ≈ 30-50 Ko) reste valide avec une marge saine.

## Leçons transférables à l'app réelle (watch/connect-iq)

1. **`dc.clear()` exige un fond opaque défini AVANT** : `setColor(WHITE, BLACK)` puis `clear()` puis `setColor(WHITE, TRANSPARENT)`. Sinon `clear()` peint le fond transparent persistant → no-op → les frames s'empilent (bug vu et corrigé en simu, commit 5a2207c).
2. **Toute géométrie verticale doit être dérivée de `dc.getFontHeight(...)`** — les offsets en pixels fixes ne passent pas d'un écran 176 px à un 454 px (polices CIQ proportionnelles à l'écran ; corrigé commit 81a2048). `Theme.mc`/layouts de l'app réelle : jamais de constantes px brutes pour les positions verticales.
3. `screenShape` (pas `shape`) est le champ réel de DeviceSettings.
4. Les polices de l'historique doivent être bornées par la hauteur d'écran disponible (pattern `mHistCap` réutilisable pour l'écran SCORE de l'app).
5. Swipes = événements UP/DOWN sur appareils tactiles (BehaviorDelegate) → l'app réelle doit consommer/ignorer les swipes sur epix pour éviter tout point fantôme en zone tactile.
6. **Run No Evil sur SDK 9.2.0** : fonctions de test = fonctions module annotées `(:test)`, signature `function test_x(logger as Logger) as Boolean` ; asserts via `Test.assertEqualMessage(a, b, msg)` (throw = échec) ; suppression de clé = `Storage.deleteValue()` ; littéraux dictionnaire avec `=>`. `Application.Storage` persiste entre sessions de simulateur → toute sonde doit être idempotente (sweep au démarrage).
7. **Budget storage par device** (U5) : ~113 Ko réels sur fr55/instinct2, ≥ 160 Ko sur epix → dimensionner la persistance (Phase 3) sous ~110 Ko sur les petits profils.
