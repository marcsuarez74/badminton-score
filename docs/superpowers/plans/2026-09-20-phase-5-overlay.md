# Phase 5 — Overlay OBS (score live pour stream)

## Objectif
Une page web (`overlay/index.html`, un seul fichier, sans build) qui affiche le score du match
en cours, mise à jour en temps réel, conçue pour être capturée dans OBS comme source navigateur.
Le propriétaire n'a **aucune manipulation** : il ouvre OBS, l'overlay suit automatiquement le
match actif de son canal.

## Architecture (figée par la phase 4a, §13 spec)
```
Montre ──pousse──► Supabase (match_state) ──Realtime WSS──► overlay.html ──capture──► OBS
```
- Lecture seule publique (RLS SELECT), anon key publishable embarquée (décision spec §13).
- **Auto-follow** : au chargement et à chaque événement Realtime, prendre le match **actif le
  plus récent** du canal (fallback : le plus récent tout statut, p. ex. final affiché après match).
  INSERT d'un nouveau match → bascule automatique.
- Reconnexion : auto (supabase-js) + refetch au retour d'onglet (`visibilitychange`).

## Design (choix du propriétaire)
- **Direction B** (l'UI montre) : vert `#2FE05C` = MOI, gris `#8B939B` = LUI, chiffres énormes,
  typographie condensée heavy, fond **transparent** (panneaux translucides sombres type TV).
- **Contenu** : noms (MOI/LUI), score, pastilles de sets (remplies = gagné).
- **Paramètres URL** : `?channel=marc` (défaut), `&name1=&name2=` (noms de session),
  `&scale=` (taille), `&bg=0` (désactiver panneaux).
- **Pas d'indicateur de service** : la donnée n'existe pas (moteur, sync, DB) → **Phase 6 dédiée**.

## Roadmap
- **Phase 6 — indicateur de service** : règle badminton dans le moteur (le vainqueur du rally
  sert), affichage montre, champ `serve` dans snapshot + events, migration DB, RNE, rebuild app
  → **mise à jour de l'app requise** (sideload). Candidate après l'overlay.
- **Phase 7 — bot Twitch** : annonce du score en chat (dépend overlay/canaux).

## Hébergement
GitHub Pages depuis `main` (racine repo publique) →
`https://marcsuarez74.github.io/badminton-score/overlay/?channel=marc`.
HTTPS requis par le Realtime — Pages le fournit.

## Tests (validation)
Playwright en local (http.server) + matchs injectés via la fonction sync (clé marc) :
1. Rendu initial : noms, score, pastilles.
2. Latence : 2e event pousse → score mis à jour < 1,5 s (Realtime, pas de polling).
3. Auto-switch : nouveau match injecté → l'overlay bascule seul.
4. Fin de match : statut `finished` → score final reste affiché.
5. Cleanup des matchs de test (API management, token trousseau).
Puis test final du propriétaire dans son OBS avec l'URL Pages.

## Hors scope
Service (phase 6), bot (phase 7), multi-overlay par canal (l'URL `?channel=` suffit),
historique/leaderboard.
