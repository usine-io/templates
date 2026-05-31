# Setup — bootstrap Spark sur un nouveau site

> Étapes one-shot d'amorçage du déploiement. Le **cœur** (00→02) se passe **dans l'ordre** à l'installation. Les **briques optionnelles** (03→05) se posent ensuite, à la carte.
>
> Chaque step a 4 phases : **prérequis humains** → **exécution** → **validation** → **teardown** (optionnel). Le step est "validé" quand le statut passe à ✅ ci-dessous, idéalement avec un lien vers le commit qui valide.

## La stack en 3 briques

Un déploiement Spark se lit comme **trois briques empilables**, pas un monolithe :

1. **Solution technique** (cœur, obligatoire) — n8n + NocoDB + Postgres + Caddy + tunnel Cloudflare. ~30 min, donne une stack qui tourne et est joignable en HTTPS. C'est le contenu du README `spark-kit` (méta) + steps 00→02 ci-dessous.
2. **Recommandations de sécurité** (optionnel, **recommandé avant toute donnée réelle**) — Cloudflare Access devant les vhosts, headers Caddy, CORS NocoDB. Ferme l'accès anonyme aux UIs/webhooks exposés. Step 03 + `SECURITY.md` (méta).
3. **Brique de sauvegarde déployable** (optionnel, recommandé) — backup 3-2-1 scripté (pg_dumpall + tar volumes + drill de restore + offsite B2). Step 04.

> La brique 1 seule = un prototype joignable. Les briques 2 et 3 la rendent **exploitable en production**. Elles sont indépendantes : on peut poser la sauvegarde sans la sécurité, ou l'inverse.

## Cœur technique — obligatoire

| # | Step | Acteur principal | ⏱️ | Prérequis |
|---|---|---|---|---|
| 00 | [Générer les secrets `.env`](00-generer-secrets-env/) | humain (lance le script) | ~5 min | Mac + bash |
| 01 | [Créer comptes admin + tokens API](01-creer-comptes-et-tokens/) | humain (UI clicks + copy-paste) | ~15 min | step 00 + stack up |
| 02 | [Vérifier la liaison n8n ↔ NocoDB](02-verifier-liaison-n8n-nocodb/) | Claude (`./run.sh` / `./teardown.sh`) | ~10 min | step 01 |

## Briques optionnelles

| # | Brique | Statut conseillé | ⏱️ | Acteur | Options / comptes externes à prendre |
|---|---|---|---|---|---|
| 03 | [Sécurité / authentification (CF Access)](03-securite-cf-access/) | **recommandé en prod** | ~60–90 min | humain (clics Cloudflare + Caddyfile) + Claude (vérif/audit) | **Cloudflare Zero Trust** activé (Free, ≤50 users) ; un **IdP** (Entra ID / Google) **ou** One-time PIN ; **Service Token** par machine qui doit franchir Access |
| 04 | [Stratégie de backup 3-2-1](04-strategie-backup-3-2-1/) | recommandé | ~45–60 min local (+~25 min si offsite) | Claude (scripts + cron) + humain (compte B2) | **compte Backblaze B2** + bucket + key pair (uniquement pour la couche offsite) |
| 05 | [Versionning des workflows n8n](05-versionning-workflows-n8n/) | confort | ~20 min | Claude (script export+commit) | — |

> Les ⏱️ sont des ordres de grandeur « première fois, à la main » (dashboard, pas IaC). La 2e fois va plus vite. Le détail du chiffrage est dans le README de chaque step.

## Convention

- **Préfixe `_t_*`** pour tout objet de test/setup (tables NocoDB, workflows n8n, webhooks). Repérable d'un coup d'œil dans les UIs, suppressible en bloc via le `teardown.sh` du step.
- **Tokens et secrets** : seul `infra/.env` les détient (gitignored). Les commandes du setup utilisent des `read -p` interactifs pour qu'on ne tape jamais un secret dans un message ou un commit.
- **Promotion vers la template** : une fois un step validé sur un premier site, il est candidat à l'extraction vers `spark-templates/setup-skeleton/<step>/` avec abstraction des URLs/noms client-spécifiques. À faire seulement après stress-test sur ce 1er site.
