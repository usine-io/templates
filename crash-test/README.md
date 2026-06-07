# Crash Test — Premier jour avec Spark

> Tu viens d'installer la stack (README de spark-kit). Les services tournent, le tunnel est ouvert. Maintenant : est-ce que ca marche vraiment ? Et surtout : comment construire ton premier truc utile ?
>
> Ce guide se fait **entierement avec Claude Code**. Tu ne vas pas ecrire de scripts ni configurer des nodes a la main. Tu vas decrire ce que tu veux, Claude le fait via le MCP n8n (workflows) et le CLI NocoDB de la skill `nocodb` (tables, donnees).

---

## Avant de commencer

### Pre-requis

- [ ] Stack Spark qui tourne (`docker-compose up -d`, les 4 services healthy)
- [ ] Tunnel Cloudflare ouvert (`https://<prefix>-n8n.<domain>` repond)
- [ ] Compte owner cree dans n8n + compte admin dans NocoDB
- [ ] Cles API renseignees dans `.env` (`N8N_API_KEY`, `NOCODB_API_TOKEN`)
- [ ] Claude Code lance dans le repo du site, avec les MCP connectes

### Verifier l'outillage live

Avant tout, tape dans Claude Code :

> Liste les workflows n8n existants et les tables NocoDB.

Claude appelle le MCP n8n (workflows) et le CLI `nocodb.sh` de la skill (tables). Si les deux repondent avec des listes (meme vides), l'outillage fonctionne. Si l'un echoue :
- **n8n** : revoir la section "Travailler avec Claude Code" du README spark-kit (verifier `.mcp.json`, `N8N_API_KEY`, `docker-compose ps`).
- **NocoDB** : verifier que `NOCODB_API_TOKEN` est dans `.env` et que la skill `nocodb` est installee globalement.

---

## Etape A — Smoke test : les 3 routes fondamentales

Avant de construire quoi que ce soit de metier, on verifie que **n8n et NocoDB se parlent dans les deux sens**. Ces 3 routes sont le substrat de tout ce qu'on construira ensuite — si l'une ne passe pas, aucun POC n'est possible.

### Les 3 routes

| # | Route | Ce qu'on prouve |
|---|-------|-----------------|
| **R1** | n8n → NocoDB (ecriture) | n8n peut creer des lignes dans NocoDB via l'API |
| **R2** | NocoDB → n8n (trigger) | Un evenement dans NocoDB peut declencher un workflow n8n |
| **R3** | n8n → NocoDB (lecture) | n8n peut lire et filtrer des donnees dans NocoDB |

### Le scenario

On va creer une boucle : un "ping" entre dans n8n, s'ecrit dans NocoDB, NocoDB notifie n8n, qui va relire le ping et ecrire un "echo". Si l'echo apparait, les 3 routes fonctionnent.

```
   curl POST
       │
       ▼
  ┌──────────────┐                    ┌────────────┐
  │ workflow      │ ──── R1 ────────▸ │ _t_pings   │
  │ _t_ping       │   POST record    │            │
  │ (webhook in) │                    └──────┬─────┘
  └──────────────┘                           │
                                             │ AFTER INSERT (webhook NocoDB)
                                             ▼  R2
  ┌──────────────┐                    ┌──────────────┐
  │ _t_echoes    │ ◀── R1 ──────────│ workflow      │
  │              │   POST record    │ _t_echo       │
  └──────────────┘                    │ (webhook in) │
                                      │  ↑ R3 : GET  │
                                      │  le ping     │
                                      └──────────────┘
```

**Critere de succes** : un seul `curl POST` produit 1 ligne dans `_t_pings` ET 1 ligne dans `_t_echoes` avec le `ping_id` correspondant, en moins de 5 secondes.

### Prompt 1 — Creer les tables

> Cree une base `_t_smoke` dans NocoDB avec 2 tables :
>
> `_t_pings` : colonnes `source` (SingleLineText), `payload` (LongText). Les colonnes Id et CreatedTime sont automatiques.
>
> `_t_echoes` : colonnes `ping_id` (Number), `note` (LongText). Id et CreatedTime automatiques aussi.
>
> Confirme-moi les IDs des tables une fois creees.

