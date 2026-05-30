---
name: spark-poc-method
description: Méthode de cadrage et de livraison d'un POC Spark (discovery → fiche-logiciel → PRD → implémentation → script E2E). Use when scoping a new POC, writing a fiche-logiciel or PRD, deciding an integration approach (file-first vs API), choosing Form NocoDB vs pseudo-API n8n, modeling an internal entity against an external reference, or deciding what is the source of truth. Couvre prepare-then-connect, référentiel-cible vs entité 1er ordre, MD frontmatter SoT, E2E = definition-of-done.
metadata:
  spark:
    layer: method
    source: LESSONS-LEARNED (bilans PRD-001/002) + feedback memories (P7, référentiel, frontmatter)
    templates: "ingest-legacy-docs.md, prd-template.md"
---

# Méthode POC Spark — cadrer & livrer

> Comment ouvrir et livrer un POC qui tient, sans scope creep ni dette. Discipline validée sur mini-CRM (PRD-001), WMS v1/v2 (6 PRDs en chaîne), GRADING, tracker PRD.
> Les skills `spark-nocodb-v3-patterns` / `spark-n8n-pseudo-api` / `spark-frontend-patterns` / `spark-stack-ops` couvrent le **comment construire** ; celle-ci couvre le **quoi construire et dans quel ordre**.

---

## Le cycle : discovery → fiche → PRD → impl → E2E

1. **Discovery** : lire le rapport d'onboarding (`discovery/onboarding/`). Comprendre le process métier réel, pas le process rêvé.
2. **Fiche-logiciel** : pour chaque legacy à brancher, une fiche `discovery/fiches/<soft>.md` (gabarit `ingest-legacy-docs.md`). On documente ce que le système expose **avant** de coder un connecteur.
3. **PRD** : `discovery/prds/prd-NNN-<slug>.md` (gabarit `prd-template.md`). Périmètre **explicite** (+ une section « hors périmètre » qui tient), étapes numérotées, **décisions D1-Dn tranchées à l'avance**.
4. **Implémentation** : workflows n8n + schéma NocoDB + écrans, par étapes du PRD.
5. **Script E2E** : `validate-<poc>.sh` = **definition-of-done exécutable** (voir plus bas).

> Pourquoi ça marche (vécu PRD-001) : le PRD évite le scope creep (« hors périmètre » respecté), les étapes numérotées donnent un cadre, les décisions pré-tranchées évitent les allers-retours.

---

## 🚨 Source de vérité : jamais NocoDB pour le business

**La source de vérité business est toujours le système métier du client** (Phone Check, Pennylane, Google Sheets, ERP, WMS…). NocoDB n'est **jamais** la source de vérité business :
- donnée qui **existe déjà** dans un legacy → NocoDB en est le **cache/staging** ;
- donnée qui **n'existait nulle part** (ex. WMS d'un atelier papier) → NocoDB devient la **source pour cette donnée précise**.

n8n est un **pont contrôlé** qui ouvre des portes **choisies** vers les sources métier.

---

## P7 — préparer le terrain AVANT de connecter

Pour toute intégration externe, **deux phases** :
- **Phase 1** : ingestion **fichier** (drop CSV/Excel/JSON) + **table + UI locale** (ex. admin des codes orphelins). On valide la modélisation et l'UX sur des données réelles, sans dépendre de l'API tierce.
- **Phase 2** : connecteur API qui remplace l'ingestion fichier, une fois la phase 1 prouvée.

Validé sur PhoneCheck, ZPL, Utopya. ➡️ Ne jamais commencer par le connecteur : on se retrouve à débugger l'API tierce **et** la modélisation en même temps.

---

## Référentiel-cible externe vs entité 1er ordre interne

Quand le modèle interne est **plus fin** que la cible externe (PIM, catalogue marketplace), garder l'**interne en entité 1er ordre** (table dédiée) et faire une **correspondance N:1** vers le référentiel-cible externe.

