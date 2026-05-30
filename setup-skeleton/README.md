# Setup — bootstrap Spark sur un nouveau site

> Étapes one-shot d'amorçage du déploiement, à passer **dans l'ordre** lors de l'installation initiale (et à rejouer partiellement en cas de réinstallation propre).
>
> Chaque step a 4 phases : **prérequis humains** → **exécution** → **validation** → **teardown** (optionnel). Le step est "validé" quand le statut passe à ✅ ci-dessous, idéalement avec un lien vers le commit qui valide.

## Ordre des steps

| # | Step | Acteur principal | Statut | Prérequis |
|---|---|---|---|---|
| 00 | [Générer les secrets `.env`](00-generer-secrets-env/) | humain (lance le script) | ⏳ | Mac + bash |
| 01 | [Créer comptes admin + tokens API](01-creer-comptes-et-tokens/) | humain (UI clicks + copy-paste) | ⏳ | step 00 + stack up |
| 02 | [Vérifier la liaison n8n ↔ NocoDB](02-verifier-liaison-n8n-nocodb/) | Claude (`./run.sh` / `./teardown.sh`) | ⏳ | step 01 |
| 04 | [Stratégie de backup 3-2-1](04-strategie-backup-3-2-1/) | Claude (scripts cron pg_dumpall + rclone) + humain (compte B2) | ⏳ placeholder | step 02 |
| 05 | [Versionning des workflows n8n](05-versionning-workflows-n8n/) | Claude (script export+commit) | ⏳ placeholder | step 02 |

## Convention

- **Préfixe `_t_*`** pour tout objet de test/setup (tables NocoDB, workflows n8n, webhooks). Repérable d'un coup d'œil dans les UIs, suppressible en bloc via le `teardown.sh` du step.
- **Tokens et secrets** : seul `infra/.env` les détient (gitignored). Les commandes du setup utilisent des `read -p` interactifs pour qu'on ne tape jamais un secret dans un message ou un commit.
- **Promotion vers la template** : une fois un step validé sur un premier site, il est candidat à l'extraction vers `spark-templates/setup-skeleton/<step>/` avec abstraction des URLs/noms client-spécifiques. À faire seulement après stress-test sur ce 1er site.