Claude va utiliser le CLI `nocodb.sh` de la skill `nocodb` (API v3) pour creer la base et les tables. Il te donnera les IDs — tu en auras besoin pour la suite (Claude les retient dans le contexte).

### Prompt 2 — Creer le credential NocoDB dans n8n

> Cree un credential dans n8n de type "Header Auth" :
> - Nom : "NocoDB API _t_smoke"
> - Header : `xc-token`
> - Valeur : le token API NocoDB (celui dans .env a la ligne NOCODB_API_TOKEN)
>
> Donne-moi l'ID du credential cree.

Ce credential sera utilise par les workflows pour s'authentifier aupres de NocoDB.

### Prompt 3 — Creer le workflow "ping"

> Cree un workflow n8n appele `[SMOKE] _t_ping` :
> - Trigger : Webhook, methode POST, path `/_t_ping`
> - Action : HTTP Request POST vers NocoDB pour creer un record dans `_t_pings` avec `source` = "smoke-test" et `payload` = le body recu par le webhook
> - Utilise le credential "NocoDB API _t_smoke" pour l'authentification
>
> Active le workflow.

### Prompt 4 — Creer le workflow "echo"

> Cree un workflow n8n appele `[SMOKE] _t_echo` :
> - Trigger : Webhook, methode POST, path `/_t_echo`
> - Action 1 : extraire le `ping_id` du payload recu (dans `data.rows[0].Id`)
> - Action 2 : HTTP Request GET vers NocoDB pour lire le record du ping correspondant dans `_t_pings` (route R3)
> - Action 3 : HTTP Request POST vers NocoDB pour creer un record dans `_t_echoes` avec `ping_id` = l'Id du ping et `note` = "echo'd ping #<id> at <timestamp>"
> - Utilise le credential "NocoDB API _t_smoke"
>
> Active le workflow.

### Prompt 5 — Configurer le webhook sortant NocoDB

> Configure un webhook sortant dans NocoDB sur la table `_t_pings` :
> - Evenement : AFTER INSERT
> - URL cible : `https://<prefix>-n8n.<domain>/webhook/_t_echo`
> - Methode : POST
> - Envoyer les donnees de la ligne inseree dans le body
>
> Utilise le format webhook v3 de NocoDB.

> **Note** : remplacer `<prefix>` et `<domain>` par les valeurs reelles de ton site.

### Prompt 6 — Tester

> Teste le smoke test : envoie un POST sur le webhook `_t_ping` avec un payload JSON `{"test": "premier ping"}`.
>
> Ensuite, verifie dans NocoDB :
> 1. Qu'une ligne est apparue dans `_t_pings`
> 2. Qu'une ligne est apparue dans `_t_echoes` avec le bon `ping_id`
>
> Dis-moi si les 3 routes sont validees.

### Ca ne marche pas ?

| Symptome | Cause probable | Solution |
|----------|---------------|----------|
| R1 echoue (n8n ne peut pas ecrire) | Token `xc-token` invalide ou expire | Regenerer le token NocoDB, mettre a jour le credential n8n |
| R2 echoue (NocoDB ne trigger pas) | Le webhook sortant utilise le format v2 (deprecie) | Reconfigurer en v3 : `operation: ["insert"]` (array), body `{{ json data }}` |
| R2 echoue (timeout/404) | NocoDB n'atteint pas n8n sur le reseau Docker | Verifier que l'URL du webhook utilise le hostname externe (via tunnel), pas `n8n:5678` |
| R3 echoue (lecture vide) | Filtre `where` mal forme | Syntaxe NocoDB : `(Id,eq,<value>)` — pas de guillemets autour de la valeur numerique |
| Tout echoue | MCP non connectes | Verifier `.mcp.json`, relancer Claude Code |

### Nettoyer

Quand le smoke test est valide :

