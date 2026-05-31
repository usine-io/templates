# Step 03 — Sécurité / authentification (Cloudflare Access) — OPTIONNEL

> 🔒 Brique de **durcissement**. Ferme l'accès anonyme aux vhosts exposés : identité posée au bord Cloudflare (CF Access) devant `-n8n` / `-app` / `-db`, + headers de sécurité Caddy + override CORS NocoDB.
> ⏱️ **~60–90 min** (dashboard, 3 vhosts, première fois). Réversible à 100 %.
> 👤 Acteur : **humain** (clics Cloudflare + édition Caddyfile) ; **Claude** pour la vérification/audit.

## Pourquoi (et pourquoi c'est optionnel mais recommandé)

La stack cœur (steps 00→02) tourne **sans** cette brique. Mais dès que le tunnel est actif, les 3 vhosts sont sur Internet : pages de login n8n/NocoDB publiques, écrans métier et `/webhook/api/*` joignables par un anonyme qui devine l'URL (certificate transparency, scan DNS). Optionnel techniquement, **obligatoire de fait avant d'y mettre de la donnée réelle**.

Modèle de menace + standard de durcissement complet : **`SECURITY.md`** (repo méta `spark-kit`).
Runbook pas-à-pas CF Access (dashboard + Terraform + Service Tokens + vérif) : **[`docs/cf-access.md`](../../docs/cf-access.md)**.

## Ce que la brique couvre (3 sous-briques)

| Sous-brique | Effet | Référence |
|---|---|---|
| **CF Access** devant `-n8n` / `-app` / `-db` | un anonyme reçoit un `302` vers un mur de login (SSO/OTP) au lieu de l'app | `cf-access.md` §3 + §10 |
| **Headers Caddy** (HSTS, X-Frame, X-Content-Type, Referrer-Policy, Permissions-Policy, `-X-Powered-By`) | durcit chaque réponse | `SECURITY.md` §2.2 |
| **CORS NocoDB** scopé sur `-app` | empêche un site tiers d'exploiter l'API NocoDB depuis le navigateur d'une victime | `SECURITY.md` §2.3 |

## Phase 1 — Prérequis humains (~10–15 min)

- [ ] Tunnel actif : les 3 vhosts répondent en HTTPS (étape 4 du README méta).
- [ ] Compte **Cloudflare Zero Trust activé** (gratuit jusqu'à 50 users). Noter le **team domain** (`<slug>.cloudflareaccess.com`, sous *Settings → Custom Pages*).
- [ ] Choisir la méthode d'identité : **Microsoft Entra ID** (si M365), sinon **Google OAuth**, sinon **One-time PIN** (code email, zéro config — parfait pour démarrer/tester).

## Options Cloudflare à prendre (récap décisionnel)

| Option | Où dans Cloudflare | Pourquoi / quand |
|---|---|---|
| Activer **Zero Trust** | dash → Zero Trust | prérequis de tout le reste |
| Brancher un **IdP** ou laisser **One-time PIN** | Zero Trust → Settings → Authentication | méthode de login des humains |
| **1 Access Application** (Self-hosted) **par vhost** | Zero Trust → Access → Applications | c'est ce qui ferme l'accès anonyme |
| **Policy Allow** (emails, ou *emails ending in* `@client.tld`) | dans chaque application | qui a le droit d'entrer |
| **Service Token** | Zero Trust → Access → Service Auth | laisser passer une **machine** (CLI NocoDB host, sonde, callback SaaS) — rotation **90 j** |
| Token API scope **`Access: Apps and Policies — Edit`** | dash → My Profile → API Tokens | seulement si on fait la voie **Terraform** (IaC multi-sites). ⚠️ le token `Zone:DNS:Edit` du tunnel ne suffit pas |
| (Recommandé) **WAF + Rate Limiting** sur la zone | dash → Security | ralentir le bruteforce des pages de login restantes |

> 💡 Un CLI/MCP qui tape un vhost **depuis le réseau Docker interne** (`http://service:port`) n'est **pas** concerné par Access — il ne traverse jamais Cloudflare. Seuls les appelants qui passent par le bord CF ont besoin d'un Service Token.

## Phase 2 — Exécution (~30–45 min)

Ordre éprouvé (détail : `cf-access.md` §10) — protéger les vhosts un par un sans rien casser :

1. **`-n8n` d'abord** (cobaye, faible trafic) : Access → Applications → Add → Self-hosted → domain `<prefix>-n8n.<domain>` → policy Allow (tes emails) → IdP/OTP → session 24h → Save. Vérifier qu'un anonyme prend un `302` et que l'outillage agent interne reste vert.
2. **`-app`** : ⚠️ **pré-requis code, pas Cloudflare** — les fronts doivent appeler leur API en **same-origin** (`/webhook/...`), jamais l'URL absolue d'un autre sous-domaine, et **aucune iframe** d'UI NocoDB (sinon les XHR cassent sous Access). Puis créer l'app Access. **Coupe l'accès anonyme immédiatement** → fenêtre dédiée + prévenir l'équipe.
3. **`-db`** (NocoDB) : décider **avant** l'accès du tooling host → préférer le **bypass reverse-proxy local** (`http://127.0.0.1:<port>` + en-tête `Host: <prefix>-db.<domain>`) qui reste insensible à Access sans Service Token. Puis créer l'app Access.
4. **Headers Caddy + CORS** : ajouter le bloc `header { ... }` standard sur chaque vhost et le `Access-Control-Allow-Origin` scopé sur `-db` (copier depuis `SECURITY.md` §2.2/§2.3), puis `docker compose restart caddy`.

## Phase 3 — Validation (~10 min)

```bash
PREFIX=<prefix>; DOMAIN=<domain>
# Auth devant chaque vhost — attendu : 302/403 -> *.cloudflareaccess.com
for h in $PREFIX-n8n $PREFIX-app $PREFIX-db; do
  curl -sS -o /dev/null -w "$h : %{http_code} -> %{redirect_url}\n" --max-time 10 "https://$h.$DOMAIN/"
done
# Headers de sécurité présents (cf. SECURITY.md §6.1) ; CORS de -db scopé sur -app, pas '*'
```

- Anonyme → `302/403` vers le team domain sur les 3 vhosts.
- Parcours **humain authentifié** en navigateur : login CF → l'app charge → une action réelle → les XHR `/webhook/*` passent (cookie same-origin).
- **Outillage interne intact** : MCP/runtime n8n→NocoDB (`http://service:port`) répond toujours ; CLI host via bypass local → `200`.

Audit complet (headers, webhooks publics, API 401, findings types `FX-01…11`) : `SECURITY.md` §6–§7.

## Phase 4 — Teardown / rollback

- Supprimer les **Access Applications** (dashboard) → retour immédiat au `200`. Aucun impact sur le tunnel ni le DNS.
- Retirer le bloc `header` du Caddyfile + `restart caddy` si on veut aussi annuler le durcissement HTTP.
- Révoquer les Service Tokens créés.

## Sources

- Runbook CF Access (dashboard + Terraform + Service Tokens) : [`docs/cf-access.md`](../../docs/cf-access.md)
- Standard de durcissement (modèle de menace, headers, CORS, audit, findings) : `SECURITY.md` (repo méta `spark-kit`)
- Recettes Caddy par site : `infra/docs/caddy.md` (repo du site)
- PRD type « Auth Entra ID / M365 via CF Access » : voir un site déployé (ex. kyklos PRD-011)
