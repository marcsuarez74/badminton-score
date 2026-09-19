# Phase 4a — Résultats synchronisation (simu + matériel)

Date : 2026-09-19 · Branche `phase-4a` · Build final : commit `aa836ef` · Tests : 55/55 RNE × 2 profils + 8 Deno

## Critères de sortie (§16 spec principale, Phase 4a)

1. **makeWebRequest → GCM → Edge Function → PostgreSQL fonctionnel sur l'epix matérielle** : ✅ (événements en DB < 2 s après l'appui)
2. **Idempotence prouvée, ACK traité** : ✅ (re-POST curl → ACK identique ; en matériel, séquences 1→11 strictement continues à travers GCM fermée + mode avion + redémarrages app)
3. **Offline-first intact** : ✅ (scoring instantané sans réseau ; file jamais perdue ; rattrapages complets)
4. **55 tests RNE verts + 8 Deno verts** : ✅ (55 × epix2pro51mm/fr55 release ; 8 deno test)
5. **Notes + PR + coches plan** : ce document + PR `phase-4a`.

## E2E simu (epix2pro51mm, réseau du Mac)

- Flush au lancement : match restauré 26971 (Phase 3) → 2 batches (`envoi seq<=5` → `ack 5` → `seq<=8` → `ack 8`) — drain/ACK/pf exactement comme conçus.
- Match neuf `CQ8JM0M3` (Crockford 8 chars) : points en DB en ~1-5 s, batch de 2 (`envoi seq<=3` → `ack 3`), chaîne `prev_me/prev_opp` cohérente.
- Idempotence à travers 4 lancements : DB = exactement `[1,2,3]`, aucun doublon ; relance avec journal acquitté → **aucun POST** (batch vide).
- **fr55 simu** : match `HCYZFQVX`, deviceId **distinct** (`a35b656227ffec05` vs epix `f1592de682c46bc5`) — isolation multi-device validée.
- Properties de simu injectées via mini-app jetable (même app id) appelant `Properties.setValue` — l'éditeur GUI du simulateur (File > Edit Application.Properties) refuse l'app (« no setting file found », cf. bug GCM/settings ci-dessous).

## Matériel (epix Pro 51 mm, GCM Android, firmware 27.18)

- **Points → DB en < 2 s** (OQ1 levée : latence perçue instantanée côté scoring, DB quasi-temps réel).
- **GCM force-stoppée (OQ2 levée)** : 2 points restés en file, renvoyés **dans un seul batch** à la réouverture (`seq 2-3`, timestamps identiques), ACK, puis flux normal. Aucune perte.
- **Mode avion** : 5 points offline → retour : rattrapage complet, `seq 7-11` en **un batch de 5 max** (batchSlice prouvé), séquences 1→11 continues.
- Scoring 100 % offline-first pendant toutes les coupures (aucun impact UX).

## Bugs environnementaux découverts (HORS de notre code)

1. **GCM 5.29 + firmware 27.18 : ouvrir la page Réglages d'une app CIQ sideloadée REBOOTE la montre** — reproduit avec le sample officiel Garmin `ApplicationStorage` (settings intacts du SDK). Nos 3 variantes de `settings.xml` (type url, alphaNumeric, @Strings+defaults) plantent identiquement. **OQ4 : reportée — bloquée par GCM 5.29** (à re-tester à la prochaine version GCM ; signalement Garmin à faire).
2. **`Properties.getValue` ne retourne PAS les defaults déclarés dans settings.xml sur matériel** (la simu, elle, les retourne). Symptôme : app silencieuse (no-op) malgré config embarquée. Diagnostic par probe à valeurs codées en dur (fonctionne immédiatement).
   → Contournement retenu : **`scripts/build-release.sh`** — lit `.secrets/phase-4a.env`, injecte backendUrl/deviceKey en defaults dans une copie temporaire, produit des .prg signés dans `watch/connect-iq/sideload/` (gitigné), prêts à sideloader. Code commité sans secret. Alternative testée en simu : mini-app « config » (même app id) appelant `Properties.setValue`. À re-tester après fix GCM : la saisie via Réglages GCM reste le chemin nominal.
3. **`updated_at` de `match_state` ne s'actualise pas aux upserts** (default now() sans trigger). Sans impact : l'overlay s'appuie sur les événements Realtime. Follow-up candidat : trigger `moddatetime` (migration 1 ligne).

## Leçons pour les phases suivantes

- **`hidden` est interdit** : crash « Symbol Not Found » au load en simu SDK 9.2.0 (Task 3, commit 2635dd2).
- **Clés d'options `makeWebRequest` en symboles** (`:method`/`:headers`/`:responseType`) : les clés string sont silencieusement ignorées → POST devenait GET sans headers (Task 3, cf8b456, prouvé par capture réseau locale).
- **`==`/`!=` sur String = comparaison par référence** : toujours `.equals()` (Task 7).
- Les snippets du plan ont contenu 3 classes de bugs récurrents : imports manquants (`Toybox.Test`, `Toybox.Application`), `hidden`, clés string — toujours builder/compiler AVANT de croire le snippet.
- Le plan Task 8 avait un off-by-one dans `ackUntil` (pf = première séquence **non** acquittée → stocker `seq+1`, garde `seq >= pf`) : ses propres tests l'exigeaient.
- Les defaults de properties ne sont pas fiables sur matériel (cf. bug 2) : ne jamais dépendre de `settings.xml` defaults pour le comportement runtime.
- Debug réseau montre : capturer avec `nc -l` local + envoi auto au lancement (view.send() dans getInitialView) — indépendant de Supabase, pas d'aller-retour propriétaire.
- Le pseudo-code ≠ vérité (confirmé 6× cette phase) : TDD rouge systématique avant d'implémenter un snippet.

## Artefacts de test

- Matches de test en DB : `TEST4A01`, `CURLTEST1`, `26971` (match Phase 3 resynchronisé), `CQ8JM0M3` (simu epix), `JZJ3MGW6`/`ZH592CDG` (matériel), `HCYZFQVX` (simu fr55) — backend de dev, nettoyage non requis (aucune donnée personnelle).
- Builds de debug : `prototypes/sync-test/sideload/` (gitigné, contient la clé — à supprimer après usage).
- Token du propriétaire (device key) : stocké uniquement dans `.secrets/phase-4a.env` (gitigné) + gestionnaire de mots de passe du propriétaire.