Exemple (PRD-010) : `sku_kyklos` (N, entité 1er ordre) → `ft_easycash` (1, référentiel-cible). Ne pas aplatir l'interne sur la maille externe — on perdrait de l'information métier. Pattern : `get-or-create idempotent` via clé naturelle déterministe.

> Un mauvais **taux de match** lors d'un mapping (ex. 14 % unmatched) n'indique pas toujours un défaut d'algo : **croiser avec le périmètre du référentiel cible** d'abord (le catalogue externe ne couvre peut-être pas ces produits → `unmatched` = signal « hors périmètre », pas un bug).

---

## Décision : Form NocoDB natif vs pseudo-API n8n (PRD-001)

| Critère | Form NocoDB natif | Pseudo-API n8n |
|---------|-------------------|----------------|
| Setup | 2 min (clic UI) | 1-3 h (workflow + debug) |
| Logique métier | impossible (mono-table, pas de side-effect) | oui (multi-table, dérivation, enrichissement) |
| UX | figée (thème NocoDB) | libre (HTML/JS) |
| Maintenance | zéro | workflow à versionner, sensible aux upgrades n8n |

**Règle** : **Form NocoDB natif par défaut**. Passer à la pseudo-API n8n **seulement** si l'opération touche **>1 table** ou a un **side-effect métier**. (Architecture 3 couches Caddy → n8n → NocoDB validée ; n8n n'apporte de la valeur que là où il y a de la logique.)

---

## MD frontmatter = source de vérité des docs de cycle de vie

Pour les **PRDs / incidents / ADRs** Spark : le **frontmatter du fichier MD porte tout** (statut, owner, version…). NocoDB n'en est qu'un **miroir lecture-seule** (sync n8n). Toute mutation = **édition du MD + commit**, pas une écriture NocoDB.

> Ne pas confondre avec la donnée *business* (où le legacy est la SoT). Ici on parle des artefacts de **gouvernance projet**, versionnés dans le repo.

---

## Le script E2E = definition-of-done

Écrire `validate-<poc>.sh` (assertions HTTP sur les endpoints réels) **avant** de déclarer le POC terminé. C'est le « done » **exécutable** : il attrape les régressions de format de réponse immédiatement, et il documente le comportement attendu.

- Standard de fait : 14-24 assertions par PRD, **100 % vertes** avant `live`.
- Couvre les cas nominaux **et** les rejets (validation, 404 de dépréciation, etc.).

---

## Réflexes qui ont payé

- **Charger les skills AVANT de construire**, pas après avoir planté (les bugs parallèle/wrapping/expression auraient été évités). 30 s qui économisent des heures.
- **Rebuild > patcher** un état NocoDB incohérent : full wipe + **seed idempotent** est plus rapide et propre. ➡️ garder les scripts de création **reproductibles et idempotents**.
- **Import de données** : valider le **mapping colonnes→champs** sur un échantillon avant de boucler. Faire les lookups FK **par nom**, pas par ID (les IDs NocoDB sont instables entre rebuilds).
- **Un upgrade n8n** se teste immédiatement (workflows), et **jamais** dans la même session qu'un changement de schéma.
- **Décisions tactiques POC explicites** : assumer et tracer ce qu'on diffère (« atomicité v2 si retour user », « gestion UI NocoDB pour POC ») dans le PRD — pas de dette silencieuse.

---

## Travail à plusieurs (Mac mini partagé)

Un builder = un PRD à la fois, périmètres orthogonaux. `git pull` chaque matin ; ne pas toucher aux tables/workflows d'un PRD qu'on ne porte pas sans coordonner ; commits courts et fréquents ; prévenir avant `docker compose down/restart` ou modif `.env` (cf. `spark-stack-ops` C5).

> Tout apprentissage méthodologique transverse : le promouvoir dans `LESSONS-LEARNED.md` du site **et**, s'il vaut pour tous les sites, dans `spark-kit/INCIDENTS.md`.
