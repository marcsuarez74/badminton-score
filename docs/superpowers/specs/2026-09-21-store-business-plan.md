# Business plan — Publication BadScore sur le store Connect IQ

- **Date** : 2026-09-21
- **Statut** : proposition à relire par le propriétaire — rien n'est lancé
- **Prérequis factuel** : audit RLS effectué le 21/09 (cf. §3) ; état app : v1 fonctionnelle (score, sync, overlay, chat, annonceur), sideload sur epix2 pro 51mm + fr55

---

## 1. Vision et positionnement

**Produit** : BadScore — app Garmin qui tient le score de badminton au poignet et publie en direct : overlay vidéo (Twitch/YouTube) + score dans le chat, sans ordinateur et sans manipulation pendant le match.

**Cible** : joueurs de badminton qui filment/streament leurs matchs (amateurs motivés, clubs, coachs). Niche assumée : peu d'apps CIQ de score sport de raquette, aucune (à notre connaissance) avec sync cloud + overlay stream.

**Différenciateurs** : offline-first (le score marche sans réseau), « zéro manipulation » pendant le match (sync automatique, chat auto-annoncé), overlay prêt à l'emploi.

**Posture honnête** : projet passion à vocation semi-pro. L'objectif du store n'est pas le revenu, mais : (a) une distribution propre (pas de sideload artisanal), (b) des retours utilisateurs, (c) couvrir les petits coûts d'infra.

---

## 2. Modèle de publication

| Sujet | Décision proposée | Note |
|---|---|---|
| Canaux | Store Connect IQ (app payante), Garmin gère paiement + distribution | Développeur ≈ 70 % / Garmin ≈ 30 % `[À VÉRIFIER dans l'accord développeur]` |
| Modèle | **Achat unique** (pas d'abonnement) — prix par app, valable toutes montres | Le store CIQ ne gère pas les essais « serveur » ; une version démo séparée est possible mais double la maintenance `[À VÉRIFIER : mécanique trial 2026]` |
| Backend | **Backend partagé fourni** (Supabase du projet) : l'utilisateur enregistre sa montre sur une page web, reçoit une clé device, la saisit dans GCM | Alternative « BYO Supabase » écartée : friction rédhibitoire pour le grand public |
| Coût backend | Free tier au départ ; **Supabase Pro 25 $/mois** dès que les limites (surtout egress Realtime) approchent | Coût marginal par utilisateur quasi nul (données minuscules) |

---

## 3. Sécurité — état actuel (audité le 21/09/2026) et chantiers

**Constat en prod** (pg_policies) :

| Table | Accès anon | Commentaire |
|---|---|---|
| `matches`, `match_state`, `events` | **SELECT uniquement** | Lecture publique nécessaire à l'overlay/chat — aucune écriture publique |
| `devices`, `chat_announce` | **aucune policy** | Service-role uniquement (Edge Functions) — invisible du public |

Écritures : uniquement via Edge Functions (`sync` authentifiée par clé device hashée SHA-256 côté serveur, `score-text`/`chat-announce` en lecture + clé partagée). TLS partout (Supabase).

**Chantiers avant store** (priorité ordonnée) :

1. **Portail d'enregistrement** (S2 ci-dessous) : page qui génère la clé device une seule fois (affichée puis hashée) + **throttling** anti-abus sur l'Edge Function d'enregistrement (table de compteurs, ex. 5 enregistrements/IP/jour)
2. **Rate-limit `sync`** : rejeter > N requêtes/minute par device (défense contre un client bugué ou malveillant)
3. **Politique de confidentialité** publique (GitHub Pages) : données = hash de clé, scores, noms de canal choisis par l'utilisateur ; scores **publics par design** (c'est la fonctionnalité) ; suppression sur demande ; aucun compte, aucun PII
4. Revue finale : pas de secret dans le repo (déjà vrai — clés dans `.secrets/` gitignées), pas de secret dans le build store (config = saisie utilisateur, cf. §4)

---

## 4. Paramétrage depuis GCM (Garmin Connect Mobile) — le chantier clé

**État actuel** : l'app lit `BackendConfig` (config cuite au build par `scripts/build-release.sh`) puis, à défaut, `Properties` (réglages GCM). Un build **store** est un build **unique** : la clé device ne peut pas être cuite (elle est personnelle) → **GCM devient le canal de configuration**.

