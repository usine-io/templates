# Step 01 — Créer les comptes admin + tokens API

> Une fois la stack démarrée, créer les comptes admin sur n8n et NocoDB (1× par site, à la première visite des UI), puis générer les tokens d'API qui permettront à Claude (ou aux scripts de setup) de prendre la main pour le step 02 et au-delà.

## Pourquoi cette étape

- **Création des comptes** : n8n et NocoDB demandent un compte `owner`/`admin` à la première visite. Sans ça, aucune UI n'est utilisable.
- **Tokens API** : Claude ne peut **pas** créer ces comptes via l'UI (besoin d'humain pour les mots de passe), et les tokens ne peuvent pas être générés par script — il faut passer par les UIs respectives. Cette étape capture le moment humain incompressible.

## Prérequis

- [ ] Step 00 fait (`infra/.env` peuplé avec les secrets)
- [ ] Stack démarrée : `cd infra && docker-compose up -d`
- [ ] Tous les services `healthy` : `docker-compose -p ${SPARK_PREFIX} ps`
- [ ] URLs accessibles depuis ton navigateur :
  - https://${SPARK_PREFIX}-n8n.${SPARK_DOMAIN}
  - https://${SPARK_PREFIX}-db.${SPARK_DOMAIN}
- [ ] Un gestionnaire de mots de passe ouvert (Bitwarden, 1Password, etc.) pour stocker les credentials créés.

## Procédure

### 1.1 Compte owner n8n

1. Ouvrir `https://${SPARK_PREFIX}-n8n.${SPARK_DOMAIN}` dans le navigateur.
2. Première visite → formulaire **Set up owner account** :
   - Email : ton email
   - First name / Last name
   - Password : générer fort dans le password manager → **enregistrer dans le PM avec le label `${SPARK_PREFIX} n8n owner`**
3. Cliquer **Next**, puis ignorer les questions de personnalisation (ou y répondre, peu importe).

### 1.2 Token API n8n

1. Dans n8n : avatar (en bas à gauche) → **Settings** → **n8n API** → bouton **Create an API Key**.
2. Label : `setup-claude-<date>` (date du jour). Pas d'expiration courte.
3. Copier la clé qui s'affiche (elle commence par `eyJ...`, c'est un JWT).

   ⚠️ **n8n ne te la remontrera jamais** : si tu fermes la modale sans copier, il faudra en recréer une.

4. Coller la commande suivante dans ton terminal — appuyer sur entrée, **coller la clé quand demandé**, entrée :

   ```bash
   read -p "Colle la clé API n8n (puis entrée) : " key && \
     echo "N8N_API_KEY=$key" >> infra/.env && \
     echo "✓ N8N_API_KEY ajouté à infra/.env" && unset key
   ```

### 1.3 Compte admin NocoDB

1. Ouvrir `https://${SPARK_PREFIX}-db.${SPARK_DOMAIN}` dans le navigateur.
2. Première visite → formulaire **Sign up** (le 1er compte créé est automatiquement super-admin) :
   - Email : ton email (peut être le même que n8n)
   - Password : générer fort → **enregistrer dans le PM avec le label `${SPARK_PREFIX} nocodb admin`**

### 1.4 Token API NocoDB

1. Dans NocoDB : avatar (en haut à droite) → **Account Settings** → onglet **Tokens** → bouton **Add new token**.
2. Description : `setup-claude-<date>`. Pas d'expiration.
3. Copier le token (chaîne longue alphanumérique).
4. Coller la commande suivante, **coller le token quand demandé**, entrée :

   ```bash
   read -p "Colle le token API NocoDB (puis entrée) : " key && \
     echo "NOCODB_API_TOKEN=$key" >> infra/.env && \
     echo "✓ NOCODB_API_TOKEN ajouté à infra/.env" && unset key
   ```

## Validation

Une fois les 2 tokens en place dans `infra/.env`, vérifier qu'ils marchent. **Important** : passer chaque commande sur **une seule ligne** (le shell paste casse les `\` de continuation) :

```bash
set -a; source infra/.env; set +a
```

```bash
echo "=== n8n ==="; curl -sS -o /dev/null -w "HTTP %{http_code}\n" -H "X-N8N-API-KEY: $N8N_API_KEY" "https://${SPARK_PREFIX}-n8n.${SPARK_DOMAIN}/api/v1/workflows"
```

