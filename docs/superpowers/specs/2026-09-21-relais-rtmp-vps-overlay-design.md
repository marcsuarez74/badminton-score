# Spec — Relais cloud RTMP : overlay dans la vidéo sans ordinateur

- **Date** : 2026-09-21
- **Statut** : conception à relire par le propriétaire (aucune commande passée, aucun code écrit)
- **Portée** : composite de l'overlay BadScore **dans la vidéo** au niveau d'un VPS, pour streamer depuis le seul téléphone. Complète la spec `2026-09-19-sync-backend-overlay-twitch-design.md` (qui reste la source de vérité backend/sync/overlay OBS).
- **Usage** : personnel (un streameur, le propriétaire), matchs filmés au téléphone, **aucun ordinateur présent**.

---

## 0. Problème et promesse

**Aujourd'hui** : l'overlay (scorebug) n'est visible que si un ordinateur exécute OBS avec un browser source. En déplacement, les viewers ne voient **pas** le score (ils ont seulement le chat, cf. annonceur automatique PR #16/#17).

**Promesse** : le téléphone streame la caméra vers un petit serveur ; le serveur incruste le score dans la vidéo et republie vers Twitch. Aucun ordinateur, aucune manipulation pendant le match (même posture que le reste du projet : « zéro manipulation »).