> Supprime les 2 workflows de smoke test dans n8n, le webhook sortant dans NocoDB, et les 2 tables `_t_pings` / `_t_echoes`. Garde la trace de ce qui a marche dans un commentaire ou dans LESSONS-LEARNED.md.

Le smoke test a prouve que la plomberie fonctionne. On passe aux choses serieuses.

---

## Etape B — Ton premier use case : de l'idee au prototype

Le smoke test etait technique. Maintenant on va construire un **vrai outil** — et cette fois, c'est toi qui decides ce que tu veux construire. Claude t'aide a le concevoir et l'implemente via les MCP.

L'exemple ci-dessous utilise un mini-CRM (suivi de prospects et relances), mais le processus est le meme pour n'importe quel besoin : suivi de stock, gestion de tickets SAV, planning d'atelier...

### Etape B.1 — Exprimer ton besoin

Le prompt le plus important de tout le guide. Pas de jargon technique, pas de specs — juste ton besoin, comme tu l'expliquerais a un collegue.

> /plan
>
> Je veux un outil pour suivre mes prospects et mes relances commerciales. On est une petite equipe de 3 commerciaux. Aujourd'hui on fait tout dans un fichier Excel partage et on oublie de rappeler les gens.
>
> Ce que je veux pouvoir faire :
> - Voir tous mes prospects et ou ils en sont
> - Enregistrer une relance (appel, email, rdv) sans ouvrir NocoDB directement
> - Voir un tableau de bord avec les deals en cours et les relances de la semaine
>
> C'est un prototype pour valider l'approche, pas un produit fini. Donnees fictives pour commencer.

Le `/plan` est important : il demande a Claude de **proposer une architecture avant de coder**. Claude va :

1. Analyser ton besoin
2. Proposer un schema de tables NocoDB (quelles entites, quelles relations)
3. Identifier les operations qui necessitent un "pont" n8n (celles qui touchent plusieurs tables)
4. Proposer des ecrans (pages HTML simples servies par Caddy sur `<prefix>-app.<domain>`)
5. Te soumettre le plan pour validation

**Ce que tu dois verifier dans le plan** :