```bash
echo "=== NocoDB ==="; curl -sS -o /dev/null -w "HTTP %{http_code}\n" -H "xc-token: $NOCODB_API_TOKEN" "https://${SPARK_PREFIX}-db.${SPARK_DOMAIN}/api/v2/meta/workspaces"
```

**Attendu** : `HTTP 200` pour les deux. Si autre chose (`401`, `403`) → token mal collé ou mauvais scope.

> ⚠️ NocoDB self-hosted (community / non-enterprise) tourne en **single workspace** mais l'API exige néanmoins de scoper par workspace. L'endpoint `/api/v2/meta/bases` (sans workspace ID) répond `403 ERR_FORBIDDEN`. Le bon endpoint pour la liveness est `/api/v2/meta/workspaces` qui renvoie l'unique workspace du tenant.

## Capture des IDs nécessaires aux steps suivants

NocoDB scope toutes ses opérations API par workspace. On capture l'ID maintenant pour le réutiliser au step 02 :

```bash
ws_id=$(curl -sS -H "xc-token: $NOCODB_API_TOKEN" "https://${SPARK_PREFIX}-db.${SPARK_DOMAIN}/api/v2/meta/workspaces" | python3 -c 'import sys,json; print(json.load(sys.stdin)["list"][0]["id"])') && echo "NOCODB_WORKSPACE_ID=$ws_id" >> infra/.env && echo "✓ NOCODB_WORKSPACE_ID=$ws_id ajouté"
```

Validation : `grep NOCODB_WORKSPACE_ID infra/.env` doit afficher la ligne.

## ⚠️ Important — `.env` ≠ credentials n8n

**Les tokens API que tu colles dans `infra/.env` ne sont PAS la même chose que les "credentials" de n8n.**

| Couche | Quoi | Qui crée | Où | À quoi ça sert |
|---|---|---|---|---|
| `infra/.env` | `N8N_API_KEY`, `NOCODB_API_TOKEN`, ... | toi (UI clicks → copy-paste) | fichier local, gitignored | les **scripts de setup** (Claude, run.sh, teardown.sh) pour piloter n8n et NocoDB depuis l'extérieur |
| Credentials n8n vault | objet dans la DB n8n (chiffré par `N8N_ENCRYPTION_KEY`) | les scripts de setup ou toi en UI | DB n8n | les **nodes des workflows** pour s'authentifier auprès des services externes (NocoDB, Pennylane, SMTP, etc.) |

**Tu n'as PAS besoin de créer manuellement de credential dans l'UI n8n au step 01.** Le credential NocoDB du step 02 est créé **automatiquement par `run.sh`** à partir du token NocoDB de `.env`.

Plus tard (CRM, intégrations tierces, etc.) :
- Si l'intégration est codée par un script de setup Spark → le script crée le credential (comme step 02).
- Si tu construis un workflow "à la main" dans l'UI n8n → tu créeras le credential dans l'UI (Settings → Credentials → New). Le token de référence reste dans ton password manager.

Règle simple : un secret externe (token API tiers, mot de passe SMTP, etc.) ne va **jamais** dans `infra/.env` ni dans le repo. Il est saisi soit (a) en UI n8n directement, soit (b) collé dans une commande `read -p` qui crée le credential via API et le déchiffre côté n8n vault — pas de fuite intermédiaire.

---

## Anti-patterns / pièges

- **Tokens dans le presse-papier** : oublier de purger après usage. Le pattern `read -p ... && unset key` ci-dessus évite que la valeur traîne dans l'env du shell, mais le presse-papier système, lui, garde la dernière valeur — pense à copier autre chose après.
- **Tokens dans des messages** : ne JAMAIS coller un token dans un commit, un message Slack, un message à Claude. Si par accident un token a été exposé : retourner dans l'UI, le révoquer, en créer un nouveau, refaire le step.
- **Réutiliser le token entre sites** : non. Chaque site Spark a ses propres tokens. Si on en a plusieurs actifs sur n8n du même client associés à différents agents, les nommer pour pouvoir les révoquer ciblement (`setup-claude-...`, `mcp-...`, `cron-backup-...`).

## Statut du step

- [ ] Compte n8n créé
- [ ] `N8N_API_KEY` ajouté à `infra/.env`
- [ ] Compte NocoDB créé
- [ ] `NOCODB_API_TOKEN` ajouté à `infra/.env`
- [ ] Validation curl passée (HTTP 200 sur les 2)
- [ ] `NOCODB_WORKSPACE_ID` capturé dans `infra/.env`

→ Quand toutes les cases sont cochées, mettre le step `01` à ✅ dans `setup/README.md`.
