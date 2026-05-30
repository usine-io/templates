# Catalogue de pièges techniques — NocoDB v3 / n8n / Docker macOS / Caddy

> Catalogue cristallisé en opérant un 1er site Spark en conditions réelles. Pièges indépendants
> du domaine métier — reproductibles sur tout déploiement Spark.
> Voir aussi `spark-kit/INCIDENTS.md` (incidents détaillés avec commandes de diagnostic) et la
> mémoire `spark-pitfalls-catalog` (condensé de session des ~30 pièges majeurs).

---

## Sommaire rapide

| Techno | Codes | Titres |
|--------|-------|--------|
| NocoDB v3 | N1–N24 | [voir §1](#1-nocodb-v3) |
| n8n | W1–W22 | [voir §2](#2-n8n) |
| Docker / macOS | D1–D5 | [voir §3](#3-docker--macos) |
| Caddy | C1–C5 | [voir §4](#4-caddy) |

---

## 1. NocoDB v3

### N1 — `NC_DB` (URL) URL-décode le password : utiliser `NC_DB_JSON`

**Symptôme** : NocoDB en `Restarting (1)` en boucle, logs Postgres `password authentication failed`, alors que le rôle existe et que le mot de passe semble correct.

**Cause** : la variable `NC_DB="pg://...&p=<password>&..."` URL-décode le password avant de l'envoyer à Postgres. Si le password contient `&`, `=`, `+`, `%`… (ce qu'un `openssl rand -base64` produit souvent), Postgres reçoit une valeur tronquée ou déformée.

**Solution** : remplacer systématiquement par `NC_DB_JSON` (format objet JSON — pas de URL-decode) :
```yaml
NC_DB_JSON: '{"client":"pg","connection":{"host":"postgres","port":5432,"user":"nocodb","password":"${NOCODB_DB_PASSWORD}","database":"nocodb"}}'
```
Générer les secrets avec un alphabet URL-safe : `tr -dc 'A-Za-z0-9-_' </dev/urandom | head -c 32`.

> Couvert aussi par INC-2026-05-05 dans `spark-kit/INCIDENTS.md`.

---

### N2 — Bulk insert/delete limité à 10 records/call (ERR_MAX_PAYLOAD_LIMIT_EXCEEDED)

**Symptôme** : insert ou delete de plus de 10 records en une seule requête → `ERR_MAX_PAYLOAD_LIMIT_EXCEEDED` ou, pire, **échec silencieux** (aucune erreur retournée, mais seulement les 10 premiers records sont traités).

**Cause** : NocoDB v3 limite les opérations bulk à 10 records par appel.

**Solution** : batcher toutes les opérations bulk par tranches de 10 maximum. Toujours vérifier le retour de chaque batch pour détecter les échecs silencieux. Ne pas se fier à l'absence d'erreur HTTP comme preuve d'exhaustivité.

---

### N3 — Insert avec champ Link ≠ création du lien (juste un compteur)

**Symptôme** : `POST /api/v3/data/{base}/{table}/records` avec `{fields: {champ_link: {id: X}}}` — la requête réussit, le record est créé, mais le lien vers l'entité liée n'existe pas. Le champ retourne `0` (compteur) au lieu d'une référence.

**Cause** : en NocoDB v3, les champs Link dans le payload d'un insert ne créent pas de lien réel. Ils ne font que renseigner un compteur de display.

**Solution** : après l'insert, créer le lien séparément :
```
POST /api/v3/data/{base}/{table}/links/{link_field_id}/{record_id}
body: [{id: X}]
```
Ce pattern s'applique à **chaque** link que l'on veut établir.

---

### N4 — Response wrapping systématique : toujours `records[0].id`, jamais `id` direct

**Symptôme** : accès à `$json.id` dans un nœud n8n après un POST/PATCH NocoDB → `undefined`.

**Cause** : toute réponse POST/PATCH NocoDB v3 est enveloppée : `{records: [{id: X, fields: {...}}]}`. L'ID n'est jamais à la racine.

**Solution** : utiliser systématiquement `$json.records[0].id` (et `$json.records[0].fields` pour les champs) après toute écriture NocoDB v3.

---

### N5 — GET liste : les champs Link retournent un compteur, pas les objets expandés

**Symptôme** : `GET /api/v3/data/{base}/{table}/records` → les colonnes Link (FK) retournent `0`, `1`, `2`… à la place des objets liés. Incomparable au comportement v1 où les relations étaient parfois auto-expandées.

**Cause** : en v3, les champs Link dans une liste ne retournent qu'un compteur.

**Solution** : pour résoudre les FK, appeler séparément `GET /api/v3/data/{base}/{table}/links/{link_field_id}/{record_id}?fields=Id,nom,...`. Ou ajouter des champs Lookup directement sur la table source pour exposer les attributs des entités liées en une seule requête.

---

### N6 — Sort syntax v3 : format JSON URL-encodé, pas tiret préfixe

**Symptôme** : `?sort=-CreatedAt` → `HTTP 400` avec message confus.

**Cause** : NocoDB v3 n'accepte pas la syntaxe v1/v2 (`-field` pour DESC). La syntaxe v3 est un tableau JSON encodé.

**Solution** :
```
?sort=[{"field":"CreatedAt","direction":"desc"}]
```

---

### N7 — Filtre sur champ Link FK : utiliser le nom de colonne physique, pas le nom du champ

**Symptôme** : `?where=(dossier,eq,42)` → `HTTP 400` ou 0 résultats alors que des records existent.

**Cause** : le nom du champ Link dans l'UI (ex: `dossier`) ≠ le nom de la colonne physique FK (ex: `dossiers_id`). NocoDB v3 filtre sur la colonne physique.

**Solution** : inspecter le schéma (`GET /api/v3/meta/bases/{base}/tables/{table}/fields`) pour trouver le vrai nom de colonne physique FK, puis l'utiliser dans le filtre `where`.

---

### N8 — WHERE sur champ Link ne filtre pas : passer par `/links` inverse

**Symptôme** : `?where=(piece,eq,X)` retourne 0 résultats sur une table liée, même si des enregistrements correspondent.

**Cause** : en NocoDB v3, les champs Link ne sont pas filtrables par valeur directe (le champ Link stocke un compteur, pas une valeur FK exploitable dans un WHERE).

**Solution** : requêter depuis le côté opposé via `/links/{link_inverse_field_id}/{record_id}` pour obtenir tous les records liés.

---

### N9 — GET single record : endpoint direct, réponse non-wrappée

**Symptôme** : accès `$json.records[0]` après un GET d'un record par ID → erreur ou `undefined`.

**Cause** : l'endpoint single-record `GET /api/v3/data/{base}/{table}/records/{id}` retourne directement l'objet (pas enveloppé dans `records[]`), contrairement au GET liste.

**Solution** : distinguer les deux patterns :
- GET liste → `$json.records[0]`
- GET single par ID → `$json.id`, `$json.fields`

---

### N10 — GET single par clé naturelle : utiliser `where` + `pageSize=1`

**Symptôme** : pas d'endpoint dédié "get by unique field" (ex: récupérer un record par `code` ou `slug`).

**Cause** : NocoDB v3 n'offre pas d'endpoint GET-by-natural-key.

**Solution** :
```
GET /api/v3/data/{base}/{table}/records?where=(code,eq,X)&pageSize=1
```
Vérifier `records.length` côté Code node pour tester l'existence.

---

### N11 — SingleSelect : l'ajout d'un choix exige un PATCH avec la liste COMPLÈTE

**Symptôme** : `PATCH /api/v3/meta/bases/{base}/tables/{table}/fields/{field_id}` avec seulement les nouveaux choix dans `options.choices` → les choix existants sont **supprimés**.

**Cause** : NocoDB v3 remplace intégralement la liste de choix, elle ne la complète pas.

**Solution** : avant toute modification, récupérer les choix existants via `GET /api/v3/meta/bases/{base}/tables/{table}/fields/{field_id}`, fusionner avec les nouveaux choix, puis PATCH avec la liste complète.

---

### N12 — API v3 PAT-only : les PAT ne fonctionnent pas sur v1/v2

**Symptôme** : un PAT (`nc_pat_...`) envoyé à `/api/v1/db/meta/projects` ou `/api/v2/meta/bases` → `HTTP 403`.

**Cause** : NocoDB 2026.04.5+ n'accepte les tokens PAT que sur l'API v3. v1/v2 exigent des tokens d'un autre type.

**Solution** : utiliser exclusivement `/api/v3/...` avec les PAT. Si un outil tiers (MCP, SDK) cible v1/v2, il sera structurellement cassé sur les NocoDB récents — le basculer sur le CLI `nocodb.sh` de la skill.

> Couvert aussi par INC-2026-05-19 dans `spark-kit/INCIDENTS.md`.

---

### N13 — Workspace scoping obligatoire même en single-workspace self-hosted

**Symptôme** : `GET /api/v2/meta/bases` → `HTTP 403` même avec un token à droits `super` et `org-level-creator`.

**Cause** : NocoDB self-hosted crée automatiquement un workspace "Default Workspace", mais les endpoints meta exigent quand même le workspace ID dans le chemin.

**Solution** : capturer le workspace ID une fois au bootstrap et l'inscrire dans `.env` (`NOCODB_WORKSPACE_ID`). Utiliser `/api/v2/meta/workspaces/{id}/bases` pour lister les bases. Le liveness check `GET /api/v2/meta/workspaces` (sans ID) reste accessible.

---

### N14 — Package MCP NocoDB (`@andrewlwn77/nocodb-mcp@0.2.2`) : incompatible NocoDB récent

**Symptôme** : toute requête `mcp__nocodb-mcp__*` retourne `Forbidden - Unauthorized access`, même après rotation du PAT, même si le PAT fonctionne en curl direct v3.

**Cause** : le package NPM cible les endpoints v1/v2, rejetés par les NocoDB 2026.04.5+ pour les PAT. L'erreur ressemble à un problème d'auth, c'est en réalité une incompatibilité structurelle.

**Solution** : basculer sur le CLI `nocodb.sh` (skill `nocodb`). Vérifier le diagnostic en greppant le source du container MCP pour `/api/v1/` ou `/api/v2/`.

> Couvert aussi par INC-2026-05-19 dans `spark-kit/INCIDENTS.md`.

---

### N15 — Lookup field : schéma options = `related_field_id` + `related_table_lookup_field_id`

**Symptôme** : création d'un champ Lookup via `POST .../fields` échoue ou crée un champ vide avec les paramètres `fk_related_model_id` / `fk_lookup_column_id` (v1/v2).

**Cause** : la structure des options d'un champ Lookup v3 utilise des clés différentes.

**Solution** :
```json
{
  "uidt": "Lookup",
  "options": {
    "related_field_id": "<id du champ Link source>",
    "related_table_lookup_field_id": "<id du champ cible sur la table liée>"
  }
}
```

---

### N16 — Lookup field response : toujours un array, même pour une relation 1:1

**Symptôme** : `$json.fields.libelle_calcule` retourne `["Apple iPhone SE"]` (tableau à 1 élément) au lieu de `"Apple iPhone SE"`.

**Cause** : NocoDB v3 encapsule systématiquement les valeurs des champs Lookup dans un tableau, quelle que soit la cardinalité de la relation.

**Solution** : toujours accéder à `field[0]` côté front et côté Code node pour les champs Lookup.

---

### N17 — GET /links retourne uniquement le champ d'affichage par défaut

**Symptôme** : `GET /api/v3/data/{base}/{table}/links/{field_id}/{record_id}` → réponse avec seulement le 1er champ `SingleLineText`. Tous les autres champs sont absents de la réponse (pas même `null`).

**Cause** : l'endpoint `/links` ne retourne que le display field par défaut sauf instruction explicite.

**Solution** : toujours spécifier les champs souhaités en query param :
```
?fields=Id,nom,statut,...
```

---

### N18 — DELETE initial Postgres ≠ resynchronisation du password NocoDB

**Symptôme** : après un `ALTER USER nocodb WITH ENCRYPTED PASSWORD ...` qui réussit (`psql` confirme `ALTER ROLE`), NocoDB continue de crasher.

**Cause** : NocoDB lit le password via la variable `NC_DB` (URL) qui l'URL-décode avant de l'envoyer. Resynchroniser le password côté Postgres ne suffit pas si `NC_DB` continue à déformer le password.

**Solution** : le fix primaire est de basculer sur `NC_DB_JSON` (N1). Le `ALTER USER` n'est utile qu'en complément, pas comme solution principale.

---

### N19 — `patchNodeField` MCP NocoDB ne peut pas patcher les arrays/objets imbriqués

**Symptôme** : `patchNodeField` sur `parameters.assignments.assignments` → erreur ou mutation ignorée.

**Cause** : `patchNodeField` ne supporte pas les chemins vers des valeurs de type array ou objet complexe.

**Solution** : utiliser `updateNode` avec `updates: {"parameters.assignments.assignments": [...]}` pour les paramètres de type array/objet.

> Note : ce piège concerne techniquement le MCP n8n (pas NocoDB), mais est souvent rencontré lors d'opérations sur des nœuds NocoDB via le MCP.

---

### N24 — Ne pas embarquer l'UI NocoDB en `<iframe>` dans un front client

**Symptôme** : un front embarque une vue ou un formulaire NocoDB via `<iframe src="https://<prefix>-db.<domain>/dashboard/#/nc/...">`. Ça « marche » en dev anonyme, puis casse dès qu'on sécurise : l'iframe affiche le login Cloudflare Access (ou reste blanche), ou est bloquée par `X-Frame-Options`/CSP.

**Cause** : l'iframe pointe sur le sous-domaine NocoDB (`*-db`), distinct de celui du front (`*-app`) → cross-origin. (a) Sous CF Access, aucun cookie d'identité n'est propagé dans l'iframe et le login interactif ne peut pas s'y dérouler ; (b) les en-têtes anti-framing (`X-Frame-Options: SAMEORIGIN`, CSP `frame-ancestors`) bloquent l'embed cross-domaine.

**Solution / convention framework** : **ne pas** embarquer l'UI NocoDB. Un front client consomme NocoDB uniquement via les **webhooks n8n same-origin** (`/webhook/...` servi par le reverse-proxy du front). Si un accès direct à NocoDB est réellement nécessaire, **lier** vers son sous-domaine (nouvel onglet), pas l'`<iframe>`. Bénéfice secondaire : on construit un écran métier maîtrisé plutôt que de ré-exposer l'UI brute.

> Cristallisé en décommissionnant un POC qui utilisait ce pattern. Rappel : NocoDB n'est jamais la source de vérité métier — embarquer son UI n'apporte pas de valeur durable.

---

## 2. n8n

### W1 — `JSON.stringify({...})` inline dans une expression → "invalid syntax"

**Symptôme** : expression `={{ JSON.stringify({id: x, fields: {status: 'X'}}) }}` dans un nœud HTTP Request → erreur n8n "invalid expression" ou "invalid syntax" à l'exécution.

**Cause** : n8n parse les expressions `{{ }}` avant de les évaluer, et la syntaxe complexe (accolades imbriquées, guillemets) entre en conflit avec le parseur.

**Solution** : préparer le body JSON dans un Code node intermédiaire (`Prep` ou `Set IDs`) :
```js
return [{json: {body: JSON.stringify({id: x, fields: {status: 'X'}})}}];
```
Puis référencer dans le nœud HTTP : `={{ $('Prep').first().json.body }}` en mode `jsonBody` ou via `rawBody`.

---

### W2 — Expression `={"fields": {"qty": {{ X }}}}` : "Unmatched expression brackets"

**Symptôme** : validation MCP ou exécution retourne "Unmatched expression brackets" pour une expression JSON template avec accolades mixtes.

**Cause** : le parseur n8n confond les accolades de l'objet JSON avec les délimiteurs d'expression `{{ }}`.

**Solution** : même que W1 — préparer l'objet entier en Code node, propager via Set, référencer par `={{ $json.body }}`.

---

### W3 — Branches parallèles + fan-in non déterministe

**Symptôme** : un Code node "Build Response" qui lit `$('BranchA').first().json` ET `$('BranchB').first().json` retourne `undefined` pour l'une des branches. L'ordre d'exécution des branches parallèles est imprévisible.

**Cause** : n8n Community Edition n'a pas de merge/wait fiable. Le nœud en aval peut s'exécuter avant que toutes les branches parallèles aient terminé.

**Solution** : restructurer en chaîne séquentielle stricte : `Fetch A → Fetch B → Fetch C → Build Response`. Légèrement plus lent, 100% fiable. Ne jamais architecturer un workflow n8n avec des branches parallèles quand un nœud en aval doit accéder aux résultats de toutes les branches.

---

### W4 — Code node sandboxé : pas de `fetch`, pas de `$helpers`

**Symptôme** : `fetch(...)` ou `$helpers.request(...)` dans un Code node → `ReferenceError: fetch is not defined` ou équivalent.

**Cause** : n8n 2.1.1+ sandbox les Code nodes. Les appels HTTP sont interdits dans ce contexte.

**Solution** : tout appel HTTP externe doit passer par un nœud **HTTP Request** dédié, jamais dans un Code node. Le Code node n'est autorisé qu'à transformer des données déjà disponibles dans `$input`.

---

### W5 — `throw new Error()` obligatoire pour retourner HTTP 500

**Symptôme** : `return [{json: {_error: 'message'}}]` dans un Code node de validation → la chaîne continue à s'exécuter, le workflow retourne HTTP 200 avec un payload d'erreur.

**Cause** : retourner un objet JSON ne stoppe pas l'exécution du workflow. Seul `throw` interrompt la chaîne.

**Solution** : pour qu'un workflow retourne HTTP 500 sur validation invalide :
```js
throw new Error('Message d\'erreur explicite');
```

---

### W6 — IF node : `conditions.options` est obligatoire (structure stricte)

**Symptôme** : création d'un nœud IF via MCP sans `conditions.options` → erreur de validation ou comportement imprévisible.

**Cause** : n8n 2.x exige une structure précise pour les options du nœud IF.

**Solution** : toujours inclure :
```json
"conditions": {
  "options": {
    "version": 2,
    "leftValue": "",
    "caseSensitive": true,
    "typeValidation": "strict"
  }
}
```

---

### W7 — IF node : opérateurs unaires (`notEmpty`, `empty`) exigent `singleValue: true`

**Symptôme** : opérateur `notEmpty` ou `empty` sur un IF node → erreur de validation ou l'opérateur ne se comporte pas comme attendu.

**Cause** : n8n 2.19.4+ exige `singleValue: true` pour les opérateurs unaires, et interdit `rightValue`.

**Solution** : pour les opérateurs unaires :
```json
{"operator": "notEmpty", "singleValue": true}
```
Sans `rightValue`.

---

### W8 — `typeValidation: "strict"` rejette un number là où un string est attendu

**Symptôme** : condition IF sur un champ numérique avec `typeValidation: "strict"` → la condition échoue même quand la valeur semble correcte.

**Cause** : en mode strict, n8n refuse la coercition de type. Un `number` n'est pas accepté là où un `string` est attendu.

**Solution** : utiliser `"loose"` + coercition explicite `String()` dans une expression si nécessaire. Ou s'assurer que les types correspondent strictement.

---

### W9 — Query params dans Webhook : `$json.query.X`, pas `$json.body.X`

**Symptôme** : accès à un query param via `$json.body.myParam` dans un nœud Webhook → `undefined`.

**Cause** : n8n sépare les query params du body. Les query params sont dans `$json.query`, le body POST dans `$json.body`.

**Solution** : `$json.query.X` pour les paramètres GET/query string, `$json.body.X` pour le body POST.

---

### W10 — Webhook v2/2.1 : les path params `:varname` sont pris littéralement

**Symptôme** : webhook configuré sur `/api/resource/:id` → n8n enregistre littéralement le chemin `/:id` au lieu de traiter `:id` comme un paramètre dynamique.

**Cause** : n8n 2.51.1 (et versions proches) ne supporte pas les path params de style Express dans les webhooks.

**Solution** : utiliser des query params (`/api/resource?id=X`) ou passer l'ID dans le body POST. À re-tester sur les versions futures.

---

### W11 — `method` dynamique via expression : faux positif de validation MCP

**Symptôme** : `method: ={{ $json.method }}` dans un nœud HTTP Request → validation MCP marque "Invalid value", mais le workflow **fonctionne correctement** au runtime.

**Cause** : le validateur MCP ne peut pas évaluer les expressions dynamiques au moment de la validation statique.

**Solution** : ignorer ce warning de validation spécifique. Activer le workflow quand même. C'est un faux positif documenté (W20 dans le pitfalls catalog).

---

### W12 — `n8n_update_partial_workflow` MCP : `source`/`target`, pas `from`/`to`

**Symptôme** : tentative de connexion entre deux nœuds avec `from`/`to` → erreur ou connexion non créée.

**Cause** : l'API MCP `n8n_update_partial_workflow` utilise les clés `source`/`target` pour les connexions.

**Solution** : toujours utiliser `source`/`target`. De même, `moveNode` attend le display name du nœud (pas son ID technique), et `patchNodeField` plante si la chaîne cible n'existe pas dans le nœud — vérifier l'état actuel du workflow avant de patcher.

---

### W13 — `n8n_update_full_workflow` : param `name` obligatoire

**Symptôme** : `n8n_update_full_workflow` sans le paramètre `name` → erreur 422 `request/body must have required property 'name'`.

**Cause** : l'API attend le nom du workflow dans le payload, même si on ne le modifie pas.

**Solution** : toujours inclure `"name": "nom du workflow"` dans le payload de `n8n_update_full_workflow`.

---

### W14 — Execute Workflow node : préférer HTTP interne pour les sub-workflows

**Symptôme** : le nœud "Execute Workflow" introduit une complexité de configuration (permissions, IDs) et rend les sous-workflows moins réutilisables.

**Cause** : les sous-workflows exposés en webhook interne (`http://n8n:5678/webhook/<path>`) sont plus simples, transparents au runtime, et peuvent être réutilisés comme building blocks par n'importe quel autre workflow.

**Solution** : exposer les sous-workflows atomiques en webhook POST sur un path interne (`/internal/...`), et les appeler via HTTP Request node. Latence ~100ms par hop acceptable en POC.

---

### W15 — Upgrade n8n : tester les workflows immédiatement après

**Symptôme** : après un upgrade n8n (ex: 2.1.1 → 2.19.4), des workflows qui fonctionnaient plantent sans raison apparente.

**Cause** : les upgrades n8n contiennent des breaking changes sur les nœuds IF (structure options), la validation de type, et le sandbox Code node.

**Solution** : ne jamais upgrader n8n ET changer le schéma NocoDB dans la même session. Tester les workflows immédiatement après un upgrade. Avoir un script E2E permet de détecter les régressions en quelques minutes.

---

### W16 — `n8n_update_partial_workflow` : `patchNodeField` strict

**Symptôme** : `patchNodeField` sur un nœud → erreur si la chaîne cible n'existe pas dans la configuration actuelle du nœud.

**Cause** : la commande cherche la valeur exacte pour la remplacer. Si le nœud a été modifié entre-temps, le patch échoue.

**Solution** : toujours récupérer l'état actuel du workflow avant d'appliquer un patch (`n8n_get_workflow`), puis calculer les diffs à appliquer.

---

## 3. Docker / macOS

### D1 — `mv` d'un dossier monté en bind mount ne propage pas dans le container

**Symptôme** : remplacement d'un dossier côté hôte par un `mv` + `mkdir` → le container continue à voir l'ancien inode. Les nouveaux fichiers dans le dossier recréé ne sont pas visibles.

**Cause** : Docker bind mount suit l'inode, pas le chemin. `mv` crée un nouvel inode, mais le container continue à pointer sur l'ancien.

**Solution** : après tout `mv` ou `rm -rf` + `mkdir` sur un dossier monté en bind, redémarrer le container :
```bash
docker-compose restart <service>
```
L'ajout de fichiers dans un dossier dont l'inode n'a pas changé est OK sans restart.

---

### D2 — Colima sous-dimensionné : crashloop silencieux (exit 0, pas OOM)

**Symptôme** : containers en `Restarting (1)` en boucle ~60s, exit code 0 (pas 137), sans stack trace. n8n logs : `Last session crashed`. Postgres : `Connection timed out` puis `recovered`. `OOMKilled=false` partout.

**Cause** : la VM Colima manque de mémoire. Le kernel-OOM-killer cible les sous-processus enfants (runner n8n, client Postgres) plutôt que le container parent → exit 0 silencieux.

**Diagnostic rapide** :
```bash
docker run --rm alpine free -h
# Si "available" < 200 MB → c'est la mémoire
```

**Solution** :
```bash
colima stop
colima start --cpu 4 --memory 4  # 4 GiB sur host 8 GB ; 6 GiB sur host 16+ GB
```
Incompatible avec un LLM local concurrent (Ollama 7B ≈ 5 GB working set) sur un host 8 GB.

> Couvert aussi par INC wiki dans `spark-kit/INCIDENTS.md`.

---

### D3 — `init-db.sh` Postgres ne se rejoue pas après le 1er boot

**Symptôme** : régénération du `.env` après le 1er démarrage → les rôles Postgres gardent leurs anciens passwords. NocoDB ou n8n échouent à s'authentifier en boucle.

**Cause** : `init-db.sh` ne s'exécute que lorsque le volume `postgres_data` est vide (1er boot). Les boots suivants, le script est ignoré même si `.env` a changé.

**Solution** : toute rotation de password dans `.env` doit être accompagnée d'un `ALTER USER ... WITH ENCRYPTED PASSWORD ...` depuis l'intérieur du container Postgres (pour ne pas exposer le secret côté hôte) :
```bash
docker exec <postgres_container> bash -c \
  'printf "ALTER USER nocodb WITH ENCRYPTED PASSWORD '\''%s'\'';\n" "$NOCODB_DB_PASSWORD" \
  | psql -U postgres -v ON_ERROR_STOP=1'
```

---

### D4 — Python `urllib` bloqué par Cloudflare (error 1010)

**Symptôme** : script Python utilisant `urllib` ou `requests` (User-Agent par défaut `Python-urllib/3.x`) → Cloudflare retourne HTTP 403 / error 1010 sur les URLs publiques protégées.

**Cause** : Cloudflare bloque les User-Agents génériques automatisés.

**Solution** : ajouter un User-Agent de navigateur :
```python
headers = {'User-Agent': 'Mozilla/5.0 (compatible; spark-script/1.0)'}
```

---

### D5 — Uptime Kuma dans le même compose que les services monitorés

**Symptôme** : arrêt de Caddy pour tester une alerte Kuma → Kuma devient inaccessible (routé via Caddy) ET ses probes passent par Caddy → impossibilité de détecter la panne.

**Cause** : Kuma est co-localisé dans le compose du client. Si le reverse proxy tombe, tout le monitoring tombe avec.

**Solution** : en production, Kuma doit tourner sur une machine séparée (master Spark). Un seul Kuma master surveille tous les sites de l'extérieur comme un vrai utilisateur.

**Note opérationnelle** : les monitors Kuma insérés via SQLite + restart fonctionnent. Les notifications doivent être configurées via l'UI (Socket.IO runtime).

---

## 4. Caddy

### C1 — `mv` d'un dossier monté en bind : restart container nécessaire

**Symptôme** : déplacement d'un dossier servi par Caddy (ex: `mv front-old front-new`) → Caddy continue de pointer vers l'ancien inode, les nouvelles pages ne sont pas servies.

**Cause** : même root cause que D1 (bind mount + inode). Caddy est affecté comme tout container Docker.

**Solution** : `docker-compose restart caddy` après tout `mv` d'un dossier servi.

---

### C2 — Ajout d'un volume dans docker-compose : recréation du container nécessaire

**Symptôme** : ajout d'un nouveau `volumes:` sur le service Caddy dans `docker-compose.yml` + `docker-compose up -d caddy` → le volume n'est pas monté, les fichiers ne sont pas accessibles.

**Cause** : `docker-compose up -d` sans `--force-recreate` ne recrée pas le container si sa définition de volumes a changé.

**Solution** : forcer la recréation du container Caddy après tout changement de volumes :
```bash
docker-compose up -d --force-recreate caddy
```
Coupure ~3-5s sur tous les fronts. Prévenir les autres builders avant de lancer.

---

### C3 — Tunnel Cloudflare : blocs `# >>> spark-begin` / `# <<< spark-end` dans le YAML

**Symptôme** : ajout de routes cloudflared hors des balises attendues → le script `tunnel-up.sh` / `tunnel-down.sh` ne gère pas les blocs et crée des doublons ou des configs orphelines.

**Cause** : les scripts de gestion du tunnel utilisent des blocs marqués pour insérer/supprimer les routes de chaque site. Toute route hors-balisage est invisible aux scripts.

**Solution** : ne jamais éditer manuellement `~/.cloudflared/config-<nom>.yml` hors des balises `# >>> spark-begin` / `# <<< spark-end`. Utiliser uniquement les scripts `tunnel-up.sh` / `tunnel-down.sh`.

---

### C4 — Reverse proxy n8n via Caddy : ne pas exposer `/webhook-test/` en production

**Symptôme** : workflows n8n en mode "test" (exécution manuelle) accessibles publiquement via `/webhook-test/`.

**Cause** : si Caddy proxy-passe tout le trafic vers n8n sans filtrage de chemin, les webhooks de test sont accessibles publiquement.

**Solution** : dans la config Caddy, restreindre `/webhook-test/` aux IPs internes ou bloquer entièrement en production. Seul `/webhook/` (mode production) doit être exposé.

---

## Annexe — Recouvrements avec d'autres sources

Les pièges suivants sont déjà documentés (partiellement ou en totalité) dans d'autres sources Spark. Ce catalogue les reprend pour être autoporteur, mais la source de référence avec le diagnostic complet reste indiquée :

| Code | Piège | Source principale |
|------|-------|-------------------|
| N1 | NC_DB_JSON vs NC_DB | `spark-kit/INCIDENTS.md` INC-2026-05-05 |
| N12 | PAT token v3-only | `spark-kit/INCIDENTS.md` INC-2026-05-19 + mémoire `feedback-nocodb-api-workspace-scoping` |
| N14 | MCP NocoDB incompatible | `spark-kit/INCIDENTS.md` INC-2026-05-19 |
| D2 | Colima crashloop silencieux | `spark-kit/INCIDENTS.md` INC wiki |
| N2 | Bulk insert max 10 | mémoire `spark-pitfalls-catalog` |
| N3 | Insert link ≠ créer lien | mémoire `spark-pitfalls-catalog` |
| W3 | Branches parallèles | mémoire `spark-pitfalls-catalog` + mémoire `feedback-n8n-no-parallel-execution` |
| W4 | Code node no HTTP | mémoire `feedback-n8n-code-node-no-http` |
| W12 | MCP conventions source/target | mémoire `feedback-n8n-mcp-partial-update` |