**La simplification clé** : l'URL du backend est **identique pour tous** (notre Supabase) et **publique** (l'overlay l'utilise côté client). On la **cuit donc dans le build store** (`BackendConfig.BACKEND_URL` rempli, `DEVICE_KEY` vide) → **l'utilisateur ne saisit qu'une seule chose : sa clé device**. Seule limite : un utilisateur avancé ne peut pas brancher son propre backend (modèle « backend partagé » assumé, cf. §2).

**Le bug rencontré** (notes phase 4a, reproductible) : sur matériel, les **valeurs par défaut déclarées dans `settings.xml` ne sont pas appliquées** — `Properties.getValue()` renvoie `null` tant que l'utilisateur n'a pas ouvert la page de réglages GCM de l'app. Sur simulateur, les défauts fonctionnent. Ce bug **ne bloque pas notre parcours** (l'utilisateur ouvre de toute façon les réglages pour coller sa clé — situation où `Properties` fonctionne), mais il interdit de pré-remplir quoi que ce soit et impose le reboot après réglage :

| Impact | Traitement (déjà en place pour partie) |
|---|---|
| App store non configurée au 1er lancement | État `SYNC_ST_OFF` implémenté : point de sync **sombre** + message écran « Configurez BadScore dans Garmin Connect » |
| Défauts ignorés | Ne PAS compter sur les défauts : traiter `null` = « non configuré » (jamais de fallback implicite) |
| Changement de réglages GCM | Exiger un **reboot de la montre** (constat GCM 5.29) — à documenter dans la fiche store + guide utilisateur |

**Parcours utilisateur (S1/S2)** :

| # | Étape | Où |
|---|---|---|
| 1 | Installe l'app (store), la lance → écran « Configurez BadScore dans Garmin Connect » (point sombre) | Montre |
| 2 | Ouvre le **portail d'enregistrement** : choisit un canal + noms → reçoit **sa clé device** (affichée une seule fois) | Navigateur (téléphone) |
| 3 | GCM → montre → BadScore → Réglages → **colle la clé** (seul champ) | GCM |
| 4 | **Reboot la montre** | — |
| 5 | Relance → point de sync vert | Montre |