**Non-objectifs (YAGNI)** : multi-plateforme (Twitch seul), multi-streameur, VOD/replay, transitions/scènes (un seul plan fixe), codage matériel (le VPS n'en a pas).

---

## 1. Architecture cible

```
Téléphone (Larix Broadcaster, 4G/Wi-Fi)
   │  RTMP sortant : rtmp://<IP_VPS>:1935/live/<CLE_SECRETTE>
   ▼
┌────────────────────────────────────────────────────────────┐
│ VPS Infomaniak « Lite 3 » — Ubuntu 24.04 (~7,7 €/mois)     │
│                                                            │
│  MediaMTX (binaire Go, :1935)                              │
│   ├─ reçoit le flux du téléphone                           │
│   ├─ runOnDemand : lance ffmpeg-relay à la publication,    │
│   │  l'arrête à la déconnexion (Twitch passe « offline »)   │
│   └─ /metrics (localhost) pour supervision                 │
│                                                            │
│  ffmpeg-relay (lancé à la demande)                         │
│   ├─ entrée 1 : rtmp://localhost:1935/live/... (vidéo+AAC) │
│   ├─ entrée 2 : pipe RGBA (stdout du renderer, 2 fps)      │
│   ├─ filter_complex : [v0][ov]overlay=W-w-16:16            │
│   ├─ vidéo : libx264 veryfast, 720p30, ~4500 kbps          │
│   ├─ audio : -c:a copy (pas de ré-encodage)                │
│   └─ sortie : rtmp://<ingest Twitch>/<STREAM_KEY>          │
│                                                            │
│  renderer (Python + Pillow, systemd --user non nécessaire) │
│   ├─ GET Supabase REST (anon) : même pick que l'overlay    │
│   │  (match actif le plus récent > dernier fini), 2 s      │
│   ├─ dessine le scorebug (design validé phase 5) en RGBA   │
│   └─ écrit les frames en continu sur le pipe ffmpeg        │
└────────────────────────────────────────────────────────────┘
   │  RTMP sortant (~6 Mb/s)
   ▼
Twitch (ingest contribute.live-video.net) → viewers
```

**Rôles** : MediaMTX = réception + pilotage du cycle de vie ; renderer = score → pixels ; ffmpeg = composite + ré-encodage + push Twitch. Trois responsabilités, trois fichiers de config distincts.

---

## 2. Décisions d'architecture (avec justifications)

| # | Décision | Choix | Justification |
|---|---|---|---|
| D1 | Serveur | **VPS Infomaniak Lite 3** (2 vCPU EPYC, 4 Go, 60 Go NVMe, 500 Mb/s, trafic illimité, Genève) | Re-encode 720p30 veryfast ≈ 1-1,5 vCPU → marge suffisante ; datacenter suisse ~10 ms du propriétaire ; trafic sortant illimité (on ne pousse que ~6 Mb/s) |
| D2 | Réception RTMP | **MediaMTX** (binaire unique, actif, `runOnDemand`, metrics) | vs nginx-rtmp : install triviale (1 binaire + 1 conf), `runOnDemand` natif = composite démarré/arrêté automatiquement à la publication ; metrics intégrées |
| D3 | Overlay dynamique | **Pipe RGBA** (renderer → ffmpeg stdin, `-f rawvideo -pix_fmt rgba -r 2 -i -`) | ffmpeg ne relit PAS une image statique modifiée sur disque (`-loop 1 -i x.png` = lecture unique) ; le pipe évite tout redémarrage de ffmpeg (glitch) à chaque changement de score. Coût : le renderer ré-écrit la frame courante à 2 fps — négligeable (720p RGBA ≈ 3,7 Mo/frame × 2 = 7,4 Mo/s en mémoire/pipe local) |
| D4 | Rendu du scorebug | **Python 3 + Pillow**, police Archivo (OFL) embarquée dans le repo | Réutilise le design validé phase 5 (barre sombre translucide, chiffres blancs, pips de sets, « SET n ») ; Pillow est suffisant pour du texte aplati ; Archivo est OFL → fichier `.ttf` committé avec la licence |
| D5 | Choix du match | Identique aux autres consommateurs : REST Supabase (clé anon, lecture publique RLS), `matches` parent + `match_state!inner`, actif le plus récent puis fallback dernier fini | Une seule logique de « pick » dans tout le projet (overlay GH Pages, widget SE, renderer) |
| D6 | Encodage | libx264 **veryfast**, 1280×720, **30 fps**, ~4500 kbps, tune `zerolatency` | Budget CPU Lite 3 ; 720p suffit pour du badminton filmé au téléphone ; 1080p30 possible en upgradant Lite 4/5 (cf. §7) |
| D7 | Audio | `-c:a copy` (AAC du téléphone) | Zéro CPU audio, Twitch accepte AAC |
| D8 | Cycle de vie | `runOnDemand` MediaMTX | Pas de push Twitch quand le téléphone ne streame pas (évite le « direct noir ») ; systemd `Restart=always` sur mediamtx seulement |
| D9 | Secrets | Twitch stream key + clé RTMP d'ingest VPS dans `/etc/badscore/env` (chmod 600, root) | Jamais dans le repo ; la clé RTMP VPS est dans l'URL Larix (configurable dans l'app) |
| D10 | Pare-feu | ufw : 22 (SSH key only), 1935 (RTMP entrée) ; rien d'autre | Surface minimale ; metrics MediaMTX sur localhost uniquement |

---

## 3. Contrat du renderer (interface figée)

```
renderer.py --channel marc [--interval 2] [--position topright|topleft|topcenter]
  stdout : frames RGBA brutes continues (2 fps), 1280×720 (mêmes dims que la vidéo)
  comportement :
    - pick() identique à l'overlay : actif le plus récent, sinon dernier fini
    - aucun match → frame entièrement TRANSPARENTE (rien d'incrusté, pas de
      message « EN ATTENTE » : la vidéo reste pure)
    - Supabase injoignable → garde la dernière frame connue (pas de clignotement)
    - changement d'état → redessine et publie la nouvelle frame au prochain tick
```

Tests (TDD, même discipline que le reste du projet) :
- **unitaires** : `pick()` factorisé (mock REST) — actif>fini, canal inconnu → None ; dessin → largeur/hauteur, alpha de fond ≈ 0,66, texte des scores aux positions attendues (mesures pixel, cf. méthode phase 5 `analyze-keep*.js`)
- **intégration live** (playwright + canal `testse` isolé, annonceur chat désactivé pendant le test) : créer match 0-0 → frame contient « 0 » ; passer 5-3 → nouvelle frame ; finir → « Terminé » ; supprimer → frame transparente

---

## 4. Configuration ffmpeg-relay (référence)

```bash
ffmpeg -hide_banner -loglevel warning \
  -i "rtmp://127.0.0.1:1935/live/$VPS_KEY" \
  -f rawvideo -pix_fmt rgba -s 1280x720 -r 2 -i - \
  -filter_complex "[0:v]scale=1280:720,format=yuv420p[v0];[v0][1:v]overlay=x=W-w-16:y=16:format=auto[out]" \
  -map "[out]" -map 0:a \
  -c:v libx264 -preset veryfast -tune zerolatency -b:v 4500k -maxrate 4500k -bufsize 9000k \
  -g 60 -pix_fmt yuv420p \
  -c:a copy \
  -f flv "rtmp://cdg.contribute.live-video.net/app/$TWITCH_KEY"
```

Points d'attention `[À TESTER]` :
- `zerolatency` + `-g 60` : GOP 2 s ; Twitch tolère, à ajuster si artefacts
- position de l'overlay en haut-droite (hors du décor du gymnase, à confirmer selon le cadrage téléphone) — paramétrable via flag du renderer, pas de re-déploiement
- si le téléphone streame en 1080p, on downscale à 720 côté VPS (`scale=`) — qualité légèrement supérieure à natif 720

---

## 5. Sécurité

1. SSH : clé uniquement (`PasswordAuthentication no`), utilisateur non-root `badscore` + sudo
2. ufw : `22/tcp`, `1935/tcp` ouverts ; le reste deny
3. `/etc/badscore/env` : `VPS_KEY` (clé RTMP d'ingest, aléatoire ≥32 hex), `TWITCH_KEY` — chmod 600
4. MediaMTX écoute :1935 public ; publication exige le chemin `/live/<VPS_KEY>` (sans la clé, pas de publish)
5. Pas de TLS RTMP (obsolète côté Larix, non requis — la clé est le secret)
6. Mises à jour : `unattended-upgrades` activé

---

## 6. Latence et expérience viewer

| Étape | Délai |
|---|---|
| Point marqué → cloud (sync BLE, batchs) | ~5 s (constat phase 5, inchangé) |
| Renderer (polling 2 s) | ≤ 2 s |
| Composite + encode | ~0,5 s |
| Twitch ingest → viewer | 10-20 s (côté Twitch, incompressible) |
| **Total score visible dans la vidéo chez le viewer** | **~15-25 s après le point** — le même ordre que le chat, cohérent entre vidéo et chat |

Le streameur (Larix, écran local) voit la vraie action en temps réel — aucun délai ajouté pour lui.

---

## 7. Coûts et évolutions

| Poste | Coût |
|---|---|
| VPS Lite 3 | CHF 7,20 HT/mois (~7,7 €), résiliable à tout moment |
| MediaMTX / renderer / ffmpeg | 0 € (open source) |
| Supabase (overlay déjà en prod) | 0 € (free tier) |

Évolutions prévues (non bloquantes) :
- **1080p30** : upsize Lite 4/5 (CHF 9-18 HT) en 1 clic, même conf, `scale` retiré
- **Enregistrement local** des matchs : `-f mp4` sur disque (60 Go ≈ 30 h de 4500 kbps) — à activer plus tard si souhaité
- **Multi-destination** (YouTube...) : ajouter un `-f flv` supplémentaire (CPU x2) ou tee

---

## 8. Risques et limites

| Risque | Impact | Mitigation |
|---|---|---|
| Débit montant 4G insuffisant | Stream instable | Tester le débit montant du lieu (≥ 5 Mb/s) ; Larix permet de baisser à 2500 kbps |
| VPS reboot / maintenance Infomaniak | Twitch coupé ~30 s | Acceptable (fréquence très faible) ; systemd relance |
| Clé Twitch sur le VPS | Compromission du canal si VPS pénétré | Fichier 600, surface SSH minimale, aucun service web public |
| Re-encode x264 | Légère perte qualité vs direct | veryfast à 4500 kbps : perte imperceptible en 720p |
| Un seul stream composite | Pas de redondance | Hors périmètre (usage personnel) |
| Dépendance Archivo (TTF committé) | Rien (OFL) | Licence + copyright dans le dossier police |

---

## 9. Plan d'implémentation (phases)

> Le plan détaillé task-par-task (checkboxes, TDD) sera écrit au lancement, conforme au format `docs/superpowers/plans/`.

- **P1 — VPS** : compte Infomaniak, commande Lite 3 (Ubuntu 24.04), IP, SSH, ufw, utilisateur `badscore` *(action propriétaire : commander ; action agente : config)*
- **P2 — Réception** : install MediaMTX, clé d'ingest, config Larix sur le téléphone, validation « je vois la vidéo arriver sur le VPS » (ffprobe)
- **P3 — Renderer** : TDD (unitaires + live canal `testse`), police Archivo committée, revue visuelle du PNG généré (le propriétaire valide le design incrusté)
- **P4 — Composite** : ffmpeg-relay, push Twitch avec la clé stream, validation live (viewer + écran)
- **P5 — Industrialisation** : `runOnDemand`, systemd, `/etc/badscore/env`, metrics, README (install complète reproductible)
- **P6 — E2E réel** : un vrai match filmé au téléphone, overlay incrusté, `!score` + annonceur inchangés, doc retour d'expérience

Estimation : P1-P2 ~1 h (avec actions propriétaire), P3 ~1-2 h, P4-P6 ~1-2 h.

---

## 10. Décisions à valider par le propriétaire

1. **Budget OK ?** ~7,7 €/mois, résiliable
2. **720p30** comme qualité de départ (upgrade 1080p plus tard si besoin)
3. **Fournir la clé stream Twitch** au moment de P4 (ou la coller soi-même sur le VPS)
4. Position de l'overlay dans l'image : **haut-droite** par défaut (modifiable)
5. Le téléphone streame via **Larix Broadcaster** (gratuit, Android/iOS) — remplace l'app Twitch pendant les matchs
