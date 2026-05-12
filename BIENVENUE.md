# Bienvenue, builder

> Tu as installe la stack Spark ([spark-kit](https://github.com/spark-kit/spark-kit)). Tu as fait le [crash-test](crash-test/). Maintenant : comment travailler au quotidien avec Spark et Claude Code.

---

## Ou tu travailles

Chaque entreprise deployee a **son propre repo**. C'est la que tu lances Claude Code, c'est la que vivent les fichiers de config, les workflows exportes, les pages front, et les notes.

```
<entreprise>/
├── CLAUDE.md                ← Claude Code le lit automatiquement a l'ouverture
├── LESSONS-LEARNED.md       ← ce qui a casse et ce qu'on a appris
├── .mcp.json                ← connecte Claude Code aux MCP (gitignored)
├── infra/
│   ├── .env                 ← secrets (gitignored, JAMAIS commite)
│   ├── docker-compose.yml
│   ├── config/
│   │   ├── Caddyfile
│   │   ├── postgres/init-db.sh
│   │   └── nocodb-mcp/Dockerfile
│   ├── apps/                ← pages HTML servies sur <prefix>-app.<domain>
│   └── scripts/
│       ├── tunnel-up.sh
│       ├── tunnel-down.sh
│       ├── mcp-n8n.sh       ← wrapper MCP pour Claude Code
│       └── mcp-nocodb.sh    ← wrapper MCP pour Claude Code
└── discovery/
    ├── onboarding/          ← rapports de visite, questionnaires
    ├── fiches/              ← une fiche par logiciel legacy etudie
    └── prds/                ← une PRD par POC envisage
```

**Regle** : tu lances toujours Claude Code **depuis la racine du repo entreprise**. C'est ce qui permet a Claude de charger le `CLAUDE.md` et le `.mcp.json` automatiquement.

---

## CLAUDE.md — le briefing agent

Le fichier [`CLAUDE.md`](CLAUDE.md) est le guide que Claude Code lit en arrivant dans un repo Spark. Il contient :

- Ce qu'est Spark (side-stack, pas remplacement)
- Le vocabulaire critique (site, prefix, playbook)
- La stack technique (quels services, quels ports)
- Les skills et MCP disponibles (n8n-mcp, nocodb-mcp, 7 skills n8n, 1 skill nocodb)
- Les principes de travail (donnees, secrets, workflows, infra)
- Les pieges connus (NC_DB_JSON, sizing Colima, tunnel pattern A)

**Ce fichier se copie et s'adapte** a chaque nouveau site. La version dans ce repo est le template de reference. Dans le repo d'une entreprise, tu y ajouteras les specificites du site (logiciels connectes, conventions locales, contacts).

---

## Comment bosser avec Claude Code

### Demarre toujours par /plan

Pour tout ce qui depasse un fix rapide, utilise `/plan` :

```
/plan

Je veux creer un outil de suivi des commandes fournisseurs.
On recoit environ 20 commandes par semaine.
Aujourd'hui le suivi est dans un Google Sheet que 3 personnes editent.
Je veux pouvoir voir les commandes en retard et marquer les receptions.
```

Claude va proposer une architecture (tables, endpoints, pages), tu valides ou tu ajustes, puis il implemente. Ca evite de construire un truc qui n'est pas ce que tu voulais.

### Utilise les MCP, pas curl

Les MCP (n8n-mcp + nocodb-mcp) sont integres dans le compose. Claude les utilise pour creer des tables, ecrire des workflows, lire des donnees — sans que tu aies a taper de commandes API.

Si Claude dit "je n'ai pas acces au MCP", verifier :
1. `.mcp.json` existe a la racine du repo
2. Les cles API sont renseignees dans `.env` (`N8N_API_KEY`, `NOCODB_API_TOKEN`)
3. La stack tourne (`docker compose ps`)

### Charge les skills avant de configurer

Avant de demander a Claude de creer un workflow n8n complexe :

> Charge la skill n8n-node-configuration et montre-moi les champs requis pour un node HTTP Request avec authentification.

Les skills donnent a Claude la doc de reference — sans elles, il improvise et fait des erreurs.

---

## Tips & tricks

### Formulaire NocoDB natif vs endpoint n8n

C'est LA question qui revient a chaque POC :

| Situation | Bon outil | Pourquoi |
|-----------|-----------|---------|
| Saisie mono-table, champs simples | **Formulaire NocoDB** | Zero code, l'utilisateur va directement dans NocoDB |
| Saisie qui met a jour 2+ tables | **Endpoint n8n** | NocoDB ne sait pas faire de side-effects cross-table |
| Saisie avec validation metier | **Endpoint n8n** | Tu veux controler ce qui entre |
| Lecture simple, tri, filtres | **Vue NocoDB partagee** | Iframe ou lien direct, zero code |
| Dashboard avec KPIs calcules | **Page HTML + API n8n** | Tu as besoin de croiser des donnees |

**Regle de base** : si un formulaire NocoDB natif suffit, utilise-le. N'ajoute un endpoint n8n que pour les operations composees.

### Nommer les workflows

Convention : `[CATEGORIE] Description courte`

```
[SYNC]    CRM → NocoDB              synchronisation periodique
[WEBHOOK] Commande recue            declenchement externe
[API]     /log-activity             pseudo-API exposee
[ALERT]   Stock bas                 notification
[SMOKE]   _t_ping                  test temporaire
```

Ca aide Claude a comprendre le role de chaque workflow quand il explore la stack.

### Secrets : qui va ou

| Secret | Ou | Pourquoi |
|--------|---|---------|
| Mots de passe Postgres, cles de chiffrement | `.env` (infra) | Ce sont des secrets de la stack elle-meme |
| API keys des logiciels metier (CRM, ERP, facturation) | **n8n Credentials** | Chiffres par `N8N_ENCRYPTION_KEY`, pas en clair dans des fichiers |
| Tokens NocoDB/n8n pour les MCP | `.env` (infra) | Necessaires au demarrage des conteneurs MCP |

**Jamais** de secret metier dans `.env`. Si Claude te propose de mettre une cle API de logiciel dans `.env`, dis non — ca va dans n8n > Settings > Credentials.

### Connecter une API externe

C'est le geste le plus frequent : tu veux brancher un logiciel (CRM, facturation, ERP, Google Sheets...) a Spark. Voici le flux :

**1. Trouve la doc API du logiciel**

Avant de coder quoi que ce soit, il te faut le lien vers la documentation API. Exemples :
- Pennylane : `https://pennylane.com/docs/api`
- Google Sheets : `https://developers.google.com/sheets/api`
- Un logiciel metier : chercher "NomDuLogiciel API documentation"

Si le logiciel n'a pas d'API, regarde s'il a un export CSV, un webhook sortant, ou un connecteur Zapier (souvent adaptable dans n8n).

**2. Obtiens les identifiants API**

Selon le logiciel :
- **API Key** : generee dans les parametres du logiciel (souvent "Developers" ou "Integrations")
- **OAuth2** : client ID + client secret + scope — n8n gere le flow OAuth nativement
- **Token Bearer** : copie depuis le dashboard du logiciel

**3. Cree le credential dans n8n**

Ouvre `https://<prefix>-n8n.<domain>` puis :

```
Settings > Credentials > Add Credential
```

Choisis le type qui correspond :
- **Header Auth** — pour les API qui attendent un header custom (`x-api-key`, `Authorization`, `xc-token`...)
- **OAuth2** — pour Google, Microsoft, Slack, et la plupart des SaaS modernes
- **HTTP Basic Auth** — pour les vieilles API avec login/password
- Le **connecteur natif** du logiciel si n8n en a un (400+ disponibles)

> Donne un nom parlant au credential : `Pennylane API Production`, `Google Sheets - Compte Atelier`, etc. Les workflows referencent les credentials par nom — un nom clair facilite la portabilite.

**4. Demande a Claude de construire le workflow**

Une fois le credential cree, dis a Claude :

> Voici la doc API de MonLogiciel : [lien]. J'ai cree un credential "MonLogiciel API" dans n8n de type Header Auth. Cree un workflow qui recupere les commandes du jour et les ecrit dans une table NocoDB.

Claude va :
- Lire la doc (si tu lui donnes le lien)
- Utiliser le credential par nom dans les nodes HTTP Request
- Construire le workflow via le MCP n8n

**Le reflexe a prendre** : quand tu veux connecter un logiciel, commence toujours par ces 3 choses :
1. Le lien vers la doc API
2. Le credential cree dans n8n
3. Un prompt qui decrit ce que tu veux faire avec cette API

Ne demande jamais a Claude de stocker une cle API dans un fichier ou dans le code d'un workflow — toujours dans un credential n8n.

### Les 3 sous-domaines

| Sous-domaine | Qui l'utilise | Ce qu'on y trouve |
|-------------|--------------|-------------------|
| `<prefix>-n8n.<domain>` | Le builder uniquement | Editeur de workflows, API, monitoring d'executions |
| `<prefix>-app.<domain>` | Les equipes + les webhooks | Pages HTML metier (`/apps/*`) + webhooks n8n entrants |
| `<prefix>-db.<domain>` | Les equipes | NocoDB : vues, formulaires, donnees |

L'utilisateur final ne va jamais sur `-n8n`. Il utilise `-app` (les outils qu'on a construits) et `-db` (les donnees brutes quand il en a besoin).

### Tester avant de livrer

Apres chaque prototype, demande a Claude :

> Teste le prototype : verifie que toutes les pages chargent, que les formulaires ecrivent dans les bonnes tables, et que le dashboard affiche des chiffres coherents.

Claude va tester chaque composant via les MCP et te faire un rapport. Si quelque chose casse, il debuggue.

### Documenter ce qu'on a appris

Apres chaque POC, meme un crash-test :

> Ajoute dans LESSONS-LEARNED.md : ce qu'on a construit, ce qui a marche, ce qui a casse, et les decisions qu'on a prises.

Ces notes sont de l'or pour le prochain POC. Claude les lit au demarrage de chaque session.

---

## Pieges courants

### NocoDB webhook v2 vs v3

Les versions recentes de NocoDB (2026+) ont deprecie le format webhook v2. Si un webhook sortant ne declenche rien :
- Format v3 : `operation: ["insert"]` (array, pas string)
- Body : `{{ json data }}`
- Payload : les donnees sont dans `data.rows[0]`

### n8n derriere un tunnel : les cookies

n8n refuse de fonctionner sans HTTPS (cookies securises). Le Caddyfile doit contenir `header_up X-Forwarded-Proto https` dans chaque bloc `reverse_proxy`. Sans ca, tu verras l'erreur "secure cookie".

### Colima qui manque de memoire

Si les containers redemarrent en boucle silencieusement :
```bash
docker run --rm alpine free -h
```
Si `available` < 200 MB → `colima stop && colima start --cpu 4 --memory 6 --disk 60`.

### NocoDB et les mots de passe speciaux

Toujours utiliser `NC_DB_JSON` (objet JSON), jamais `NC_DB` (URL). Les caracteres `+/=&%` dans un mot de passe cassent le format URL silencieusement.

### n8n : pas de branches paralleles

Les fan-in dans n8n sont peu fiables. Si tu as besoin de faire A puis B puis C, enchaine-les sequentiellement. `$('NodeName').first().json` sur des resultats paralleles = `undefined`.

---

## Quand tu es pret pour un vrai projet

Le crash-test t'a montre le processus. Pour un vrai deploiement chez une entreprise :

1. **Decouverte** — utilise le questionnaire onboarding (wiki Spark) pour comprendre l'entreprise
2. **Documentation** — ouvre une fiche par logiciel a brancher avec [`ingest-legacy-docs.md`](ingest-legacy-docs.md)
3. **Cadrage** — ecris un PRD avec [`prd-template.md`](prd-template.md)
4. **Construction** — `/plan` dans Claude Code avec le PRD comme contexte

La methodologie est la meme que le crash-test, mais avec un vrai besoin et de vraies donnees.

---

*Guide builder Spark v1.1 (2026-05-12). Se complete avec chaque deploiement.*