- [ ] Les tables proposees couvrent ton besoin (pas plus, pas moins)
- [ ] Les relations entre tables ont du sens (un contact appartient a une entreprise, etc.)
- [ ] Les endpoints n8n ne font pas de CRUD basique (sinon, utiliser un formulaire NocoDB natif suffit)
- [ ] Le scope est raisonnable pour un premier prototype (pas de multi-auth, pas d'import legacy, pas de notifications)

Si quelque chose ne te convient pas, dis-le :

> Le plan est bien mais je n'ai pas besoin de la table Activities pour le moment, on verra ca apres. Et pour les deals, je prefere des colonnes "montant" et "probabilite" plutot que juste "stage".

Claude ajuste et te repropose. Quand tu es satisfait, valide le plan.

### Etape B.2 — Claude implemente

Une fois le plan valide, Claude cree tout via les MCP :

1. **Tables NocoDB** avec les colonnes et relations
2. **Donnees fictives** pour que l'outil ne soit pas vide (tu peux demander le volume : "mets 5 entreprises et une dizaine de contacts")
3. **Workflows n8n** pour les operations composees (celles qui touchent plusieurs tables ou ont des effets de bord)
4. **Pages HTML** dans `apps/` servies par Caddy sur `<prefix>-app.<domain>`

Tu n'as rien a faire pendant cette phase, mais **garde un oeil** sur ce que Claude cree. Si tu vois quelque chose qui te surprend :

> Attends — pourquoi tu crees un endpoint pour ca ? Un formulaire NocoDB natif ne suffirait pas ?

C'est la bonne question a poser. La regle :

| Situation | Bon outil |
|-----------|-----------|
| Saisie dans une seule table, champs simples | Formulaire NocoDB natif (zero code) |
| Saisie qui met a jour plusieurs tables, ou qui a des effets de bord | Endpoint n8n (pseudo-API) |
| Lecture simple, filtres, tris | Vue NocoDB partagee (iframe ou lien direct) |
| Dashboard avec KPIs calcules, donnees croisees | Page HTML + appel API n8n |

### Etape B.3 — Tester

Une fois l'implementation terminee, verifie que tout marche :

> Teste le prototype :
> 1. Ouvre la page d'accueil sur `https://<prefix>-app.<domain>/apps/` et verifie qu'elle charge
> 2. Soumets le formulaire de saisie avec des donnees de test
> 3. Verifie que les donnees apparaissent dans NocoDB
> 4. Verifie que le dashboard affiche des chiffres coherents
>
> Dis-moi ce qui marche et ce qui ne marche pas.

Claude va tester chaque composant et te faire un rapport. Si quelque chose casse, il debuggue et corrige.

### Etape B.4 — Documenter ce qu'on a appris

Derniere etape, souvent negligee et pourtant la plus utile pour la suite :

> Ecris un paragraphe dans LESSONS-LEARNED.md qui resume :
> - Ce qu'on a construit (schema, endpoints, pages)
> - Ce qui a marche du premier coup
> - Ce qui a casse et comment on l'a corrige
> - Les decisions qu'on a prises et pourquoi (formulaire natif vs API, scope reduit, etc.)

---

## Et apres ?

Tu as un prototype qui tourne. Voici les chemins possibles :

### Ajouter des features au prototype

> /plan
>
> Le mini-CRM marche bien. J'aimerais ajouter des notifications : quand une relance est en retard de plus de 3 jours, envoyer un email a l'adresse du commercial assigne.

### Connecter un logiciel existant

Tu veux brancher un CRM, un ERP, une facturation ? Le reflexe en 3 temps :

1. **Trouve la doc API** du logiciel et copie le lien
2. **Cree le credential** dans n8n (`Settings > Credentials > Add Credential`) — c'est la que vit la cle API, pas dans un fichier
3. **Dis a Claude** :

> Voici la doc API de MonLogiciel : [lien]. J'ai cree un credential "MonLogiciel API" dans n8n. Cree un workflow qui recupere les donnees du jour et les ecrit dans NocoDB.

Le guide complet (types de credentials, OAuth2, conventions de nommage) est dans [`BIENVENUE.md` § "Connecter une API externe"](../BIENVENUE.md#connecter-une-api-externe).

Pour un branchement plus complexe (documentation du logiciel legacy, cadrage du POC), suis aussi [`ingest-legacy-docs.md`](../ingest-legacy-docs.md) puis [`prd-template.md`](../prd-template.md).

### Recommencer avec un autre use case

Le CRM etait un exercice. Ton vrai besoin est peut-etre un suivi de stock, un planning d'atelier, un outil de ticketing SAV. Reprends l'etape B.1 avec ton vrai besoin — le processus est le meme.

---

## Resume des prompts cles

| Etape | Prompt | Ce que Claude fait |
|-------|--------|--------------------|
| A.1 | "Cree les tables de smoke test" | Tables NocoDB via MCP |
| A.2 | "Cree le credential NocoDB dans n8n" | Credential via MCP |
| A.3-4 | "Cree les workflows ping/echo" | Workflows n8n via MCP |
| A.5 | "Configure le webhook sortant" | Webhook NocoDB via MCP |
| A.6 | "Teste le smoke test" | Curl + verification via MCP |
| **B.1** | **"/plan — je veux un outil pour..."** | **Plan d'architecture (le plus important)** |
| B.2 | *(Claude execute le plan valide)* | Tables + seed + workflows + pages |
| B.3 | "Teste le prototype" | Validation E2E |
| B.4 | "Documente dans LESSONS-LEARNED" | Capitalisation |

Le prompt B.1 est celui qui fait la difference. Plus tu decris ton besoin en termes metier (pas techniques), mieux Claude concoit l'architecture. Tu n'as pas besoin de savoir ce qu'est un webhook ou une pseudo-API — c'est le travail de Claude.

---

*Crash test v1.0 (2026-05-12). Inspire du premier deploiement Spark en production.*
