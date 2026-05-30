# CLAUDE.md — Guide agent pour un deploiement Spark

> Toi (Claude) qui debarques sur un repo Spark : voici l'essentiel avant d'ecrire ou modifier quoi que ce soit.

---

## ⚠️ REGLE D'OR — avant toute action technique

**Pour toute session qui touche NocoDB, n8n ou ecrans Caddy, charger immediatement** :

```
/skill nocodb                    # CLI nocodb.sh + reference API v3
/skill n8n-workflow-patterns     # patterns architecturaux
/skill n8n-expression-syntax     # $json.body.X, expressions {{}}
/skill n8n-mcp-tools-expert      # formats nodeType, validation
```

Et **lire la memoire `spark-pitfalls-catalog`** (~30 pieges cristallises sur les premiers POCs Spark). Si elle n'est pas presente sur la machine, voir `GETTING-STARTED.md` §3c pour la copier depuis un repo Spark existant.

**Les 3 pieges les plus couteux** (ceux qui reviennent meme apres avoir vu les autres) :
- **N3 (NocoDB v3 Links)** : `{fields: {champ_link: {id: X}}}` a l'insert NE CREE PAS le lien. Le champ retourne juste un compteur. Solution : POST `/api/v3/data/{base}/{table}/links/{link_field_id}/{record_id}` body `[{id: X}]` separement apres l'insert.
- **W3 (n8n expressions JSON)** : `={{ JSON.stringify({...}) }}` plante "invalid syntax" si la struct est complexe. Solution : Code node intermediaire qui prepare la string, puis HTTP node consomme `={{ $json.insert_body }}`.
- **C1 (Docker bind mount)** : un `mv` d'un dossier monte ne propage PAS dans le container. `docker compose restart <service>` necessaire. Un simple ajout/modif de fichier OK sans restart.

**Skipper la regle d'or coute 2-3h de bugs evitables par session** (vecu sur le premier gros build WMS v2). Cette section est en haut volontairement.

Premiere installation sur une nouvelle machine ? → suivre `GETTING-STARTED.md`.

---

## Ce qu'est Spark

Spark est un **side-stack** : un Mac Mini pose a cote des systemes existants de l'entreprise. Il ne remplace rien. Le CRM reste. L'ERP reste. Le fichier Excel qui marche depuis 2012 reste. Spark les fait parler entre eux.

**La source de verite business est toujours le systeme metier de l'entreprise** (CRM, ERP, Google Sheets, facturation, WMS...). NocoDB n'est jamais la source de verite business — c'est un bac a sable, un staging, une surface pour des donnees qui n'existaient nulle part avant. n8n est un pont controle qui ouvre des portes choisies vers les sources metier.

---

## Vocabulaire critique

| Terme | Sens |
|-------|------|
| **Spark** | La kit / methode (org GitHub `spark-kit`). Pas un site specifique. |
| **Site** | Un deploiement Spark concret : 1 Mac Mini, 1 entreprise, 1 domaine, 1 repo. |
| **`SPARK_PREFIX`** | Slug par-site qui forme les hostnames (`<prefix>-<service>.<domain>`). Ce n'est PAS le nom de la kit. |
| **Playbook** | Brique d'integration assemblable (workflow n8n + tables NocoDB + config). |

---

## Stack technique

| Service | Role | Port interne |
|---------|------|-------------|
| n8n | Orchestration, workflows | 5678 |
| NocoDB | Base visuelle, ecrans metier | 8080 |
| PostgreSQL 16 | Base relationnelle partagee (users separes : `n8n`, `nocodb`) | 5432 |
| Caddy | Reverse proxy, route le trafic | 80 (127.0.0.1 uniquement) |
| cloudflared | Tunnel Cloudflare (TLS, acces distant) | host, pas Docker |

Caddy a `auto_https off` — c'est Cloudflare qui gere le TLS. Caddy injecte `X-Forwarded-Proto https` pour que les apps croient etre en HTTPS.

---

## Outillage agent : skills + acces live

Deux outillages distincts. Pour **n8n** : skills (reference) + MCP (action live). Pour **NocoDB** : skill (reference) + **CLI v3** (action live, pas de MCP).

### n8n

