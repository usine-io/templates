---
name: spark-frontend-patterns
description: Patterns et pièges des fronts statiques Spark (HTML/JS servis par Caddy sur le vhost -app). Use when creating/editing a Spark front page, wiring a front to n8n webhooks, building a shared UI component, generating a file download (ZPL/PDF), or debugging "le bouton ne fait rien sans erreur console", a CF Access 302 on an XHR, or stale JS after deploy. Couvre F1 + P2/P4/P5/P6 + anti-pattern iframe + cache Cloudflare.
metadata:
  spark:
    layer: frontend
    source: spark-pitfalls-catalog (F1, P2/P4/P5/P6, N24, C4/C6)
    arch: "front statique Caddy (-app) -> webhooks n8n (same-origin)"
---

# Fronts statiques Spark — patterns & pièges

> Un front Spark = HTML/JS statique servi par **Caddy** sur le vhost `<prefix>-app`, qui parle à **n8n** via des webhooks. Pas de framework, pas de build — du JS vanilla maîtrisé.
> Voir `spark-n8n-pseudo-api` pour le backend, `spark-stack-ops` pour Caddy/Cloudflare.

---

## 🚨 F1 — ne JAMAIS nommer une fonction comme une propriété de `window`

`confirm`, `alert`, `prompt`, `name`, `open`, `print`, `close`, `status`… sont des propriétés natives de `window`. Définir une fonction top-level avec un de ces noms dans un `<script>` inline crée un **conflit silencieux** :

```html
<!-- ❌ Symptôme : clic = RIEN ne se passe, AUCUNE erreur console -->
<script>
  function confirm(id) { … }          // écrase / entre en collision avec window.confirm
</script>
<button onclick="confirm(42)">OK</button>
```

`onclick="confirm(…)"` peut résoudre vers la **dialog native**, ou créer une **boucle infinie** si la fonction custom appelle `window.confirm()`. C'est l'un des bugs les plus déroutants (zéro trace).

➡️ **Préfixer/suffixer systématiquement** : `confirmSortie`, `confirmX`, `promptGrade`, `openModal`… Vécu sur WMS (boutons de sortie diagnostic inertes).

---

## 🚨 Appels API en relatif, jamais en absolu (CF Access)

Les vhosts publics passent derrière **Cloudflare Access**. Front (`<prefix>-app`) et webhooks n8n sont **same-origin** → le cookie CF se propage aux XHR **seulement en relatif**.

```js
// ✅ relatif — same-origin, cookie CF propagé
fetch('/webhook/api/wms/commandes')

// ❌ absolu — cross-origin vers <prefix>-n8n → 302 vers le login CF, XHR cassée
fetch('https://acme-n8n.acme.example/webhook/api/wms/commandes')
```

Hardcoder l'hôte n8n comme base d'API d'un front est un **anti-pattern** (Caddy route déjà `/webhook/*` vers n8n sur le même origin). Détail CF Access : `docs/cf-access.md`.

---

## 🚨 Anti-pattern — pas d'`<iframe>` d'UI NocoDB (N24)

Ne jamais embarquer l'UI NocoDB dans un front (`<iframe src="https://<prefix>-db…">`) :
- **Aucune valeur ajoutée** : on ré-expose le chrome NocoDB brut au lieu d'un écran métier maîtrisé.
- **Casse sous CF Access** : login CF dans l'iframe (cross-origin, pas de cookie) ou `X-Frame-Options`/CSP qui bloque l'embed.
- **Cross-origin** : autre sous-domaine que le front → murs CORS/credentials.

➡️ Un front consomme NocoDB **uniquement** via les webhooks n8n (same-origin). Si une vue NocoDB suffit, **linker** NocoDB en clair plutôt qu'embarquer.

---

## P4 — composant partagé « skeleton + slot »

Pour des pages qui partagent header/sidebar (ex. les 5 modes d'un dossier WMS), un seul composant JS partagé rend le commun, chaque page peuple un slot :

```js
// dossier-skeleton.js (chargé par toutes les pages mode)
window.WMS.skeleton.renderSkeleton({
  code,                       // identifiant métier (issu du scan)
  mode: 'diagnostic',         // sélectionne le contenu central
  onLoaded(data) { /* la page mode reçoit l'agrégat, sans re-fetch */ }
});
// chaque page mode remplit #mode-content-root
```

Réutilisé par 5 pages avec 1 seul fichier. CSS partagé `*-skeleton.css`. Bascule responsive (sidebar en haut < 900px).

## P5 — login opérateur via `localStorage` (POC, avant vraie auth)

Pas d'auth en POC, mais besoin de tracer qui fait quoi :

```js
localStorage.setItem('wms_user_id', selectedId);   // sélecteur en haut de chaque page opérateur
// envoyé dans le body des POST pour l'audit (evenements.user)
```

## P6 — téléchargement d'un fichier généré côté front

Pour un fichier produit par un workflow (ZPL d'étiquette, PDF…), le renvoyer en string dans la réponse JSON puis :

```js
const blob = new Blob([zplString], { type: 'text/plain' });
const a = Object.assign(document.createElement('a'),
  { href: URL.createObjectURL(blob), download: `${code}.zpl` });
a.click(); URL.revokeObjectURL(a.href);
```

## P2 — résolution FK côté front (rappel)

Liste avec FK à afficher → endpoint `/{ressource}-detail?id=X` (résout via `/links`, cf. `spark-nocodb-v3-patterns`), et le front fait `Promise.all` sur la liste. Tient jusqu'à ~50 records. Au-delà, optimiser côté workflow.

---

## Cache Cloudflare en dev (C4/C6)

- **🚨 C6 — `.js` mis en cache agressif** : Cloudflare sert les `.js` avec `max-age=14400` + `cf-cache-status: HIT` → une modif de JS met **jusqu'à 4 h** à se propager (symptôme : « mon fix ne fait rien »). Les `.html` sont en `DYNAMIC` (non cachés), donc OK.
  ➡️ **Bumper `?v=N`** sur les `<script src="…?v=2">` (éditer dans **toutes** les pages qui le référencent). En prod : Cache-Control plus court côté Caddy sur les statiques mutables, ou purge CF à chaque deploy.
- **C4** : pendant le dev, `?nocache=$(date +%s)` ou `Ctrl+F5` pour bypasser. Non critique en prod.

---

## Check-list avant de livrer une page

1. Aucune fonction top-level nommée comme une propriété `window` (F1) ?
2. Tous les `fetch` en **relatif** (`/webhook/api/…`) ?
3. Pas d'`<iframe>` NocoDB ?
4. Si JS partagé modifié → `?v=N` bumpé partout (C6) ?
5. Header `user_id` (localStorage) envoyé sur les écritures (P5) ?
