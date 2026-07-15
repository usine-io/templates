---
name: spark-nocodb-v3-patterns
description: Pièges et patterns empiriques NocoDB v3 (CE 2026.04.5+) sur stack Spark. Use when modeling data, creating NocoDB tables/fields, writing n8n workflows that read/write NocoDB, debugging Links/Lookups/filters, or hitting "le lien ne se crée pas", "where sur FK renvoie 0", "bulk delete silencieux", "Lookup renvoie un array/null", "/links renvoie records vide", "GET record lent". Complète (ne remplace pas) la skill `nocodb` de référence API.
metadata:
  spark:
    layer: data
    source: spark-pitfalls-catalog (N1-N28)
    nocodb_version: "2026.04.5+ CE"
---

# NocoDB v3 — pièges & patterns Spark

> Couche **empirique** au-dessus de la skill `nocodb` (qui documente l'API v3 brute).
> Ici : ce qui fait perdre 20-60 min à découvrir et 3 s à éviter. Cristallisé sur la chaîne WMS v2 (102 assertions E2E, 6 PRDs) puis enrichi (dernier : 2026-07-15, N26-N28 + N25 raffiné).
> **Cible : NocoDB Community Edition 2026.04.5+, API v3, PAT (`xc-token`).**

---

## 🚨 Les 4 pièges qui coûtent le plus

### 1. Insert avec FK ≠ création du lien (N3 — vécu 4 fois)

Passer une FK dans le body d'insert **ne crée PAS le lien**. Le champ Link renvoie ensuite `1` (= « 1 lien »), mais ce `1` n'a **aucun référent réel**.

```jsonc
// ❌ NE CRÉE PAS LE LIEN — juste un compteur fantôme
POST /api/v3/data/{base}/{table}/records
{ "fields": { "commande": { "id": 42 } } }
```

```bash
# ✅ Créer le lien APRÈS l'insert, séparément (N4 — pattern universel)
POST /api/v3/data/{base}/{table}/links/{link_field_id}/{record_id}
[ { "id": 42 } ]
```

Dans un workflow n8n : insert → récupérer l'id créé (`{{ $json.records[0].id }}`) → 1 POST `/links` par FK. C'est **le** pattern de toute écriture avec relations.

### 2. Lecture Links = compteurs, pas d'objets (N5/N6/N21)

La liste des records renvoie `0/1/2…` sur les champs Link (nombre de liens), **jamais** l'objet expansé (contrairement à v1).

```bash
# Résoudre les FK : GET /links, en explicitant les champs voulus
GET /api/v3/data/{base}/{table}/links/{link_field_id}/{record_id}?fields=Id,nom,statut
```

⚠️ **N21** : sans `?fields=`, `/links` ne renvoie **que le display field** (1er SingleLineText). Tous les autres champs sont *omis* (même pas `null`). Toujours expliciter `?fields=`.
⚠️ **N26 — 🚨 le `?fields=` d'un `/links` doit inclure `Id`** : `?fields=code,nom` (sans `Id`) → `records: []` **vide silencieux** alors que les liens existent. Pire que N21 : on perd les records eux-mêmes, pas juste des champs. Toujours `?fields=Id,…`.
⚠️ Résolution N+1 par défaut → voir pattern d'agrégat par Lookups plus bas (N24).

### 3. `where` sur un champ Link ne marche pas (N7/N8)

```bash
# ❌ Renvoie 0 résultat même si des liens existent
GET ...?where=(commande,eq,42)
```

Deux contournements (N8) :
- **(a)** interroger le `/links` **inverse** côté table opposée (NocoDB crée auto un Link inverse pour tout `belongsTo`, cf. N13 — son nom est trouvable via `field:list`) ;
- **(b)** ajouter un Link `belongsTo` **dénormalisé direct** vers le parent recherché (ex. `pannes_dossier.dossier` posé en plus de `pannes_dossier.test`) → permet un `where=(dossiers_id,eq,X)` simple. À réserver aux volumes modérés.

> Pour filtrer sur une FK « normale » (belongsTo), le `where` veut le **nom de colonne FK réel** (`dossiers_id`), pas le nom logique (`dossier`) → 400 sinon. Vérifier le vrai nom dans le schéma.

### 4. Bulk insert ET delete cap à 10 — delete échoue *silencieusement* (N2)

`POST`/`DELETE` bulk au-delà de 10 records → `ERR_MAX_PAYLOAD_LIMIT_EXCEEDED` (insert) ou **0 suppression sans aucune erreur** (delete). Toujours **batcher par 10** et **vérifier le retour** (`len(records supprimés)`), sinon boucle infinie possible si le caller re-page sans contrôle.

---

## Lookups (N19/N20/N24/N25/N27)

Les Lookups sont la bonne arme contre le N+1 sur les agrégats — mais 5 chausse-trappes :

- **N19 — schéma de création** : `options.related_field_id` (= ID du **Link** sur la table source) + `options.related_table_lookup_field_id` (= ID du **champ à lookup-er** sur la cible). **PAS** `fk_relation_column_id` / `fk_lookup_column_id` (noms intuitifs mais faux → 400).
- **N20 — réponse = ARRAY** : un Lookup renvoie `["Samsung Galaxy S7"]`, jamais la string nue, **même** pour un belongsTo 1:1. Le consommateur fait `champ[0]`.
- **N24 — agrégat N:N propre** : poser des Lookups sur la **table de jonction** (ex. `piece_id_l` via Link pieces + `loc_type_l` via Link localisations) permet de fetch toutes les jointures avec attributs résolus **en 1 call** → agrégat côté Code node. Évite le N+1×2. **Pattern réutilisable.**
- **N25 (raffiné 2026-07-15) — 🚨 la collision de Lookups est PAR LIEN** : plusieurs Lookups du **même** Link coexistent dans un seul `?fields=` (ex. `sku_code_lookup` + `sku_libelle_complet`, tous deux via le Link `sku_kyklos` → les 2 corrects). C'est un Lookup d'un **autre** Link dans le même `?fields=` qui revient `[null]` — valeur perdue, sur `/records/{id}` comme sur les listes. **Workaround : 1 fetch HTTP par Link porteur de Lookups** (pas par Lookup), combiner dans Build Response. ⚠️ **Faux négatif de test** : sur un record dont le lien est vide, `[]` semble correct → tester la collision sur un record où **tous** les liens concernés sont peuplés avant de "simplifier" des fetchs séparés existants.
- **N27 — 🚨 Lookup sur un lien m2m = `null` systématique** : un Lookup posé sur un Link `relation_type: "mo"` (m2m) renvoie `null` partout, même avec une config identique aux Lookups belongsTo qui marchent et un lien peuplé. **Vérifier `relation_type` du Link (meta table) AVANT de créer un Lookup dessus.** Workaround batching sans changement de schéma : joindre via une table intermédiaire belongsTo + colonne FK dénormalisée (ex. `dossiers → ligne_commande` par `/links` inverse par ligne + `lignes_commande.produit_kyklos_id`) → O(intermédiaires) appels au lieu de O(records).

---

## CRUD & schéma — réflexes

| # | Règle |
|---|---|
| N1 | **PAT (`xc-token`) sur v3 uniquement** — v1/v2 → 403 sur 2026.04.5+. |
| N9 | **GET single par valeur naturelle** (code, ref) : `?where=(code,eq,X)&pageSize=1` puis check `records.length === 1`. Pas d'endpoint dédié. |
| N10 | **GET single par ID interne** : `GET /records/{id}` (sans `?where`) — plus rapide quand on a l'id. Toujours avec `?fields=` (N28). |
| N11 | **SingleSelect création** : `options.choices: [{title:"X"}, …]` (pas besoin de color/id). |
| N12 | **Update SingleSelect** : PATCH le field avec la liste **complète** des choices (pas un append — sinon on perd les existants). |
| N13 | **belongsTo crée auto un Link inverse** côté cible (`tableSource` ou `tableSource1`). Indispensable pour les agrégats inverses. Trouvable via `field:list`. |
| N14 | **Formula/Rollup pénibles en v3** → préférer un champ direct géré par n8n (ex. `quantite_stock` updaté à chaque mouvement). |
| N15 | **Renommer une base = cosmétique** : `title` change, ID inchangé. Sûr pour l'archivage. |
| N16 | **Append-only sur tables d'audit** : pas de DELETE, correction = mouvement **compensatoire** (`mouvements_stock`, `evenements`). |
| N17 | **PATCH single** : `{id, fields:{…}}` (objet). **PATCH bulk** : `[{id, fields}, …]` (array). |
| N18 | **MCP NocoDB instable** sur 2026.04.5+ → utiliser le **CLI `nocodb.sh`** de la skill `nocodb`. Cf. INC-2026-05-19. |
| N28 | **🚨 GET `/records/{id}` sans `?fields=` = 10-35× plus lent** (150-750 ms vs ~20 ms mesuré) : NocoDB résout **toutes** les expansions (objets belongsTo, m2m imbriqués, jonctions `_nc_m2m_*`) même si le payload final paraît petit. `?fields=` systématique sur tout GET par id dans un workflow. |

---

## Réponses — wrapping & tri (rappels qui coûtent cher en n8n)

- **Response wrapping** : toute réponse POST/PATCH est `{records:[{id, fields:{…}}]}`. Dans n8n : `{{ $json.records[0].id }}`, **jamais** `{{ $json.id }}`. (Bug #1 historique, chaque endpoint l'a eu.)
- **Sort** : `sort=[{"field":"CreatedTime","direction":"desc"}]` (JSON URL-encodé). Le format v1/v2 `-CreatedTime` → 400 au message trompeur.
- **Types de champs date** : `CreatedTime` / `LastModifiedTime` (pas `CreatedAt`).

---

## Check-list avant tout HTTP NocoDB dans un workflow

1. Écriture avec FK ? → insert **puis** `POST /links` (N3/N4).
2. Lecture qui a besoin des FK ? → `/links?fields=Id,…` explicite (N21 + **Id obligatoire** N26), ou Lookups (N24) en pesant N25/N27 (1 fetch par **lien** ; jamais sur un lien m2m).
3. Filtre sur relation ? → **pas** de `where` sur Link (N7) ; /links inverse (N8a) ou dénorm (N8b) ; FK normale = nom de colonne réel.
4. Bulk ? → batch de 10 + check du retour (N2).
5. Lecture de l'id créé ? → `records[0].id`.
6. GET par id ? → `?fields=` systématique, sinon 10-35× plus lent (N28).

> Promouvoir tout nouveau piège confirmé ici **et** dans `spark-kit/INCIDENTS.md` s'il est transverse à plusieurs sites.