**Skills** (7 skills `n8n-*`) :
- `n8n-node-configuration` — configuration des nodes par type et operation
- `n8n-workflow-patterns` — patterns architecturaux prouves (webhook, CRUD, scheduling, AI agents)
- `n8n-expression-syntax` — syntaxe `{{ }}`, `$json`, `$node`, troubleshooting expressions
- `n8n-code-javascript` — Code nodes JS, `$input`, `$helpers`, `DateTime`
- `n8n-code-python` — Code nodes Python, `_input`, `_json`, limitations
- `n8n-validation-expert` — interpretation des erreurs de validation
- `n8n-mcp-tools-expert` — guide d'utilisation des outils MCP n8n

**MCP** (`n8n-mcp`) :
- Lecture/ecriture de workflows, activation, executions
- Se connecte a `http://n8n:5678` en interne Docker
- Script wrapper : `infra/scripts/mcp-n8n.sh`

### NocoDB

**Skill** (`nocodb`) :
- Reference API v3 complete : data CRUD, meta management, links, filters, sorts, attachments
- Inclut le CLI `nocodb.sh` — c'est l'outil d'**action** pour NocoDB
- Syntaxe des filtres `where` : `(field,op,value)~and(field2,op2,value2)`

**Acces live : API v3 via CLI `nocodb.sh`** (pas de MCP). L'ecosysteme MCP NocoDB n'est pas stable contre les versions recentes (`2026.04.5+`) — le package historique `@andrewlwn77/nocodb-mcp@0.2.2` cible v1/v2 que NocoDB rejette pour les PAT. Cf. INC-2026-05-19 dans `spark-kit/INCIDENTS.md`. La stack n'integre donc pas de MCP NocoDB ; on s'en tient au CLI tant qu'un package compatible v3 n'a pas ete valide.

Utilisation type :
```bash
set -a; source infra/.env; set +a
export NOCODB_TOKEN="$NOCODB_API_TOKEN"
export NOCODB_URL="https://<prefix>-db.<domain>"
bash ~/.claude/skills/nocodb/scripts/nocodb.sh table:list <base>
unset NOCODB_TOKEN NOCODB_API_TOKEN
```

Le CLI lit le token via env, hit `/api/v3/...` avec le header `xc-token`, n'expose jamais le secret en sortie.

### Regles

1. **n8n : ne jamais `curl` quand le MCP n8n peut le faire.** Le MCP gere auth, pagination, format.
2. **NocoDB : toujours passer par `nocodb.sh`.** Pas de curl ad-hoc, pas de docker exec psql, pas de lecture brute de `.env` — le CLI est l'outil sanctionne.
3. **Skills = reference, MCP/CLI = action.** Consulter la skill pour comprendre la syntaxe, utiliser le MCP n8n ou le CLI NocoDB pour executer.
4. **Charger la skill avant de configurer un node.** `n8n-node-configuration` donne les champs requis par operation — evite les allers-retours.
5. **Valider avec `n8n-validation-expert`** apres avoir modifie un workflow.

---

## Configuration Claude Code

Le repo entreprise contient un `.mcp.json` (gitignored) a la racine qui pointe vers le wrapper n8n :

```json
{
  "mcpServers": {
    "n8n-mcp": {
      "command": "bash",
      "args": ["infra/scripts/mcp-n8n.sh"]
    }
  }
}
```

Le script source `infra/.env` et lance `docker run --network spark_spark` en mode stdio (`name: spark` dans le compose → reseau `spark_spark`). Au demarrage d'une session, le MCP n8n apparait automatiquement comme tool provider. NocoDB s'utilise via le CLI `nocodb.sh` de la skill (cf. plus haut).

### Installation des skills

Les skills sont globales (une seule fois par poste, dans `~/.claude/skills/`) :

```bash
npx @anthropic-ai/claude-code skills add nocodb/agent-skills
npx @anthropic-ai/claude-code skills add n8n/agent-skills
```

### Obtention des cles API

Apres le premier acces aux apps :
1. **n8n** : Settings > API > Create API Key → `N8N_API_KEY` dans `.env`
2. **NocoDB** : Team & Settings > Tokens > Add New Token → `NOCODB_API_TOKEN` dans `.env` (PAT `nc_pat_...`)
3. Relancer `docker compose up -d` pour que le MCP n8n recharge `N8N_API_KEY`. Le token NocoDB est lu depuis `.env` par le CLI au runtime (pas besoin de restart).

