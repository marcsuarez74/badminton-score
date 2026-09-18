# Phase 0 — Findings (2026-09-18)

## Environnement
- SDK installé : Connect IQ **9.2.0** (`connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`)
- Java : **Temurin 17.0.20.1** (requis par les CLIs Monkey C)
- Clé développeur : `~/keys/developer_key.der` (PKCS#8 DER ; le `.pem` brut est refusé par `monkeyc`)
- Build OK sur : epix2pro42mm / epix2pro47mm / epix2pro51mm / fr55 / instinct2
- Tailles `.prg` (release, sans tests) : buttontest 8,1-14,6 Ko ; builds `-t` (Run No Evil) 99-105 Ko

## Incertitudes levées

| # | Incertitude | Résultat | Preuve |
|---|---|---|---|
| U1 | onMenu (UP-long) sur les cibles | **Délivré sur epix Pro 51 mm matériel** : UP-long → `UP-LONG` affiché puis menu inline. fr55/instinct2 : simu seulement (matériel non disponible, à refaire) | Checklist T9 S3 (2026-09-18) |
| U2 | DOWN-long (hotkey) | **Intercepté par le système sur epix 51 mm** : DOWN-long lance la hotkey musique, l'app ne le reçoit pas de façon exploitable → bouton non mappable pour le score. fr55/instinct2 : à refaire sur matériel | Checklist T9 S3 |
| U3 | Détection tactile getDeviceSettings | `isTouchScreen` existe (API 1.2.0+), `isTouch` n'existe pas. epix=true, fr55/instinct2=false. `screenShape` est le champ réel (pas `shape`) | Sonde `[probe]` simu (phase-0-sim-results.md) |
| U4 | MTP /GARMIN/APPS epix 51mm | **Copie OK via openMTP** (mode MTP natif, pas de volume `/Volumes/GARMIN`). Remplacement même app id sans doublon (0.1.0 → 0.1.1). Garmin Express ne sait pas installer de .prg perso | T9 S1 + S4 (2026-09-18) |
| U5 | Limites réelles Application.Storage | 8 Ko/valeur OK ; **total réel par device : 113 Ko fr55/instinct2, ≥ 160 Ko epix** (mur non atteint sur epix) | Run No Evil T8 (simu, commits ba7af87 + ec1d061) |
| U6 | Logs si nom de PRG | **NE FONCTIONNE PAS sur epix 51 mm** (firmware 23.48, CIQ 5.0.0) : fichier `BUTTONTEST-EPIX2PRO51MM.TXT` vide créé dans `GARMIN/APPS/LOGS/` selon la convention documentée, app lancée puis quittée proprement via QUITTER → fichier resté à 0 octet. Seul `CIQ_LOG.BAK` (journal d'erreurs système CIQ, ex. crash du Store) apparaît dans LOGS/ | T9 S2 (2026-09-18, copie retour MD5 = fichier vide) |

## Résultats simulateur
Voir `docs/superpowers/notes/phase-0-sim-results.md` : checklist boutons ✅ sur les 3 profils, U3 + U5 levées, 7 leçons layout/clear/Run No Evil.

## Surprises / contraintes Garmin découvertes
1. **Mode USB = MTP** (pas de stockage de masse) : jamais de `/Volumes/GARMIN` ; transfert via openMTP uniquement ; « éjection » = fermer openMTP. Reconnexion MTP capricieuse (relancer openMTP).
2. **Garmin Express** : bloque la montre en mode Garmin et ne sait pas installer de .prg perso ; à réserver à la désinstallation d'apps.
3. **DOWN-long = hotkey musique** sur epix : un seul des 5 boutons est non mappable.
4. **Swipes tactiles** = événements UP/DOWN BehaviorDelegate sur epix → l'app réelle doit les consommer/ignorer (point fantôme).
5. `dc.clear()` exige un fond opaque défini avant (leçon simu, commit 5a2207c) ; géométrie verticale toujours dérivée de `getFontHeight` (commit 81a2048).
6. Run No Evil 9.2.0 : fonctions module `(:test)`, `Test.assertEqualMessage`, `Storage.deleteValue`, dictionnaires `=>` ; Storage persiste entre sessions simu → sondes idempotentes.
7. Builds `-t` (tests) ≈ 105 Ko vs app ≈ 14,6 Ko : ne pas sideloader le build de tests par erreur (même app id, il remplace l'app interactive).
8. **Aucun logging println sur matériel** (U6) : le debug terrain passera par un logging applicatif (Application.Storage lu via openMTP, ou makeWebRequest).

## Décisions pour la Phase 1
- **Design inchangé** : le mapping boutons est validé — UP/START/BACK exploitables, DOWN-long inutilisable (U2), UP-long disponible pour un menu (pause/undo).
- UX tactile epix : ignorer les swipes (leçon 4).
- Persistance (Phase 3) : budget < ~110 Ko sur fr55/instinct2 (U5) ; clés multiples < 8 Ko.
- Debug : ne pas dépendre des logs println matériels (U6) ; prévoir logging applicatif si besoin.
- Sideload : procédure openMTP documentée dans les notes ; cible = `GARMIN/APPS/`.
- Critère de sortie Phase 1 (spec §16) : un match complet compté aux boutons sur epix Pro.
