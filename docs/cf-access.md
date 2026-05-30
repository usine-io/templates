# Mettre une application derrière Cloudflare Access — exemple projet ACME

> Document générique transmissible. Substituer `ACME`/`acme` par le slug court du projet client
> et `<domain>` par la zone Cloudflare réelle.
> Aucune valeur de secret n'apparaît ici. Compagnon de [`cloudflared.md`](cloudflared.md) (le tunnel) — ceci en est la couche d'authentification.

CF Access = couche d'**identité** posée au bord de Cloudflare, **devant un hostname public**. Un anonyme ne reçoit plus l'app mais un `302` vers un mur de login (SSO ou code email). C'est ce qui ferme les pages de login exposées (n8n, NocoDB…) et les écrans/webhooks non authentifiés.

---

## 0. Le principe en une image — les « deux portes »

```
Porte 1 (publique, humain)
  Navigateur → Cloudflare edge [CF Access 🔒 302] → tunnel → reverse-proxy → service

Porte 2 (interne, machine/agent)
  Conteneur A ──(réseau Docker interne)──► http://service:port
            ne sort jamais de la machine → jamais vu par CF Access
```

**Conséquence clé** : protéger un hostname **ne casse pas** les appels conteneur-à-conteneur (un MCP, un worker, un script interne qui tape `http://service:port`). CF Access ne voit que le trafic qui passe par le bord Cloudflare.

À l'inverse, tout **client externe légitime** (CLI sur un laptop, autre serveur, callback d'un SaaS) passe par la porte 1 → il lui faut un moyen de franchir Access (cf. §5 Service Tokens).

---

## 1. Choisir le bon contrôle selon l'appelant

| Appelant | Exemple | Contrôle |
|---|---|---|
| **Humain via navigateur** | écrans internes, UI admin (n8n, NocoDB) | **CF Access** + IdP (SSO) ou One-time PIN |
| **Machine externe (M2M)** | callback d'un SaaS, autre serveur, CLI headless | **Service Token** Access (§5), ou clé applicative au niveau du service |
| **Machine interne (même hôte)** | MCP, worker, script conteneur | **rien à faire** — passe par le réseau interne, hors Access |

> ⚠️ CF Access (SSO interactif) ne convient **pas** à une machine : prévoir un Service Token.

---

## 2. Pré-requis

