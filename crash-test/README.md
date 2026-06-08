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
| **R2** | n8n → n8n (chainage) | Un workflow n8n peut en declencher un autre via webhook interne |
| **R3** | n8n → NocoDB (lecture) | n8n peut lire et filtrer des donnees dans NocoDB |

### Le scenario

On va creer une boucle : un "ping" entre dans n8n, s'ecrit dans NocoDB, puis le meme workflow appelle un deuxieme workflow "echo" via HTTP interne, qui relit le ping et ecrit un "echo". Si l'echo apparait, les 3 routes fonctionnent.

```
   curl POST
       │
       ▼
  ┌──────────────┐                    ┌────────────┐
  │ workflow      │ ──── R1 ────────▸ │ _t_pings   │
  │ _t_ping       │   POST record    │            │
  │ (webhook in) │                    └────────────┘
  │              │
  │  R2 : HTTP ──┼──────────────────────────┐
  │  interne     │                          ▼
  └──────────────┘                    ┌──────────────┐
                                      │ workflow      │
  ┌──────────────┐                    │ _t_echo       │
  │ _t_echoes    │ ◀── R1 ──────────│ (webhook in) │
  │              │   POST record    │  ↑ R3 : GET  │
  └──────────────┘                    │  le ping     │
                                      └──────────────┘
```

**Critere de succes** : un seul `curl POST` produit 1 ligne dans `_t_pings` ET 1 ligne dans `_t_echoes` avec le `ping_id` correspondant, en moins de 5 secondes.

> **Note sur R2** : dans l'ideal, R2 serait un webhook sortant NocoDB (AFTER INSERT) qui declenche `_t_echo`. En pratique, les webhooks sortants NocoDB ne se declenchent pas sur les inserts via API dans CE 2026.06.0 (regression probable). On utilise donc un chainage workflow→workflow (W23) : `_t_ping` appelle `_t_echo` directement via HTTP interne apres l'insert. Ca prouve la meme chose : un evenement en base declenche un traitement downstream. L'alternative webhook NocoDB est documentee en [annexe](#annexe--webhook-sortant-nocodb-alternative-r2).

### Prompt 1 — Creer les tables

> Cree une base `_t_smoke` dans NocoDB avec 2 tables :
>
> `_t_pings` : colonnes `source` (SingleLineText), `payload` (LongText).
>
> `_t_echoes` : colonnes `ping_id` (Number), `note` (LongText).
>
> Les colonnes Id et CreatedTime sont automatiques, ne les cree pas.
>
> Confirme-moi les IDs des tables une fois creees.

Claude va utiliser le CLI `nocodb.sh` de la skill `nocodb` (API v3) pour creer la base et les tables. Il te donnera les IDs — tu en auras besoin pour la suite (Claude les retient dans le contexte).

**Attention CLI NocoDB** : la commande `table:create` cree la table mais **pas les colonnes** (meme si on passe `columns` dans le JSON). Il faut creer chaque colonne separement via `field:create` apres la table. Le format attendu :

```json
{"title": "source", "type": "SingleLineText"}
```

Le champ s'appelle `type` (pas `uidt`).

<details>
<summary><strong>Mini-reference CLI <code>nocodb.sh</code></strong> — commandes utilisees dans le smoke test</summary>

Le CLI est dans `~/.claude/skills/nocodb/scripts/nocodb.sh`. Alias recommande : `alias nc="bash ~/.claude/skills/nocodb/scripts/nocodb.sh"`. Help complet : `nc --help`.

**Ordre des arguments** : toujours `workspace → base → table → field → record`.