---

## Principes de travail

### Donnees

- NocoDB = bac a sable. Le systeme metier = source de verite.
- Quand une donnee existe deja dans un legacy, NocoDB en est le **cache/staging**.
- Quand une donnee n'existait nulle part (ex: WMS d'un atelier papier), NocoDB devient la **source pour cette donnee precise**.

### Secrets

- Pas de credential en clair dans le repo — jamais.
- `.env` est gitignored. Verifier avec `git status` avant tout commit.
- Les secrets metier (API keys, tokens des logiciels de l'entreprise) vont dans **n8n > Settings > Credentials**, chiffres par `N8N_ENCRYPTION_KEY`.
- Le `.env` ne contient que les secrets d'infrastructure de la stack.

### Securite de l'exposition externe

Tout site Spark expose 3 sous-domaines via Cloudflare Tunnel (`<prefix>-n8n`, `<prefix>-app`, `<prefix>-db`). Le standard de durcissement par defaut :

- **Cloudflare Access devant tout vhost UI / app / webhook** (pattern Entra ID M365 ou Google OAuth, Free tier jusqu'a 50 users). Aucune page login native n8n/NocoDB ne doit etre joignable directement depuis Internet.
- **Headers de securite Caddy** (HSTS, X-Frame-Options, etc.) sur **chaque** vhost — bloc copiable dans `spark-kit/SECURITY.md` §2.2.
- **CORS NocoDB** restreint au sous-domaine `-app` (NocoDB renvoie `*` par defaut, l'override est cote Caddy).
- **Caddy bind `127.0.0.1`** uniquement (pas `0.0.0.0`) pour eviter l'exposition LAN.
- **Pas de Uptime Kuma dans le compose client** — monitoring vit sur un master Spark separe.

Hygiene speciale : `CF_API_TOKEN` (scope DNS), `N8N_ENCRYPTION_KEY` et `NOCODB_API_TOKEN` sont des secrets de tres haut privilege. Ne **jamais** afficher leur valeur en sortie de tool/message. Cf. `spark-kit/SECURITY.md` §5.

Detail complet, modele de menace, recettes copy-paste et procedure d'audit recurrent : **`spark-kit/SECURITY.md`**.

### Workflows n8n

- Un workflow = une responsabilite claire.
- Nommer les workflows avec un prefixe explicite : `[SYNC] CRM → NocoDB`, `[ALERT] Stock bas`, `[WEBHOOK] Commande recue`.
- Tester les workflows en mode manuel avant de les activer.
- Les credentials sont references par nom, pas par ID — facilite la portabilite.

### Modifications infra

- Travailler dans `infra/`.
- Tester localement (`docker compose up -d`) avant de committer.
- Commit avec prefixe : `infra: ...`, `workflow: ...`, `discovery: ...`.

---

## Structure d'un repo entreprise

```
<entreprise>/
├── infra/
│   ├── .env                  secrets (gitignored)
│   ├── .env.example          template sans secrets
│   ├── docker-compose.yml
│   ├── config/
│   │   ├── Caddyfile
│   │   └── postgres/init-db.sh
│   ├── apps/                    apps metier statiques (servies par Caddy sur -app)
│   └── scripts/
│       ├── tunnel-up.sh      creation routes + CNAMEs CF
│       ├── tunnel-down.sh    suppression routes + CNAMEs
│       └── mcp-n8n.sh        wrapper MCP n8n
├── discovery/
│   ├── onboarding/           questionnaires entreprise
│   ├── fiches/               fiches-logiciel legacy
│   └── prds/                 PRDs des POCs
├── LESSONS-LEARNED.md        notes operationnelles
├── CLAUDE.md                 ce fichier, adapte a l'entreprise
└── .mcp.json                 config MCP (gitignored)
```

---

## Pieges connus

### NocoDB — toujours `NC_DB_JSON`, jamais `NC_DB`

La conf URL `NC_DB="pg://...&p=XXX&d=..."` URL-decode le password. Si le password contient `&`, `=`, `+`, `%` → auth fail en boucle. Utiliser `NC_DB_JSON` (objet JSON, pas de parsing URL).

### Sizing Colima

4 GiB par defaut. Si la stack devient lourde ou si des LLMs locaux tournent en parallele → 6+ GiB, mais seulement sur Mac 16 GB+. Diagnostic memoire : `docker run --rm alpine free -h`.

### Tunnel Cloudflare — pattern A

Le YAML cloudflared vit cote hote (`~/.cloudflared/config-*.yml`), edite par `scripts/tunnel-up.sh` via blocs marques `# >>> spark-begin` / `# <<< spark-end`. Ne pas editer manuellement les blocs marques.

### Endpoints derriere CF Access — ne pas pointer un script au mauvais endroit

Les 3 vhosts publics passent derriere Cloudflare Access (cf. "Securite de l'exposition externe"). Un appel anonyme recoit un `302` vers le login CF. Donc, pour tout nouveau front ou script :

- **Fronts** : appeler les webhooks en **relatif** (`/webhook/api/...`), jamais l'URL absolue `https://<prefix>-n8n.<domain>/...`. Front + API sont same-origin sur `<prefix>-app` → le cookie CF se propage aux XHR. Hardcoder l'hote n8n comme base d'API d'un front est un anti-pattern. Pas d'iframe NocoDB non plus.
- **Scripts / tooling host** (validation, cron, CLI) qui visent un vhost public → ils prendront un `302` sans auth. Trois voies, par ordre de preference :
  1. **Caddy local + Host header** (prefere sur le Mac hote) : `http://127.0.0.1:<port-http-local>` + en-tete `Host: <prefix>-<svc>.<domain>`. Reste en local, ne traverse jamais Cloudflare → pas de token. `nocodb.sh` : passer le header via `NOCODB_HOST_HEADER`.
  2. **Reseau Docker interne** (si le script tourne dans la stack) : viser `http://n8n:5678` / `http://nocodb:8080`.
  3. **Service Token CF** (seulement off-host / audit du 302 public) : en-tetes `CF-Access-Client-Id` / `CF-Access-Client-Secret`.
- **MCP n8n** : non concerne (reseau Docker interne).
- Runbook complet (creation app Access, Service Tokens, verif) : `docs/cf-access.md`.

### NocoDB v3 — vues custom = Enterprise

Sur NocoDB CE (le cas par defaut auto-heberge), l'API v3 des vues (`/api/v3/meta/bases/.../tables/.../views`) renvoie `ERR_LICENSE_REQUIRED`. Le CLI v3 ne peut donc pas creer/lister de vues Kanban / Calendar / Gallery / Form en programmatique. Workarounds : (a) creer les vues via l'UI NocoDB a la main, ou (b) se contenter de la grille par defaut. Les autres operations meta (tables, fields) marchent normalement sur CE.

### n8n — credential NocoDB : utiliser `nocoDbApiToken`, pas Header Auth

Quand un workflow n8n appelle l'API NocoDB via HTTP Request node, configurer le credential en type natif `nocoDbApiToken` (libelle "API Token" dans l'UI n8n). Ne pas creer un Header Auth generique avec `xc-token` — c'est techniquement equivalent mais moins propre et rejete par certains endpoints proteges.

### n8n — lecture de fichiers du repo via volume mount

Le node "Read/Write Files from Disk" n'autorise par defaut que les chemins sous `/home/node/.n8n-files/`. Pour qu'un workflow puisse lire des fichiers du repo (PRDs MD, configs...), monter dans ce path :

```yaml
# infra/docker-compose.yml, service n8n
volumes:
  - n8n_data:/home/node/.n8n
  - ../discovery:/home/node/.n8n-files/discovery:ro
```

Le `:ro` rend la lecture seule (recommande). Setter `N8N_RESTRICT_FILE_ACCESS_TO` pour etendre la whitelist est theoriquement possible mais n8n applique parfois encore la restriction par defaut — preferer le mount dans `/home/node/.n8n-files/*`.

---

## Liens

- Meta Spark : https://github.com/spark-kit/spark-kit
- Templates (gabarits methodologie) : https://github.com/spark-kit/templates
- Wiki Spark (manifeste, archi, concurrence) : `<spark-vault>/wiki/`
