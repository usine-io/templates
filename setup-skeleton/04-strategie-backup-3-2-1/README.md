# Step 04 — Stratégie de backup 3-2-1 (placeholder)

> ⏳ **Pas encore implémenté.** Spec à fleshout, pas de scripts.

## Pourquoi cette étape

`wiki/topics/architecture-technique.md` §2.3 spécifie une stratégie 3-2-1 :

| Couche | Méthode | Fréquence | Rétention |
|---|---|---|---|
| PostgreSQL | `pg_dumpall` → `.sql.gz` | 6h | 7j local |
| Volumes Docker | `tar` des volumes nommés | quotidien | 7j local |
| Offsite | `rclone sync` → Backblaze B2 | quotidien | 30j |
| USB | copie locale (optionnel) | hebdo | 4 semaines |

Aucun script n'est livré pour l'instant. Step 04 = livrer ces scripts + cron + valider une **drill de restore** (un dump est inutile s'il n'est pas restaurable).

## Prérequis

- step 02 ✅ (la stack tourne)
- Compte Backblaze B2 (créé par toi) avec une bucket `<B2_BUCKET>` et un key pair (write-only depuis le Mac Mini)
- Un disque USB optionnel branché si on veut la 4e couche

## Plan d'action (à dérouler quand on attaquera)

### Phase 1 — Prérequis humains
- [ ] Créer compte B2 (https://www.backblaze.com)
- [ ] Créer bucket et key pair, scope write-only
- [ ] Coller `B2_ACCOUNT_ID`, `B2_APPLICATION_KEY`, `B2_BUCKET` dans `infra/.env`

### Phase 2 — Scripts à livrer (tous dans `infra/scripts/backup/`)
- `pg-dump.sh` : `docker exec ${SPARK_PREFIX}-postgres-1 pg_dumpall -U postgres | gzip > /backups/pg-$(date +%Y%m%d-%H%M).sql.gz`. Rotation 7j local.
- `volumes-tar.sh` : tar des volumes Docker nommés (`${SPARK_PREFIX}_n8n_data`, `${SPARK_PREFIX}_nocodb_data`, etc.).
- `rclone-push.sh` : `rclone sync /backups/ b2:<B2_BUCKET>/` avec rétention 30j côté B2.
- `usb-copy.sh` (optionnel) : si `/Volumes/SPARK_BACKUP` monté, rsync vers le disque.
- `restore-drill.sh` : monte un container postgres temporaire, restore le dernier dump, vérifie qu'il y a des rows. Idempotent et non-destructif (pas de write sur la prod).

### Phase 3 — Cron à configurer (launchd ou crontab du user spark)
- `pg-dump.sh` : toutes les 6h
- `volumes-tar.sh` + `rclone-push.sh` : 1×/jour à 3h du matin
- `restore-drill.sh` : 1×/semaine, dimanche 4h du matin → notifier via Kuma webhook si fail

### Phase 4 — Validation
- Lancer manuellement chaque script
- Vérifier les fichiers produits (taille, lisibilité d'un échantillon)
- Lancer `restore-drill.sh` → doit réussir

## Découvertes anticipées

- `pg_dumpall` plutôt que `pg_dump` parce qu'on veut TOUS les rôles + les 2 bases (n8n + nocodb) en une fois.
- rclone gère bien B2 nativement (config interactive `rclone config`, ou via env vars).
- La drill de restore est **le critère de validation** — un backup non-testé n'est pas un backup.

## Sources

- `wiki/topics/architecture-technique.md` §2.3 (table des couches)
- Doc rclone B2 : https://rclone.org/b2/
- Best practices PG backup : `pg_dumpall` vs `pg_basebackup` (on reste sur pg_dumpall pour simplicité, basebackup pour PITR un autre jour)