```bash
# Prealable : charger les variables d'environnement
set -a; source infra/.env; set +a
export NOCODB_TOKEN="$NOCODB_API_TOKEN"
export NOCODB_URL="http://127.0.0.1:${SPARK_HOST_HTTP_PORT:-18080}"
export NOCODB_HOST_HEADER="${SPARK_PREFIX}-db.${SPARK_DOMAIN}"

# Creer une base (dans un workspace)
nc base:create <workspace> '{"title":"_t_smoke"}'
# → retourne l'ID de la base (pXXX...)

# Creer une table (dans une base) — SANS colonnes
nc table:create <base> '{"title":"_t_pings"}'
# → retourne l'ID de la table (mXXX...)

# Creer un champ (dans une base + table) — APRES la table
nc field:create <base> <table> '{"title":"source","type":"SingleLineText"}'
nc field:create <base> <table> '{"title":"payload","type":"LongText"}'

# Lister les champs (verifier la creation)
nc field:list <base> <table>

# Creer un record
nc record:create <base> <table> '{"fields":{"source":"smoke-test","payload":"hello"}}'

# Lire les records
nc record:list <base> <table>

# Nettoyage
nc table:delete <base> <table>
nc base:delete <base>

# Fin
unset NOCODB_TOKEN NOCODB_API_TOKEN
```

**Pieges courants** :
- `base:create` attend un **JSON** (`'{"title":"..."}'`), pas une string simple
- `field:create` prend **3 arguments** (`<base> <table> '<json>'`), pas 2
- Les noms fonctionnent a la place des IDs (`nc record:list _t_smoke _t_pings`), mais les IDs sont plus rapides — ajouter `NOCODB_VERBOSE=1` pour les voir

</details>

### Prompt 2 — Creer le credential NocoDB dans n8n

> Cree un credential dans n8n de type `nocoDbApiToken` :
> - Nom : `NocoDB API _t_smoke`
> - `apiToken` : le token API NocoDB (celui dans `.env` a la ligne `NOCODB_API_TOKEN`)
> - `host` : `http://nocodb:8080` (URL interne Docker)
>
> Donne-moi l'ID du credential cree.

**Important** : le type est `nocoDbApiToken` (credential natif n8n), pas Header Auth. Le MCP n8n n'a pas de tool fiable pour creer des credentials. Deux options :

1. **Via l'API REST n8n** (automatisable par Claude) :
   ```
   POST http://n8n:5678/api/v1/credentials
   ```
   avec le body adequat et le header `X-N8N-API-KEY`.

2. **Via l'UI n8n** (manuel) : Settings → Credentials → Add Credential → chercher "NocoDB". Remplir `apiToken` et `host`.

### Prompt 3 — Creer le workflow "ping"

> Cree un workflow n8n appele `[SMOKE] _t_ping` :
>
> 1. **Trigger** : Webhook, methode POST, path `/_t_ping`
> 2. **Code node "Prep insert"** : construit le body d'insert NocoDB v3 et le serialise en string :
>    ```js
>    const body = {
>      fields: {
>        source: "smoke-test",
>        payload: JSON.stringify($json.body)
>      }
>    };
>    return [{ json: { insert_body: JSON.stringify(body) } }];
>    ```
> 3. **HTTP Request "Insert ping"** : POST vers NocoDB pour creer un record dans `_t_pings`
>    - URL : `http://nocodb:8080/api/v3/data/<base_id>/<table_id>/records`
>    - Body : `={{ $json.insert_body }}` (jsonBody, expression qui injecte la string du Code node)
>    - Credential : `NocoDB API _t_smoke`
> 4. **Code node "Prep echo call"** : construit le payload pour appeler `_t_echo` (simule ce qu'un webhook NocoDB aurait envoye) :
>    ```js
>    const inserted = $json;
>    const payload = {
>      data: { rows: [{ Id: inserted.records[0].id }] }
>    };
>    return [{ json: { echo_payload: JSON.stringify(payload) } }];
>    ```
> 5. **HTTP Request "Call echo"** : POST vers `http://n8n:5678/webhook/_t_echo`
>    - Body : `={{ $json.echo_payload }}` (jsonBody)
>
> Active le workflow.

**Points cles** :
- Le format d'insert NocoDB v3 est `{"fields": {...}}` — un seul objet, pas de wrapper `records` (le wrapper `records` n'existe que dans la reponse).
- Le Code node produit une **string** (`JSON.stringify`), le HTTP Request la consomme via l'expression `={{ $json.insert_body }}`. C'est le pattern W3 documente dans les skills Spark.
- L'etape 4-5 est le chainage W23 : `_t_ping` appelle `_t_echo` via HTTP interne au lieu d'attendre un webhook NocoDB.