- Compte **Cloudflare Zero Trust** activé (gratuit jusqu'à 50 users).
- Le hostname est **déjà exposé** (tunnel cloudflared — cf. [`cloudflared.md`](cloudflared.md)).
- Un **IdP** branché (Entra ID, Google…) **ou** rien → fallback **One-time PIN** (code envoyé par email, zéro config, parfait pour un test).

---

## 3. Procédure A — Dashboard (rapide, 1 app / test) ✅ recommandé pour démarrer

1. **Zero Trust → Access → Applications → Add an application → Self-hosted**
2. **Application domain** : `acme-n8n` . `<domain>` (sous-domaine à protéger)
3. **Policy** : Action **Allow** → Include → **Emails** = adresses autorisées
   (ou *Emails ending in* `@acme.tld` pour toute l'équipe ; pour un test, une seule adresse)
4. **Identity provider** : l'IdP du client, sinon **One-time PIN**
5. **Save**

Réversible à 100 % : supprimer l'application Access = retour à l'état non protégé.

---

## 4. Procédure B — Terraform (IaC, pour généraliser / capitaliser)

Pour reproduire d'un client à l'autre et versionner. Surdimensionné pour un seul test, pertinent dès qu'on protège plusieurs hostnames.

```hcl
resource "cloudflare_zero_trust_access_application" "n8n" {
  account_id       = var.cf_account_id
  name             = "ACME n8n"
  domain           = "acme-n8n.<domain>"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "n8n_team" {
  account_id     = var.cf_account_id
  application_id = cloudflare_zero_trust_access_application.n8n.id
  name           = "Équipe ACME"
  decision       = "allow"
  precedence     = 1
  include { email_domain = ["acme.tld"] }   # ou email = ["alice@acme.tld"]
}
```

**Token API requis** : scope **`Access: Apps and Policies — Edit`** (+ `Access: Organizations, Identity Providers — Read`).
⚠️ Un token `Zone:DNS:Edit` (celui des tunnels) **ne suffit pas** — créer un token dédié.

---

## 5. Laisser passer une machine / un CLI — Service Tokens

Quand un appelant **non-humain** doit franchir Access (CLI headless, autre serveur, sonde de monitoring) :

1. **Zero Trust → Access → Service Auth → Service Tokens → Create** → récupérer `Client ID` + `Client Secret`.
2. Dans la **policy** de l'app : ajouter un include **Service Token** (Action *Service Auth*).
3. L'appelant envoie deux en-têtes :
   ```bash
   curl https://acme-db.<domain>/... \
     -H "CF-Access-Client-Id: <id>.access" \
     -H "CF-Access-Client-Secret: <secret>"
   ```
   Rotation des Service Tokens tous les **90 jours**.

Alternative pour un usage interactif depuis un poste : **`cloudflared access`** (même binaire que le tunnel) :
```bash
cloudflared access login  https://acme-n8n.<domain>      # auth + cache du token
cloudflared access curl   https://acme-n8n.<domain>/...  # curl auto-authentifié
cloudflared access token  https://acme-n8n.<domain>      # récupère le JWT à injecter
```

> 💡 Si un CLI maison tape une app passée derrière Access (ex. un CLI NocoDB sur `acme-db`), il **cassera** (302 au lieu de 200) tant qu'on ne lui donne pas un Service Token. À provisionner **en même temps** que l'app Access.

---

## 6. Vérification (avant / après)

```bash
DOMAIN=<domain>
for h in acme-n8n acme-app acme-db; do
  printf "%-14s : " "$h"
  curl -sS -o /dev/null -w "HTTP %{http_code} -> %{redirect_url}\n" --max-time 10 "https://$h.$DOMAIN/"
done
```

- **Avant** : `HTTP 200` (anonyme atteint l'app).
- **Après (protégé)** : `HTTP 302 -> https://acme.cloudflareaccess.com/cdn-cgi/access/login/...`
- Dans un navigateur : écran de login CF **avant** l'app.

Vérifier aussi que l'**outillage interne reste vert** (un MCP / worker qui tape `http://service:port` doit continuer à répondre — preuve que la porte 2 est intacte).

---

## 7. Rollback

Supprimer l'application Access (dashboard) ou `terraform destroy` la ressource → retour immédiat au `200`. Aucun impact sur le tunnel ni le DNS.

---

## 8. Pièges à connaître

- **CF Access ≠ déménagement d'URL.** On ajoute un hostname à une policy ; on ne déplace pas `acme-n8n.<domain>` vers `acme-app.<domain>/n8n`. Aucun reroutage, aucun changement de reverse-proxy.
- **Rate-limit ≠ CF Access.** Le rate-limit ralentit le bruteforce d'une page login ; il ne couvre pas les endpoints **sans** login (webhooks, écrans statiques) et n'arrête pas le credential-stuffing. CF Access supprime la surface. Les deux sont complémentaires.
- **Ordre d'opérations sur une app *live*** : protéger un hostname coupe l'accès anonyme **immédiatement**. Le faire dans une fenêtre prévue + prévenir l'équipe. Provisionner les Service Tokens des machines **avant** de couper.
- **Session duration** : trop courte = re-login fréquent ; 24h est un bon défaut interne.
- **Scripts & fronts ne doivent pas pointer au mauvais endroit.** Une fois un vhost derrière Access, tout appelant non authentifié prend un `302` que `fetch`/`curl` ne suivent pas. Conventions à graver pour les développements futurs :
  - **Fronts** → webhooks en **relatif** (`/webhook/...`), même origine que le front ; jamais l'URL absolue d'un autre sous-domaine. Pas d'iframe d'UI NocoDB (cf. `pieges-nocodb-n8n.md` N24).
  - **Scripts/CLI host** → soit viser le **réseau Docker interne** (`http://service:port`, hors Access), soit envoyer un **Service Token** (`CF-Access-Client-Id`/`CF-Access-Client-Secret`) ou passer par `cloudflared access curl`. Exemple : le CLI NocoDB de la skill lit `CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` depuis l'environnement.
  - **MCP / outillage agent** : non concernés (réseau interne).

---

## 9. Audit récurrent

Rejouer le bloc §6 tous les 3 mois ou après tout changement infra. Tous les hostnames censés être protégés doivent répondre `302 → *.cloudflareaccess.com` ; tout `200` inattendu = régression.

---

## 10. Déploiement complet sur un site — séquence appliquée (checklist)

Ordre éprouvé pour protéger les 3 vhosts type d'un site Spark (`-n8n`, `-app`, `-db`) sans rien casser. Chaque étape « Cloudflare » = dashboard **Zero Trust → Access**.

### Pré-requis (une fois)
- [ ] **Zero Trust activé** sur le compte Cloudflare ; noter le **team domain** (`acme.cloudflareaccess.com`, sous Settings → Custom Pages / team domain).
- [ ] **IdP branché** (Entra ID / Google) **ou** rien → fallback **One-time PIN** (zéro config).

### Étape 1 — vhost outil interne d'abord (bac à test) : `acme-n8n`
- [ ] **Cloudflare** : Access → Applications → Add → **Self-hosted** → domain `acme-n8n.<domain>` → policy **Allow** (tes emails) → IdP/OTP → session 24h → Save.
- [ ] Vérifier : anonyme → `302`. **Outillage agent intact** (le MCP tape `http://n8n:5678` en interne, jamais Cloudflare). Bon cobaye : faible trafic, impact nul si la policy est mal réglée.

### Étape 2 — app métier : `acme-app`
- [ ] **Pré-requis code (PAS Cloudflare)** : les fronts appellent leur API en **same-origin** (`/webhook/...`), jamais l'URL absolue d'un autre sous-domaine — sinon les XHR cassent sous Access (le cookie CF ne se propage pas cross-origin). Retirer aussi toute **iframe d'UI** d'un autre sous-domaine (cf. `pieges-nocodb-n8n.md` N24).
- [ ] **Cloudflare** : même procédure, domain `acme-app.<domain>`, policy = **opérateurs** (emails/groupe).
- [ ] ⚠️ **Coupe l'accès anonyme immédiatement** → fenêtre dédiée + prévenir l'équipe.
- [ ] Vérifier : anonyme (écrans + webhooks) → `302` ; puis **parcours utilisateur authentifié** en navigateur (login CF → l'app charge → une action réelle → les XHR `/webhook/*` passent via le cookie same-origin).

### Étape 3 — vhost data : `acme-db` (NocoDB)
- [ ] **Décider l'accès du tooling host AVANT** : préférer le **bypass reverse-proxy local** (`http://127.0.0.1:<port>` + en-tête `Host: acme-db.<domain>`) → le CLI reste local, insensible à Access, **sans Service Token**. (Alternative : Service Token, cf. §5, pour de l'off-host.)
- [ ] **Cloudflare** : app Self-hosted, domain `acme-db.<domain>`, policy = **admins** data.
- [ ] Vérifier : anonyme → `302` ; **CLI via bypass local** → `200` ; **runtime interne** (n8n→NocoDB en `http://nocodb:8080`) intact.

### Ce qu'on ne fait PAS / cas particuliers
- **Rate-limit sur les logins** : inutile une fois les 3 vhosts derrière Access — les formulaires de login natifs ne sont plus joignables anonymement. La seule surface d'auth restante est le login CF Access, protégé par Cloudflare + l'IdP.
- **Appelant machine externe (SaaS, autre serveur)** qui doit *pousser* vers un webhook : **Service Token** (§5) ou policy **Service Auth**, jamais le SSO interactif.
- **Consolider les vhosts sous un seul host/paths** (`/db`, `/n8n`) : à éviter — SPA sous sous-path fragile, conflit base-path n8n (UI vs `/webhook`), collisions de cookies. Garder un sous-domaine par app.

### Vérification finale (les 3 d'un coup)
```bash
DOMAIN=<domain>
for h in acme-n8n acme-app acme-db; do
  printf "%-12s : " "$h"
  curl -sS -o /dev/null -w "HTTP %{http_code} -> %{redirect_url}\n" --max-time 10 "https://$h.$DOMAIN/"
done
# Attendu : les 3 en 302 → acme.cloudflareaccess.com
```
