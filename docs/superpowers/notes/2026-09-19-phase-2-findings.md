# Phase 2 — Findings (2026-09-19)

## Ce qui a été construit

- **UNDO (§4.5/D7)** : `ScoreEngine.undo()` — retire le dernier événement du journal (quel qu'il soit) + replay ; verrou `MATCH_FINISHED` (ne s'annule jamais) ; journal vide → sans effet. Branché UP en SCORE **et** SET_RESULT (fix validation).
- **Métadonnées d'événements (§7.1/§8.2)** : journal 6 slots `[type, arg, seq, ts, prevMe, prevOpp]` ; matchId (`genMatchId()` = ms du boot) ; séquence **monotone** ; getters protocole `getEvent(i)` / `getEventId(i)` = `matchId:sequence`.
- **Menu inline 4 items (§5)** : Reprendre / Changer de format / Réinitialiser / Quitter (labels compacts FORMAT/RESET), navigation cyclique, BACK ferme ; RESET = `newMatch(config, nouvel id)`.
- **30 tests Run No Evil verts × 3 profils** (undo simple/multi/vide/verrou, undo SET_FINISHED/SET_CHANGED, protocole événements, séquence monotone). Critère de sortie §16 (« suite §15.1 verte hors persistance ») atteint. Validation simu 3 profils : `phase-2-sim-results.md`.

## Décisions à porter en Phase 4a (protocole/sync)

1. **D-2 — séquence jamais réutilisée après undo** : l'idempotence backend `(match_id, sequence)` imposerait de dropper un event réutilisant un numéro déjà vu → point perdu. Conséquence : après undo, le journal a un trou de séquence (dernier seq supprimé, compteur conservé). **Question ouverte §8** : la représentation réseau de l'undo (event `TYPE_UNDO` réservé dans l'enum §7.1, endpoint DELETE, ou réémission d'historique) — à trancher quand le backend sera conçu ; en local (Phases 2-3) le retrait+replay est suffisant.
2. **Undo d'un event déjà acquitté** : même problème côté données — l'événement annulé a pu partir en `pending`/ACK. La file pending devra retirer l'event annulé ; s'il était déjà ACK, seule la représentation réseau ci-dessus peut le corriger côté dashboard.
3. `TYPE_UNDO = 5` est réservé dans l'enum mais jamais journalisé en Phase 2 (undo = retrait, §4.5 explicite).

## Points de vigilance Phase 3 (persistance §7.2)

- **À la restauration d'un journal sauvegardé, `mLastSequence` doit être dérivé du journal** (max des seq), pas remis à 0 — sinon les nouveaux events réutiliseraient des séquences déjà acquittées par le backend et seraient **silencieusement ignorés** (c'est exactement le risque que D-2 protège). Prévoir une `restoreEvents(events, matchId, lastSequence)`.
- Le format 6 slots est directement compatible avec la sérialisation §7.2 (tableaux positionnels, ~150-250 o/event) ; `prevMe/prevOpp` + `seq` + `ts` déjà portés.
- `MatchView.mMatchId` est en écriture seule (le moteur détient l'id ; un `getMatchId()` au moteur serait plus propre pour Phase 3/4a).
- Refactor candidat : `drawMenu`/`drawSetup` partagent l'algorithme liste-titre-zone-compression (extraire `drawList(...)`).

## Leçons processus / Monkey C

- Rien de nouveau côté API Monkey C cette phase (leçons Phase 1 toujours d'actualité : `me` réservé, `TEXT_JUSTIFY_CENTER`, `System.exit()` en dernier bloc, verdict = ligne PASSED).
- Écrire le **scénario de validation AVANT** le code de la tâche UI : l'oubli du branchement SET_RESULT vient de l'écart entre §3.2 (« UP=UNDO » générique) et le scénario.
- Règle de layout confirmée : **tout écran borne son contenu à 7h/8** ; listes : MEDIUM si h ≥ 300, sinon SMALL (fr55/instinct2).
- Revue qualité a de nouveau attrapé un vrai piège UX (BACK sur SETUP avec match en cours → fermeture app, viol §3.2) — les flux d'états UI méritent une revue dédiée à chaque nouvelle transition.