### Prompt 4 — Creer le workflow "echo"

> Cree un workflow n8n appele `[SMOKE] _t_echo` :
>
> 1. **Trigger** : Webhook, methode POST, path `/_t_echo`
> 2. **Code node "Extract ping_id"** : extrait l'Id du ping depuis le payload recu :
>    ```js
>    const pingId = $json.body.data.rows[0].Id;
>    return [{ json: { ping_id: pingId } }];
>    ```
> 3. **HTTP Request "Read ping"** (route R3) : GET vers NocoDB pour relire le record du ping
>    - URL : `http://nocodb:8080/api/v3/data/<base_id>/<t_pings_id>/records/<ping_id>`
>    - Credential : `NocoDB API _t_smoke`
> 4. **Code node "Prep echo insert"** : construit le body d'insert pour `_t_echoes` :
>    ```js
>    const pingId = $json.id;
>    const body = {
>      fields: {
>        ping_id: pingId,
>        note: `echo'd ping #${pingId} at ${new Date().toISOString()}`
>      }
>    };
>    return [{ json: { insert_body: JSON.stringify(body) } }];
>    ```
> 5. **HTTP Request "Insert echo"** : POST vers NocoDB pour creer un record dans `_t_echoes`
>    - URL : `http://nocodb:8080/api/v3/data/<base_id>/<t_echoes_id>/records`
>    - Body : `={{ $json.insert_body }}` (jsonBody)
>    - Credential : `NocoDB API _t_smoke`
>
> Active le workflow.

### Prompt 5 — Tester

> Teste le smoke test : envoie un POST sur le webhook `_t_ping` avec un payload JSON `{"test": "premier ping"}`.
>
> Ensuite, verifie dans NocoDB :
> 1. Qu'une ligne est apparue dans `_t_pings` avec `source` = "smoke-test"
> 2. Qu'une ligne est apparue dans `_t_echoes` avec le bon `ping_id`
>
> Si `_t_echoes` est vide, verifie l'execution du workflow `_t_echo` (mode error dans le MCP n8n).
>
> Dis-moi si les 3 routes sont validees.

### Ca ne marche pas ?

