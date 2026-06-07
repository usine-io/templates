# Setup Caddy — reverse-proxy interne (exemple projet ACME)

> Document générique transmissible. Substituer `ACME`/`acme` par le slug court du projet client
> et `<domain>` par la zone Cloudflare réelle.
> Aucune valeur de secret n'apparaît ici. À lire après `cloudflared.md`.

---

## 1. Le rôle de Caddy dans la stack

Caddy est le **démultiplexeur de sous-domaines** placé derrière le tunnel Cloudflare. Toutes les requêtes entrantes arrivent sur un **port hôte unique** (`18080`), et Caddy les aiguille vers les bons containers selon le `Host:` header.

```
Cloudflare Tunnel (1 cible : http://localhost:18080)
            │
            ▼
        Caddy (container)         ← lit Host: acme-{n8n,app,db,status}.<domain>
       ┌────┼────┬────┬────┐
       ▼    ▼    ▼    ▼    ▼
      n8n  WMS  CRM  NocoDB  Uptime Kuma
```

**Pourquoi pas exposer chaque container directement au tunnel** ? Parce qu'on veut :
- Un seul point d'entrée à configurer dans cloudflared (1 ingress rule, pas N).
- Du routing par path (`/wms/*` → front statique, reste → n8n) qu'un tunnel pur ne sait pas faire.
- Pouvoir ajouter/retirer un service sans toucher au tunnel.

---

## 2. Position dans le compose

Extrait du `docker-compose.yml` (service Caddy) :

```yaml
caddy:
  image: caddy:2-alpine
  restart: unless-stopped
  networks: [spark]
  ports:
    - "127.0.0.1:${ACME_HOST_HTTP_PORT}:80"   # ⚠️ bind localhost-only
  environment:
    ACME_DOMAIN: ${ACME_DOMAIN}
    ACME_PREFIX: ${ACME_PREFIX}
  volumes:
    - ./config/Caddyfile:/etc/caddy/Caddyfile:ro
    - ./front-wms:/srv/wms:ro                # bind front statique
    - ./front-mini-crm:/srv/mini-crm:ro
    - caddy_data:/data                       # certifs (inutilisés ici, voir §4)
    - caddy_config:/config
  depends_on: [n8n, nocodb, uptime-kuma]
```

Deux points cruciaux :
- **`127.0.0.1:18080:80`** : le port est bindé **localhost-only** sur le Mac. Inaccessible depuis le LAN, seul `cloudflared` (qui tourne sur le même Mac) peut le joindre.
- **Variables `ACME_DOMAIN` / `ACME_PREFIX`** injectées dans le container : le Caddyfile les interpole pour générer les vhosts dynamiquement.

---

## 3. Anatomie du Caddyfile

```caddy
{
    auto_https off
}

http://{$ACME_PREFIX}-n8n.{$ACME_DOMAIN} {
    reverse_proxy n8n:5678 {
        header_up X-Forwarded-Proto https
    }
}

http://{$ACME_PREFIX}-app.{$ACME_DOMAIN} {
    handle_path /crm/* {
        root * /srv/mini-crm
        file_server
    }
    handle_path /wms/* {
        root * /srv/wms
        file_server
    }
    handle {
        reverse_proxy n8n:5678 {
            header_up X-Forwarded-Proto https
        }
    }
}

http://{$ACME_PREFIX}-db.{$ACME_DOMAIN} {
    reverse_proxy nocodb:8080 {
        header_up X-Forwarded-Proto https
    }
}

http://{$ACME_PREFIX}-status.{$ACME_DOMAIN} {
    reverse_proxy uptime-kuma:3001 {
        header_up X-Forwarded-Proto https
    }
}
```

4 vhosts, 4 destinations. Le 2ᵉ (`acme-app`) est particulier : il **mixe front statique et reverse-proxy** sur le même hostname.

---

## 4. Les deux directives critiques

### `auto_https off` (bloc global)

