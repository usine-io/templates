# Getting Started — premier boot d'un repo client Spark

> **Si tu es Claude Code et que l'utilisateur te demande "suis ce guide" :** execute les etapes dans l'ordre, demande confirmation avant chaque action qui modifie le systeme (install skills, docker up, credentials), et **arrete-toi a la fin de la section §2** pour valider que les skills sont chargees avant d'attaquer le reste.
>
> **Si tu es humain :** ce guide peut etre suivi a la main, ou tu peux dire a Claude *"lis GETTING-STARTED.md et execute-le"* — il te demandera confirmation a chaque etape critique.

**Scope** : preparer un **repo client** (`spark-kit/<client>`) sur un poste deja equipe Spark — skills Claude, premier boot stack, credentials n8n, verifications.

**Pre-requis** : la **machine** doit deja avoir l'infra Spark installee (Mac Mini + Colima + Docker + cloudflared + tunnel actif). Sinon, voir [spark-kit/spark-kit](https://github.com/spark-kit/spark-kit) (installation infra).

Temps cible : **30-45 min** la 1ere fois sur une machine, **5 min** sur une machine deja equipee de l'ecosysteme Spark.

---

## §1 — Verification pre-requis machine (5 min)

| Outil | Verif | Si absent |
|---|---|---|
| **Claude Code** | `claude --version` | https://claude.com/claude-code |
| **Docker + Colima** | `docker info` (≥ 4 GiB memoire) | `brew install colima docker && colima start --memory 4` |
| **cloudflared** | `cloudflared --version` | `brew install cloudflared` puis `cloudflared tunnel login` |
| **gh CLI** | `gh auth status` | `brew install gh && gh auth login` |
| **git** | `git --version` | (present par defaut macOS) |
| **node + npx** | `node --version` (≥ 20) | `brew install node` |
| **python3** | `python3 --version` (≥ 3.11) | (present par defaut macOS) |
| **tmux** | `tmux -V` | `brew install tmux` — requis pour §8 (Remote Control persistant) |

**Sizing Colima** : ≤ 4 GiB sur Mac dev 8 GB (memoire unifiee), 6 GiB sur Mac Mini Spark 16+ GB. Voir CLAUDE.md §Pieges connus.

---

## §2 — Installer les skills Claude (10 min) — UNE FOIS PAR MACHINE

Les skills sont **globales a l'utilisateur** (dans `~/.claude/skills/`), donc a installer **une seule fois par poste**, pas une fois par repo.

### 2a — Skill NocoDB

Source : https://github.com/nocodb/agent-skills

```bash
# Methode recommandee :
npx @anthropic-ai/claude-code skills add nocodb/agent-skills

# Alternative (Claude Code plugin) :
# Dans une session Claude Code : /plugin marketplace add nocodb/agent-skills
```

Verification :
```bash
ls ~/.claude/skills/nocodb/   # doit contenir SKILL.md et scripts/
```

### 2b — Skills n8n (7 skills)

Source : https://github.com/czlonkowski/n8n-skills

```bash
# Methode recommandee (depuis Claude Code) :
/plugin install czlonkowski/n8n-skills

# Alternative manuelle :
git clone https://github.com/czlonkowski/n8n-skills.git /tmp/n8n-skills
cp -r /tmp/n8n-skills/skills/* ~/.claude/skills/
rm -rf /tmp/n8n-skills
```

Verification — doit lister **7 skills** :
```bash
ls ~/.claude/skills/ | grep ^n8n
# n8n-code-javascript / n8n-code-python / n8n-expression-syntax
# n8n-mcp-tools-expert / n8n-node-configuration / n8n-validation-expert
# n8n-workflow-patterns
```

### 2c — Test dans Claude Code

Ouvrir une session Claude dans n'importe quel dossier :
```
/skill nocodb
```
Doit retourner le contenu du SKILL.md NocoDB. Idem pour `/skill n8n-workflow-patterns`.

**Si une skill ne se charge pas → refaire l'install (2a ou 2b) avant d'aller plus loin.**

---

## §3 — Cloner ou creer le repo client

### 3a — Si repo existant

```bash
gh repo clone spark-kit/<client>
cd <client>
cp infra/.env.example infra/.env           # puis editer avec les vraies valeurs
```

