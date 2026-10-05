# CLAUDE.md — harnais d'un site Spark

> Gabarit canonique. Chaque repo de site en a une **instance** : elle renvoie ici et n'ajoute que ce qui est propre
> au site (hôtes, bases, état des modules, mécanisme de déploiement, pièges locaux). Ne pas recopier ce fichier dans
> l'instance : une copie dérive. Une leçon qui vaut pour tous les sites remonte ici par PR.

## Ce qu'est Spark

Un **side-stack** : un Mac mini posé à côté des systèmes de l'entreprise, qui les fait parler entre eux sans rien
remplacer. **La source de vérité business reste le système métier** (CRM, ERP, Sheets, facturation…). NocoDB est un
staging, ou la source d'une donnée qui n'existait nulle part avant. n8n est le pont contrôlé vers les systèmes métier.

| Terme | Sens |
|---|---|
| **Spark** | la méthode et le kit (ce repo, `spark-kit`), pas un site |
| **Site** | un déploiement : 1 Mac mini, 1 entreprise, 1 domaine, 1 repo |
| `SPARK_PREFIX` | slug du site qui forme les hôtes `<prefix>-<service>.<domaine>` |

## Méthode

1. **Cycle** : discovery → fiche-logiciel (`ingest-legacy-docs.md`) → PRD (`prd-template.md`) → réalisation →
   script `validate-*.sh` = définition du « fini ». Détail : skill `spark-poc-method`.
2. **Analyse d'impact avant toute évolution d'un site en prod**, même pour un outil « neuf » (PRD §8bis) : chaque
   élément touché est classé ✅ / ⚠️ / ⛔ / 🔁 avec sa source ; un conflit est une question à l'owner, jamais une
   correction implicite. Elle dit aussi s'il faut amender un PRD ou en ouvrir un (règle dans les notes du gabarit).
3. **Critères d'acceptation = assertions** d'un script nommé (PRD §5.3), nominal et refus, tous verts avant `live`.
4. **Non-régression** : toute sortie existante qui doit rester identique (export, écran, rapport) a un banc
   avant/après dans l'ordre de mise en prod (PRD §9.4).
5. **Branche ou worktree** pour tout changement de code ; jamais de `checkout` dans le dossier servi par la prod
   (les tâches planifiées y supposent `main`).
6. **Déploiement prod = confirmation humaine explicite**, par le mécanisme défini dans l'instance du site.
   Sauvegarder l'état (workflow, schéma) avant, et savoir revenir en arrière.
7. **Leçons** : bloc daté dans `LESSONS-LEARNED.md` du site ; si elle vaut pour tous les sites, PR ici.

## Skills — les charger avant d'écrire

| Avant de… | Skill |
|---|---|
| créer ou modifier une table, un lien, un workflow n8n qui lit/écrit NocoDB | `spark-nocodb-v3-patterns` **et** `spark-n8n-pseudo-api` |
| toucher une page front (vhost `-app`) | `spark-frontend-patterns` |
| toucher compose, Caddy, tunnel, secrets, ou diagnostiquer un conteneur | `spark-stack-ops` |
| cadrer un POC, écrire une fiche ou un PRD | `spark-poc-method` |
| appeler l'API NocoDB v3 (référence + CLI `nocodb.sh`) | `nocodb` |
| configurer un node, écrire une expression ou un Code node n8n | les skills `n8n-*` |

Pourquoi : le détail des ~40 pièges vit dans ces skills (versionnées dans `skills/`), pas ici. Les ignorer coûte
des heures de debug par session (vécu sur le premier gros build).

## Les 5 pièges silencieux

Ils échouent **sans erreur** et ont déjà coûté cher en prod. Le reste est dans les skills.

- **Lecture tronquée (W28)** : un fetch NocoDB s'arrête à sa taille de page sans rien dire → paginer, ou lever une
  erreur au plafond, jamais rendre un résultat partiel.
- **Lien ajouté au lieu de remplacé (N34)** : `POST /links` ajoute, même sur un `belongsTo` → le record a deux
  liens et les lecteurs voient l'ancien. Re-lier = lire, supprimer, poser, relire.
- **Suppression en masse plafonnée (N2)** : au-delà de 10 records par appel, le delete n'efface rien, sans erreur →
  lots de 10 et vérifier le retour.
- **Requêtes qui explosent avec le volume (N29/N33)** : un Lookup dans un fetch liste devient superlinéaire ; côté
  front, une requête par ligne lancée toutes en même temps fait tomber tout le monde → requête inverse ou jointure,
  et parallélisme borné (6).
- **Branches parallèles n8n (W9)** : le fan-in rend `undefined` au hasard → tout en chaîne séquentielle.

## Accès aux instances

- **n8n : API REST v1** (`/api/v1`, clé `N8N_API_KEY`). Patcher = GET → modifier le JSON avec des assertions sur
  l'état de départ → PUT. Un changement de graphe (nodes, connexions) exige `deactivate` puis `activate`.
- **NocoDB : CLI `nocodb.sh`** de la skill `nocodb` (API v3), token lu dans l'environnement, jamais affiché.
- **Pas de MCP** n8n ni NocoDB : pont stdio qui tombe en cours de session, conteneurs orphelins, incompatibilités
  avec NocoDB v3 récent.
- **Derrière Cloudflare Access** : les scripts du Mac hôte passent par le Caddy local (`127.0.0.1:<port>` + en-tête
  `Host`), les fronts appellent les webhooks en **relatif**. Un appel à l'URL publique prend un `302`.
  Détail : `docs/cf-access.md`.

## Règles non négociables

- Aucun secret dans le repo ; `.env` gitignored (vérifier `git status` avant de commiter) ; ne jamais afficher un
  token (`N8N_ENCRYPTION_KEY`, `NOCODB_API_TOKEN`, `CF_API_TOKEN`, clés métier). Secrets métier → credentials n8n.
- Ce repo et `spark-kit` sont **publics** : aucun nom de client, de personne ni de donnée réelle.
- Chaque vhost derrière Cloudflare Access, Caddy lié à `127.0.0.1`. Détail : `spark-kit/SECURITY.md`.

## Où trouver quoi

| Besoin | Fichier |
|---|---|
| Services, ports, structure d'un repo de site, sizing, limites NocoDB CE, montage de fichiers dans n8n, clés API | `docs/reference-stack.md` |
| Cloudflare Access, tunnel, Caddy | `docs/cf-access.md`, `docs/cloudflared.md`, `docs/caddy.md` |
| Catalogue complet des pièges | `docs/pieges-nocodb-n8n.md` (et les skills) |
| Installer une machine ou un site | `GETTING-STARTED.md`, `setup-skeleton/` |
| Gabarits | `prd-template.md`, `ingest-legacy-docs.md` |
| Sécurité, incidents | `spark-kit/SECURITY.md`, `spark-kit/INCIDENTS.md` |
