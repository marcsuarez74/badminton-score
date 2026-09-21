# BadScore — Guide utilisateur

*Version 1.0 — compatible Garmin Connect IQ. Ce guide est la référence pour la fiche store et la page web d'aide.*

---

## 1. BadScore, c'est quoi ?

BadScore transforme ta montre Garmin en **tableau de score de badminton** : un bouton par point, et le score part **tout seul** sur internet. Tes viewers suivent le match en direct :

- dans la **vidéo** (bandeau de score façon retransmission TV),
- dans le **chat** (`!score` ou annonce automatique à chaque point).

Aucun ordinateur, aucune manipulation pendant que tu joues : la montre fait tout, offline d'abord (le score marche même sans réseau — la sync rattrape dès que ça revient).

---

## 2. Ce qu'il te faut

| Élément | Détail |
|---|---|
| Montre Garmin compatible | Voir familles supportées sur la fiche store (v1.0 : epix2 Pro 51 mm, Forerunner 55 — d'autres familles suivent) |
| Garmin Connect Mobile | Installé et connecté à ta montre (c'est le relais internet de la montre) |
| Pour streamer | Un compte Twitch + streameur ou téléphone (l'overlay est un simple lien web) |

Pas besoin de compte ailleurs : le backend est **fourni et gratuit**.

---

## 3. Installation (10 minutes)

### Étape 1 — Installer l'app
1. Ouvre **Garmin Connect Mobile** → ta montre → **Activités & Apps** → **En savoir plus**
2. Cherche **BadScore** → **Installer**

### Étape 2 — Premier lancement
1. Lance BadScore sur la montre
2. L'écran affiche **« Configurez BadScore dans Garmin Connect »** avec un **point sombre** en haut à droite : c'est normal, il faut d'abord enregistrer ta montre (étape 3)

### Étape 3 — Enregistrer ta montre (obtenir ta clé)
1. Sur ton téléphone, ouvre le **portail d'enregistrement BadScore** (lien sur la fiche store)
2. Choisis un **canal** (un nom unique, ex. ton pseudo Twitch — c'est ce qui identifie tes matchs) et les **noms des joueurs** affichés
3. Le portail affiche **ta clé personnelle** — ⚠️ elle n'est montrée **qu'une seule fois**, copie-la tout de suite

### Étape 4 — Configurer Garmin Connect
1. GCM → ta montre → **Activités & Apps** → BadScore → **Réglages**
2. Colle ta **clé** dans le champ (c'est le seul réglage à faire)
3. **Redémarre ta montre** (obligatoire — Garmin Connect n'envoie les réglages à l'app qu'au redémarrage)

### Étape 5 — Vérifier
Relance BadScore : le point en haut à droite doit passer **vert** (au premier point marqué). C'est prêt. 🏸

---

## 4. Pendant un match — les boutons

| Bouton | Action |
|---|---|
| **START** | point pour toi |
| **BACK** | point pour l'adversaire |
| **UP** | annuler le dernier point |
| **DOWN** | demander la fin du set → **« TERMINER SET ? »** (DOWN = oui, BACK = non) |
| **UP (appui long)** | menu : Reprendre / Format / Reset / Quitter |
| **QUITTER** (dans le menu) | **abandonne le match** : le score est supprimé de la montre (prochain lancement = choix du format) et l'app se ferme |

### Les règles gérées automatiquement
- 21 points par set, **2 points d'écart** (cap à 30), **2 sets gagnants** le match
- À la fin d'un set : l'app propose « TERMINER SET ? », gère le changement de côté et le repos
- Fin de match : le score final reste affiché (et en ligne) jusqu'à ton prochain match
- Tu te trompes ? **UP annule** le dernier point, y compris après la confirmation de set

### Le point de sync (en haut à droite de l'écran score)

| Couleur | Signification | À faire |
|---|---|---|
| 🟢 Vert | dernier envoi confirmé par le serveur | rien |
| ⚪ Gris | envoi en cours | rien |
| 🔴 Rouge | erreur réseau (nouvel essai automatique en arrière-plan) | vérifier téléphone (Bluetooth) et GCM ; ça reprend tout seul |
| ⚫ Sombre | app non configurée | refaire l'installation (étapes 3-4) |

> ℹ️ **La sync fonctionne par lots** : la montre envoie les points par groupes (≤ 5, toutes les 5 s minimum) — une contrainte du Bluetooth. Si tu marque plusieurs points en rafale, l'overlay les suit par paliers de 5 à 10 s. Dans un vrai match (un échange toutes les 10-30 s), chaque point arrive en 1 à 3 s.

---

## 5. Côté viewers

### L'overlay (bandeau de score dans la vidéo)
Un simple lien web à mettre en browser source (OBS) ou à incruster via ton outil de stream :

```
https://marcsuarez74.github.io/badminton-score/overlay/?channel=TON_CANAL&name1=TOI&name2=ADVERSAIRE
```

Il suit **automatiquement** ton match actif — rien à toucher entre les matchs. Paramètres : `scale` (taille), `bg=0` (fond transparent).

### Le chat Twitch
- `!score` → le bot affiche le score immédiatement
- **Annonce automatique** : à chaque changement de score, le message s'affiche tout seul dans le chat (~5 s après le point) — aucune action nécessaire

---

## 6. Dépannage (FAQ)

**Le point reste rouge.**
→ La montre n'arrive pas à joindre le serveur : vérifie que le téléphone est appairé en Bluetooth, que GCM tourne en arrière-plan (non « tuée » par l'économiseur de batterie), puis attends — la reprise est automatique (backoff jusqu'à 2 min).

**L'overlay ne change pas alors que j'ai marqué.**
→ Latence normale de sync par lots (5-10 s en rafale). Si ça dure > 2 min, vérifie le point de sync et le canal dans l'URL de l'overlay.

**J'ai changé un réglage dans GCM, rien ne bouge.**
→ **Redémarre la montre** : Garmin Connect n'injecte les réglages qu'au redémarrage.

**Je ne trouve plus ma clé.**
→ Reviens sur le portail d'enregistrement et régénère une clé (l'ancienne est invalidée).

**Deux matchs s'affichent en même temps ?**
→ Impossible par design : créer un nouveau match **clôture automatiquement** le précédent de ta montre.

**Qui peut voir mes scores ?**
→ N'importe qui avec le lien de ton canal (c'est ce qui permet l'overlay et le `!score`). N'y mets pas d'informations personnelles dans les noms. Voir « Confidentialité » ci-dessous.

---

## 7. Confidentialité

- **Données stockées** : ton canal, les noms que tu choisis, les scores/événements de match, et l'**empreinte** (hash SHA-256) de ta clé — jamais la clé elle-même
- **Aucun compte, aucune donnée personnelle** (pas d'email, pas de nom réel requis)
- **Scores publics par design** : c'est ce qui permet aux viewers de les afficher ; ton canal est consultable par quiconque connaît son nom
- **Suppression** : demande via la page support — les matchs de ton canal sont supprimés, ta clé révoquée
- L'app ne lit ni contacts, ni position, ni santé ; elle n'envoie rien hors de ton action (un point marqué)

---

## 8. Support

- Bugs et questions : [GitHub Issues](https://github.com/marcsuarez74/badminton-score/issues)
- Montre compatible non listée ? Demande — chaque famille d'écran nécessite une validation, ajoutées au fil des demandes.