### 3b — Si nouveau client

```bash
gh repo create spark-kit/<client> --private --clone --template spark-kit/templates
cd <client>
# Puis renseigner discovery/, adapter CLAUDE.md pour le client, etc.
```

### 3c — Recuperer la memoire transverse Spark (pitfalls catalog)

```bash
# Depuis un repo Spark existant (ex: kyklos), copier la memoire
# catalogue des pieges qui sera chargee automatiquement par Claude.
src="$HOME/.claude/projects/-Users-$(whoami)-projects-<existing-client>-container/memory/spark-pitfalls-catalog.md"
dst="$HOME/.claude/projects/-Users-$(whoami)-projects-<client>-container/memory/"
mkdir -p "$dst" && cp "$src" "$dst"
```

Cette memoire contient ~30 pieges NocoDB / n8n / Caddy cristallises (W3 invalid syntax, N3 link insert, etc.). Elle est referenceee par CLAUDE.md §Regle d'or.

> **Si premier repo Spark de cette machine** : le catalogue n'existe pas encore. Pas grave — le CLAUDE.md du template inclut deja les 3 pieges les plus couteux. Le catalogue se construira au fil des sessions.

---

## §4 — Configurer le `.env`

Variables critiques (voir `infra/.env.example` pour la liste complete) :

- `SPARK_PREFIX` (= slug court du client, sert aux hostnames `<prefix>-*.<domain>`)
- `NOCODB_DB_PASSWORD` (generer un mot de passe **sans caracteres URL-speciaux** `& = + %` — cf. piege NocoDB du CLAUDE.md)
- `NOCODB_API_TOKEN` (a creer apres le premier boot NocoDB, etape §6)
- `N8N_ENCRYPTION_KEY` (`openssl rand -hex 32`)

**Jamais commiter `.env`** — il est dans `.gitignore`. Voir feedback `never-display-secrets` dans la memoire.

---

## §5 — Premier boot de la stack (10 min)

```bash
cd infra/
docker compose up -d
docker compose -p <prefix> ps        # tous services en "Up"
```

Verifications tunnel public :
```bash
curl -sI https://<prefix>-db.<domain>/      # NocoDB → 200
curl -sI https://<prefix>-n8n.<domain>/     # n8n → 200
curl -sI https://<prefix>-app.<domain>/     # Caddy (selon contenu front)
```

Si tunnel non configure : `bash infra/scripts/tunnel-up.sh`.

---

## §6 — Setup credentials n8n (etape manuelle, 5 min)

Le credentiel NocoDB cote n8n **doit etre cree a la main** (pas d'API publique d'admin n8n stable cote setup).

1. Ouvrir `https://<prefix>-n8n.<domain>`
2. Login (cf. `.env` `N8N_BASIC_AUTH_USER/PASSWORD`)
3. Settings → Credentials → **+ Add Credential**
4. Type : **NocoDB API Token** (chercher "nocodb")
5. Nom : `NocoDB Token account` (convention Spark)
6. Champ `apiToken` : coller la valeur de `NOCODB_API_TOKEN` du `.env`
7. Save → noter l'ID retourne

Inscrire l'ID dans la doc projet (ex: `infra/nocodb-schema/<projet>.json` `n8n_credential_id`).

---

## §7 — Verification finale (5 min)

Dans une nouvelle session Claude sur le repo :