**Travail** (phase S1) :
- `settings.xml` : **1 champ** — `deviceKey` (l'URL étant cuite) ; valeur par défaut **vide** et assumée
- Écran d'accueil : si non configuré → guide pas-à-pas (1. portail → clé, 2. GCM → coller, 3. reboot)
- **Ticket support Garmin** pour le bug des défauts (annexe A — texte prêt, à poster avec le firmware exact)

---

## 5. Compatibilité montres

**Approche** : progressif — chaque famille d'écran exige une passe RNE (recette) + une validation layout.

| Version | Familles | Montres | État |
|---|---|---|---|
| v1.0 | `square-280x280` + `round-208x208` | epix2 pro 51mm (validée en vrai), FR55 (validée RNE + build ami) | ✅ prêtes |
| v1.1 | `round-218x218`, `round-240x240` | FR165/265/965, Forerunner récents | à tester (RNE + layout pips/score) |
| v1.2 | `square-454x454` (Venu 3…), au fil des demandes | | à la demande |

Règle : **pas de famille activée sans RNE `PASSED` + capture validée** (le SDK local permet de tester chaque famille sans matériel).

---

## 6. Prix

**Recommandation : 2,99 € (achat unique)** — arrondi local géré par Garmin (base USD ≈ 2,99 $).

Justification :
- Apps CIQ comparables de score sport : 2-5 € ; au-dessus de 3 €, la friction explose pour une niche
- Perçu « outil sérieux » sans être cher ; ~2 € nets/vente après part Garmin `[À VÉRIFIER]`
- Le backend fourni est un argument de valeur (pas besoin de compte Supabase) et coûte ~0 par utilisateur

Scénarios honnêtes (après ~30 % Garmin) :

| Ventes | Revenu brut | Net développeur |
|---|---|---|
| 20 | 60 € | ~42 € |
| 100 | 300 € | ~210 € |
| 500 | 1 500 € | ~1 050 € |

Objectif réaliste année 1 : quelques dizaines à centaines de ventes via les communautés badminton (clubs, r/badminton, groupes FB/Discord FR).

---

## 7. Assets de fiche store (checklist)

| Item | État / à faire |
|---|---|
| Icône launcher (wordmark « Bad » vert, zéro licence) | ✅ faite (60×60 + 35×35) — décliner aux tailles store `[tailles exactes : guide CIQ]` |
| Captures d'écran par famille | À produire depuis le simulateur SDK (fond propre, score visible) — 3-5 par famille |
| Description courte + longue | À écrire (FR + EN) — angle : « le score de badminton au poignet, en direct sur ton stream » |
| **Guide utilisateur détaillé** | `docs/guide-utilisateur.md` (source) → publié sur GitHub Pages, lié depuis la fiche store (installation, configuration pas-à-pas, boutons, point de sync, dépannage, confidentialité) |
| Mots-clés | badminton, score, streaming, overlay, Twitch |
| Politique de confidentialité | cf. §3.3 — page GitHub Pages |
| URL support | GitHub issues du repo |
| Crédits/licences | Police Archivo (OFL) mentionnée ; icône texte pur (aucun asset tiers) |
| Version + notes de version | v1.0.0 — par famille activée |
| Compte développeur Garmin | À créer + accord développeur + infos fiscales `[À VÉRIFIER : TVA gérée par Garmin ?]` |

---

## 8. Roadmap de publication

| Phase | Contenu | Estimation |
|---|---|---|
| **S1 — Configurable** | settings GCM (URL + clé), UX non configuré, ticket Garmin (annexe A), tests RNE 2 familles | 1 phase |
| **S2 — Onboarding** | portail d'enregistrement (génération de clé, throttling), rate-limit `sync`, politique de confidentialité | 1 phase |
| **S3 — Store assets** | captures, descriptions FR/EN, déclinaisons icônes, compte développeur | ½ phase (beaucoup de propriétaire) |
| **S4 — Soumission** | build store (épuré de tout secret), revue Garmin (délai inconnu `[À VÉRIFIER]`), corrections éventuelles | variable |
| **S5 — Post-lancement** | monitoring (logs Supabase), support issues, familles v1.1/v1.2 au fil des demandes | continu |

**Coûts récurrents à terme** : Supabase Pro 25 $/mois (seulement si croissance) ; VPS gratuit (gratuité collaborateur).

---

## Annexe A — Ticket support Garmin (prêt à poster sur forums.garmin.com/developer/connect-iq/i/bug-reports)

> **Subject:** Connect IQ SDK 9.2.0 — `settings.xml` defaults are not applied on real hardware: `Properties.getValue()` returns `null` until GCM settings page is opened
>
> **Environment:** Connect IQ SDK 9.2.0 (macOS), Garmin Connect Mobile 5.29 (Android), device: epix2 Pro 51mm, firmware `[FW À RELEVER SUR LA MONTRE]`.
>
> ### Summary
>
> A property declared in `settings.xml` with a default `<value>` entry behaves differently between the simulator and a real device:
>
> | Situation | Simulator | Real device |
> |---|---|---|
> | Fresh install, user never opened GCM settings for the app | `Properties.getValue()` returns the declared default ✅ | returns `null` ❌ |
> | User opened the GCM settings page at least once (no change made), then app relaunch | default returned ✅ | value available (default or last user value) ✅ |
> | User changed a value in GCM, watch not rebooted | immediate | change **not** seen until the watch is rebooted |
>
> ### Minimal repro
>
> `settings.xml` (the `<entry><value>` pair declares the default):
> ```xml
> <settings>
>   <property id="backendUrl" type="string">
>     <entry>
>       <property>Backend URL</property>
>       <value>https://example.com</value>
>     </entry>
>   </property>
>   <setting propertyKey="@Properties.backendUrl" title="@Strings.BackendUrlTitle">
>     <settingConfig type="alphaNoSpace" required="false"/>
>   </setting>
> </settings>
> ```
>
> App code, on first launch:
> ```monkeyc
> var url = Properties.getValue("backendUrl");
> System.println("url=" + url);   // Simulator: "url=https://example.com" / Device: "url=null"
> ```
>
> **Observed on device:** `null` on first launch — even though a default is declared. The app cannot tell "user left it empty" apart from "user never opened settings".
>
> **Expected:** the declared default should be returned on device as on the simulator (or the behavior documented).
>
> ### Real-world impact
>
> For a store app that needs user configuration (backend URL + device key), the first launch on a watch always behaves as "unconfigured", even for users who would have been fine with defaults. Our workaround is to treat `null` as "not configured" and show a setup prompt, which is acceptable — but the simulator/device discrepancy cost significant debugging time, and the reboot requirement after any GCM change is invisible to users (they think the app is broken).
>
> ### Questions
>
> 1. Is "defaults only applied after a GCM settings round-trip" intended behavior or a defect?
> 2. If intended, could it be documented in the Programmer's Guide (`Properties` / `settings.xml` sections)?
> 3. Is there a supported way to detect "user never opened settings" vs "user cleared the value"?
> 4. Is the reboot requirement after GCM settings changes expected? Could the app be notified (e.g. property-change callback) when values are refreshed?
