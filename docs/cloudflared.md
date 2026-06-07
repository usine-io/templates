# Setup Cloudflare Tunnel — exemple projet ACME

> Document générique transmissible. Substituer `ACME`/`acme` par le slug court du projet client
> et `<domain>` par la zone Cloudflare réelle.
> Aucune valeur de secret n'apparaît ici.
> Pour **authentifier** les hostnames exposés par ce tunnel (mur de login devant les UI/apps), voir [`cf-access.md`](cf-access.md).

---

## 1. Le modèle retenu : "tunnel local-managed" (pattern A)

Trois façons de faire tourner un tunnel Cloudflare existent. Choix : **la plus simple.**

| Pattern | Où vit la config ingress | Où tourne cloudflared | Commentaire |
|---|---|---|---|
| **A — local-managed** ✅ | YAML sur le Mac hôte (`~/.cloudflared/config-*.yml`) | Process Mac (lancé via `cloudflared tunnel run …`) | Lisible, scriptable, pas de dashboard. **Choix retenu.** |
| B — remote-managed | Dashboard Cloudflare Zero Trust | Mac ou container | Clic-clic, mais pas de versioning |
| C — sidecar in-compose | YAML monté dans le container | Service Docker dédié | Couple le tunnel au cycle de vie de la stack. Trop rigide pour un Mac qui sert plusieurs projets |

**Conséquence du choix A** : un seul process `cloudflared` sur le Mac, son YAML est édité par script, plusieurs projets clients peuvent coexister dans le même fichier.

---

## 2. Schéma du flux

```
Browser
   │  https://acme-app.<domain>/...
   ▼
Cloudflare edge  ← CNAME résout vers <tunnel-id>.cfargotunnel.com
   │
   │   tunnel encapsulé (sortant, depuis le Mac)
   ▼
cloudflared (sur le Mac hôte, port aléatoire sortant)
   │
   │   selon l'ingress YAML : tout acme-* → http://localhost:18080
   ▼
Caddy (container Docker, exposé en host port 18080)
   │
   │   reverse-proxy interne (Caddyfile)
   ▼
Service cible (n8n, NocoDB, front statique, Uptime Kuma)
```

Points clés :
- **Le tunnel ne voit qu'un seul port hôte** : `18080`. Toute la démultiplexation par sous-domaine est faite par Caddy.
- **Pas d'IP publique sur le Mac** : seul cloudflared parle vers l'extérieur (sortant, ports 7844/443).
- **Le DNS est géré par script** : les CNAMEs sont créés/supprimés via l'API Cloudflare.

---

## 3. Les sous-domaines exposés

Pour le préfixe `acme` :
- `acme-app.<domain>` — front (Caddy file_server + apps statiques)
- `acme-n8n.<domain>` — n8n
- `acme-db.<domain>` — NocoDB
- `acme-status.<domain>` — Uptime Kuma

Tous pointent vers le **même CNAME tunnel**, c'est Caddy qui aiguille.

---

## 4. Les variables nécessaires (côté `.env`, valeurs non transmises)

| Variable | Rôle |
|---|---|
| `ACME_DOMAIN` | Domaine parent (ex. `<domain>`) |
| `ACME_PREFIX` | Préfixe des sous-domaines (ici `acme`) |
| `ACME_TUNNEL_ID` | UUID du tunnel Cloudflare (créé une fois via `cloudflared tunnel create`) |
| `ACME_TUNNEL_CONFIG` | Chemin du YAML cloudflared sur l'hôte (ex. `~/.cloudflared/config-<zone>.yml`) |
| `ACME_HOST_HTTP_PORT` | Port hôte vers Caddy (défaut `18080`) |
| `CF_API_TOKEN` | Token Cloudflare avec scope `Zone:DNS:Edit` sur la zone |
| `CF_ZONE_ID` | ID de la zone parente |

Le **`credentials.json`** du tunnel (généré par `cloudflared tunnel create`) vit dans `~/.cloudflared/<tunnel-id>.json` et n'est pas dans le `.env`.

---

## 5. Le mécanisme d'édition idempotente du YAML

Le YAML cloudflared est partagé entre plusieurs projets. Chaque projet ajoute/retire **son propre bloc** délimité par des marqueurs :

```yaml
ingress:
  # >>> acme-begin (auto: scripts/tunnel-up.sh — ne pas editer)
  - hostname: acme-app.<domain>
    service: http://localhost:18080
  - hostname: acme-n8n.<domain>
    service: http://localhost:18080
  - hostname: acme-db.<domain>
    service: http://localhost:18080
  - hostname: acme-status.<domain>
    service: http://localhost:18080
  # <<< acme-end
  - service: http_status:404      # catch-all obligatoire en fin
```

Le bloc est inséré **juste avant le catch-all 404**. Avantages :
- Plusieurs projets cohabitent sans interférence (marqueurs nommés par préfixe).
- Toujours réversible (`tunnel-down.sh` supprime exactement la zone marquée).
- Backup `.bak.<timestamp>` à chaque édition.

---

## 6. Les deux scripts

`infra/scripts/tunnel-up.sh` — fait **3 choses** :
1. Insère le bloc d'ingress dans le YAML (skip si déjà présent → idempotent).
2. Crée les CNAMEs via API Cloudflare (skip si déjà présents).
3. Envoie `SIGHUP` au process cloudflared pour qu'il recharge la config sans downtime.

`infra/scripts/tunnel-down.sh` — fait l'inverse :
1. Retire le bloc (entre marqueurs).
2. Supprime les CNAMEs.
3. SIGHUP.

Les deux sont **idempotents** : on peut les rejouer sans casser quoi que ce soit.

---

## 7. Pré-requis machine (one-time, hors scripts)

À faire **une fois par Mac hôte** :

```bash
brew install cloudflared jq
cloudflared tunnel login                       # ouvre un navigateur, lie le compte CF
cloudflared tunnel create acme                 # génère l'UUID + credentials.json
```

Le process cloudflared lui-même est lancé en arrière-plan (ex. via `launchd` ou simplement `cloudflared tunnel --config ~/.cloudflared/config-<zone>.yml run &`). Les scripts `tunnel-up/down` **ne le démarrent pas** — ils le supposent actif et lui envoient SIGHUP.

---

## 8. Cycle de vie typique

```bash
# Mise en service (après docker-compose up)
bash infra/scripts/tunnel-up.sh
# → ~10s plus tard, les 4 URLs répondent

# Mise hors service (déprovisionnement client)
bash infra/scripts/tunnel-down.sh

# Diagnostic
pgrep -f cloudflared                           # process actif ?
curl -sI https://acme-app.<domain>/            # 200 attendu
```

---

## 9. Pourquoi c'est sûr

- **Aucun port ouvert sur le Mac** : tunnel sortant uniquement.
- **TLS terminé chez Cloudflare** (auto-renouvelé), pas de gestion certif côté Mac.
- **API token scopé** (`Zone:DNS:Edit` sur la seule zone parente, pas Account-wide).
- **Le `credentials.json` du tunnel** ne sort jamais du Mac.
- **Le `.env` est gitignored**, jamais commité.

---

## 10. Pour un nouveau projet client sur la même machine

Tout ce qu'il faut : un nouveau préfixe (`projet01`, `projet02`…), copier les scripts, changer les noms de variables (`ACME_*` → `<PREFIX>_*`) et les marqueurs (`# >>> <prefix>-begin`). Le même tunnel Cloudflare peut servir plusieurs projets, ou chaque projet peut avoir le sien — au choix.