1. Charger les skills (CLAUDE.md §Regle d'or les liste) :
   ```
   /skill nocodb
   /skill n8n-workflow-patterns
   /skill n8n-expression-syntax
   /skill n8n-mcp-tools-expert
   ```
2. Verifier la memoire chargee : Claude doit mentionner `spark-pitfalls-catalog` dans son contexte initial (si copiee en §3c).
3. Tester un appel NocoDB :
   ```bash
   set -a; source infra/.env; set +a
   export NOCODB_TOKEN="$NOCODB_API_TOKEN"; export NOCODB_URL="https://<prefix>-db.<domain>"
   bash ~/.claude/skills/nocodb/scripts/nocodb.sh workspace:list
   unset NOCODB_TOKEN NOCODB_API_TOKEN
   ```
   Doit lister au moins 1 workspace.
4. Tester n8n MCP via Claude : `n8n_list_workflows` doit retourner les workflows actifs.

Si toutes ces verifications passent → la machine et le repo sont **prets**. Sinon, revenir a l'etape correspondante.

---

## §8 — Lancer une session de travail persistante (Remote Control + tmux)

> Recommande sur Mac mini partage entre plusieurs builders. Permet d'avoir une UI
> Claude Code Desktop / navigateur sur un laptop, tout en gardant Claude qui agit
> sur le serveur (filesystem serveur, Docker serveur, MCP serveur), sans perdre la
> session a chaque deconnexion SSH.

### 8a — Lancer ta session sur le Mac mini

```bash
# En SSH sur le Mac mini
tmux new-session -d -s <prenom>-acme \
  "cd ~/acme && claude remote-control --name '<Prenom> · ACME'"
```

Puis depuis ton laptop (Claude Code Desktop ou navigateur claude.ai/code), tu retrouves la session **"<Prenom> · ACME"** et tu lui parles. Tous les outils (Read/Edit/Bash, MCP n8n, CLI nocodb) agissent sur le serveur.

### 8b — Pourquoi tmux est obligatoire

`claude remote-control` seul meurt a la fermeture du terminal qui l'a lance (deconnexion SSH, fermeture de fenetre, sleep laptop). `tmux` detache le processus, il survit jusqu'a `tmux kill-session`.

Sans tmux : a la moindre coupure, la session distante affiche "session disconnected" — mauvaise experience, perte de contexte.

### 8c — Commandes tmux utiles

```bash
tmux ls                              # liste des sessions actives
tmux attach -t <prenom>-acme         # reprendre la main en local (Ctrl+B D pour detacher)
tmux kill-session -t <prenom>-acme   # fin de journee / nettoyage
```

### 8d — Multi-builder sur la meme machine

Chaque builder a son **propre user Unix** sur le Mac mini, son **propre clone** dans son `$HOME` (ex: `/Users/martin/acme/`), et lance sa propre session :

```bash
# Builder 1
tmux new -d -s benjamin-acme "cd ~/acme && claude remote-control --name 'Benjamin · ACME'"

# Builder 2
tmux new -d -s martin-acme "cd ~/acme && claude remote-control --name 'Martin · ACME'"
```

Chacun retrouve sa session depuis son laptop. La stack Docker reste unique (servie par le Mac mini), partagee entre les builders. Les modifications de code se font dans le clone perso de chaque builder, qui push sur GitHub.

> ⚠️ Conventions multi-builder ("parallel prototyping" : 1 builder = 1 PRD, perimetres orthogonaux) a documenter dans le `CLAUDE.md` du repo client.

---

## §9 — Premier prototype

Une fois ce guide complete, suivre :
1. **[crash-test/](crash-test/)** — smoke test des 3 routes + premier use case guide
2. **[BIENVENUE.md](BIENVENUE.md)** — guide du builder au quotidien
3. **[CLAUDE.md](CLAUDE.md)** — briefing agent, a copier dans le repo client et adapter

---

## §10 — En cas de probleme

Catalogue des pieges cristallises (~30 NocoDB v3 + n8n + Caddy) :
→ Memoire `spark-pitfalls-catalog` (chargee auto par Claude — si copiee en §3c)

Incidents transverses :
→ `spark-kit/spark-kit/INCIDENTS.md`

Lessons du projet courant :
→ `LESSONS-LEARNED.md` a la racine du repo client

---

## Annexe — Philosophie

Ce guide est volontairement **non scripte** (pas un `install.sh`). Raisons :
- **Robustesse** : etapes manuelles verifiables, pas de magie qui casse silencieusement
- **Lisibilite** : un humain ou un agent Claude peut le suivre pas a pas
- **Maintenance** : modifier le guide est plus simple que debug un script auto

Evolutions envisagees :
- Auto-creation du credentiel n8n via `n8n_manage_credentials` MCP (si l'API admin se stabilise)
- Skill `spark-bootstrap` qui execute ce guide automatiquement (futur)
- Memoire `spark-pitfalls-catalog` packagee comme skill installable au lieu d'une copie manuelle §3c

---

*Guide v1 — 2026-05-21. A enrichir des qu'une nouvelle etape recurrente apparait sur les premiers postes.*