**Pourquoi** : Caddy par défaut tente d'obtenir un certificat Let's Encrypt pour chaque hostname défini. Ici, **TLS est déjà terminé par Cloudflare** (le tunnel envoie du HTTP en clair au Mac, qui n'est jamais joignable depuis l'extérieur). Activer auto_https ferait :
- Échouer le challenge HTTP-01 (Caddy n'est pas joignable depuis Internet).
- Polluer les logs avec des erreurs ACME.
- Potentiellement faire bannir l'IP par Let's Encrypt rate-limit.

Donc : **`auto_https off` + écoute en `http://`** uniquement. Le volume `caddy_data:/data` reste vide (pas de certifs à persister).

### `header_up X-Forwarded-Proto https`

**Pourquoi** : Caddy reçoit du HTTP du tunnel, mais l'utilisateur final voit du HTTPS dans son navigateur. Sans ce header, les apps en aval (n8n, NocoDB) :
- Génèrent des URLs absolues en `http://` → boucles de redirection, mixed content warnings.
- Refusent de poser des cookies `Secure` → sessions cassées.
- Cassent les websockets (n8n executions live, NocoDB realtime).

Le header transmet l'info "à l'origine c'était du HTTPS" pour que l'app génère des URLs correctes.

---

## 5. Le pattern handle_path (front statique + API)

Pour `acme-app.<domain>` :
- `GET /crm/login.html` → fichier `/srv/mini-crm/login.html` (file_server)
- `GET /wms/dossier.html` → fichier `/srv/wms/dossier.html`
- `POST /webhook/api/wms/dossier` → reverse-proxy vers n8n

**Comment ça marche** : `handle_path /prefix/*` matche le préfixe **et le strip** avant de passer au handler. Le bloc `handle { ... }` final attrape tout le reste (l'API n8n).

L'ordre compte : Caddy évalue les `handle_path` dans l'ordre du fichier, puis `handle` en fallback.

**Pour ajouter un nouveau front** (ex. `app2`) :

```caddy
handle_path /app2/* {
    root * /srv/app2
    file_server
}
```

Plus côté compose, monter le bind : `- ./front-app2:/srv/app2:ro`.

---

## 6. Variables nécessaires (`.env`, valeurs non transmises)

| Variable | Rôle |
|---|---|
| `ACME_DOMAIN` | Domaine parent (ex. `<domain>`) — interpolé dans le Caddyfile |
| `ACME_PREFIX` | Préfixe sous-domaines (ici `acme`) — interpolé dans le Caddyfile |
| `ACME_HOST_HTTP_PORT` | Port hôte exposé vers cloudflared (défaut `18080`) |

Aucun secret côté Caddy : c'est un proxy pur, pas d'auth, pas de TLS. La protection vient de **l'amont (Cloudflare)** et de **l'aval (auth n8n / NocoDB)**.

---

## 7. Cycle de vie typique

```bash
# Démarrage (avec le reste de la stack)
docker-compose -p acme up -d caddy

# Reload après édition du Caddyfile (sans downtime)
docker-compose -p acme exec caddy caddy reload --config /etc/caddy/Caddyfile

# Hard restart (si reload ne suffit pas — rare)
docker-compose -p acme restart caddy

# Diagnostic
docker logs acme-caddy-1 --tail 50
curl -sI http://localhost:18080/ -H "Host: acme-app.<domain>"   # depuis le Mac
```

---

## 8. Piège connu — bind mount + `mv`

Si on **déplace** ou renomme un dossier monté en bind (ex. `mv front-wms front-wms-v1-archive && cp -r nouvelle-version front-wms`), **Caddy continue à servir l'ancien inode**. Le container voit le nouveau dossier mais le file_server cache des références obsolètes.

**Fix** : `docker-compose -p acme restart caddy` après tout `mv` sur un bind mount. Voir piège C1 du `spark-pitfalls-catalog`.

---

## 9. Pourquoi c'est simple

- **Pas de TLS** : géré en amont par Cloudflare. Caddy ne fait que du HTTP.
- **Pas d'auth** : protection en amont (Cloudflare Access en prod) + en aval (n8n basic auth, NocoDB tokens).
- **Pas de log d'accès** : par défaut Caddy ne loggue que les erreurs. Pour debug, ajouter un bloc `log { ... }` dans le vhost concerné.
- **Pas de cache** : tout est passé tel quel au backend. Si latence problématique, voir `cache-handler` plugin.

---

## 10. Pour ajouter un sous-domaine (ex. `acme-flow.<domain>`)

1. **Caddyfile** : ajouter un bloc vhost.
   ```caddy
   http://{$ACME_PREFIX}-flow.{$ACME_DOMAIN} {
       reverse_proxy flow-service:8080 {
           header_up X-Forwarded-Proto https
       }
   }
   ```
2. **`tunnel-up.sh`** : ajouter `acme-flow.<domain>` à la liste `HOSTS`.
3. **Re-run** : `tunnel-up.sh` (crée le CNAME) puis `docker-compose exec caddy caddy reload`.

Aucun cert à gérer, aucune route à déclarer ailleurs.