| Symptome | Cause probable | Solution |
|----------|---------------|----------|
| `ERR_INVALID_REQUEST_BODY` ou `Property 'fields' on index 0 must be a JSON object` | Format d'insert incorrect : wrapper `records` en trop dans le body de la requete | Le body doit etre `{"fields": {...}}`, pas `{"records": [{"fields": {...}}]}`. Le wrapper `records` n'existe que dans la reponse. |
| R1 echoue (401 / token invalide) | Token `xc-token` invalide ou credential mal configure | Verifier que le credential est de type `nocoDbApiToken` (pas Header Auth) avec `host` = `http://nocodb:8080` |
| R2 echoue (echo jamais execute) | Le HTTP Request "Call echo" n'atteint pas le webhook | Verifier que l'URL est `http://n8n:5678/webhook/_t_echo` (hostname Docker interne, pas l'URL externe) |
| R3 echoue (lecture vide / 404) | URL mal formee ou mauvais ID de record | URL v3 : `/api/v3/data/<base>/<table>/records/<id>` (segment `data/` obligatoire, pas de segment `tables/`). Pour filtre : `(Id,eq,<value>)` sans guillemets autour de la valeur numerique |
| Colonnes absentes dans `_t_pings` / `_t_echoes` | `table:create` n'a pas cree les colonnes | Les colonnes doivent etre creees separement via `field:create` apres la table. Format : `{"title": "source", "type": "SingleLineText"}` |
| Tout echoue | MCP non connectes | Verifier `.mcp.json`, relancer Claude Code |

### Nettoyer

Quand le smoke test est valide :

> Supprime les 2 workflows de smoke test dans n8n et les 2 tables `_t_pings` / `_t_echoes` dans NocoDB. Garde la trace de ce qui a marche dans un commentaire ou dans LESSONS-LEARNED.md.

Le smoke test a prouve que la plomberie fonctionne. On passe aux choses serieuses.

---

## Annexe — Webhook sortant NocoDB (alternative R2)

> **Avertissement** : les webhooks sortants NocoDB ne se declenchent pas sur les inserts via API dans CE 2026.06.0 (teste le 2026-06-08). Le hook se cree et apparait dans la liste, mais aucun evenement ne fire. Hypothese : regression CE, ou hooks limites aux inserts via l'UI. Si tu veux tester, cree le hook via l'UI NocoDB (pas l'API).

Dans un monde ou le webhook fonctionne, on remplacerait les etapes 4-5 du workflow `_t_ping` (le chainage W23) par un webhook sortant NocoDB :

**Configuration du hook** (API v2) :
```
POST /api/v2/meta/tables/<table_id>/hooks
```
```json
{
  "title": "_t_pings after insert",
  "event": "after",
  "operation": ["insert"],
  "version": "v3",
  "notification": {
    "type": "URL",
    "payload": {
      "method": "POST",
      "path": "http://n8n:5678/webhook/_t_echo"
    }
  }
}
```

Points cles :
- `"version": "v3"` est obligatoire — sans ca, erreur `"hook version is deprecated"`.
- `"operation"` est un **array** (`["insert"]`), pas une string.
- L'URL cible utilise le hostname Docker interne (`n8n:5678`), pas l'URL externe du tunnel.

Si le webhook ne fire pas (0 execution cote `_t_echo` apres un insert), c'est le bug CE 2026.06.0. Repasser sur le chainage W23 (Prompt 3, etapes 4-5).

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

1. **Tables NocoDB** via `table:create` puis `field:create` pour chaque colonne (les colonnes ne se creent pas en passant `columns` dans le JSON de creation)
2. **Donnees fictives** pour que l'outil ne soit pas vide (tu peux demander le volume : "mets 5 entreprises et une dizaine de contacts") — format d'insert v3 : `{"fields": {...}}`, un record a la fois
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
| A.1 | "Cree les tables de smoke test" | Tables + colonnes NocoDB via CLI (`table:create` puis `field:create`) |
| A.2 | "Cree le credential NocoDB dans n8n" | Credential `nocoDbApiToken` via API REST n8n ou UI |
| A.3 | "Cree le workflow ping" | Workflow n8n : webhook → insert NocoDB (R1) → appel echo (R2 W23) |
| A.4 | "Cree le workflow echo" | Workflow n8n : webhook → lecture ping (R3) → insert echo (R1) |
| A.5 | "Teste le smoke test" | Curl + verification via MCP |
| **B.1** | **"/plan — je veux un outil pour..."** | **Plan d'architecture (le plus important)** |
| B.2 | *(Claude execute le plan valide)* | Tables + seed + workflows + pages |
| B.3 | "Teste le prototype" | Validation E2E |
| B.4 | "Documente dans LESSONS-LEARNED" | Capitalisation |

Le prompt B.1 est celui qui fait la difference. Plus tu decris ton besoin en termes metier (pas techniques), mieux Claude concoit l'architecture. Tu n'as pas besoin de savoir ce qu'est un webhook ou une pseudo-API — c'est le travail de Claude.

---

*Crash test v1.1 (2026-06-08). Corrections : format insert NocoDB v3, credential nocoDbApiToken, chainage W23 (contournement webhook NocoDB CE 2026.06.0), CLI field:create obligatoire. Teste sur leolaw — NocoDB CE 2026.06.0, n8n 2.19.4.*
