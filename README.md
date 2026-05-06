# Spark Templates — Pipeline ingest → PRD → POC

> Gabarits méthodologiques de Spark — pour transformer la découverte d'un client en POC déployable.
>
> Ce repo contient les **gabarits et procédures réutilisables**. Les **instances** (fiches-logiciel d'un client donné, PRD POC d'un projet précis) vivent dans le repo du site client correspondant (ex: `spark-kit/<client>/discovery/`), pas ici.
>
> Privé pour démarrer, conçu pour être rendu public à terme — c'est l'intérêt d'un repo séparé.

---

## Vue d'ensemble du pipeline

```
[wiki Spark]                           [par-site, repo client]                [spark-kit]

questionnaire-onboarding   ────►   discovery/fiches/<soft>.md   ◄────  ingest-legacy-docs.md
(découverte client,                  (1 fiche par logiciel                  (gabarit + checklist)
 déjà existant)                       legacy touché)
                                            │
                                            ▼
                                   discovery/prds/prd-<NNN>-<slug>.md   ◄──  prd-template.md
                                   (1 PRD par POC envisagé)                  (gabarit PRD)
                                            │
                                            ▼
                                   POC implémenté (n8n flows,    ◄────  poc-from-prd.md
                                   tables NocoDB, écrans...)              (à venir — chantier A
                                            │                              en dépendance)
                                            ▼
                                   Déployé chez le client
                                   → boucle d'itération
```

---

## Fichiers de ce repo

| Fichier | Rôle |
|---|---|
| [`ingest-legacy-docs.md`](ingest-legacy-docs.md) | Procédure pour ingérer la doc d'un logiciel legacy → produire une fiche-logiciel structurée |
| [`prd-template.md`](prd-template.md) | Template du PRD pour un POC Spark client (inspiré de `wiki/topics/veille-prd.md`) |
| `poc-from-prd.md` *(à venir)* | Du PRD → assemblage de playbooks → implémentation. Dépend du chantier A (futur repo `spark-kit/playbooks` qui n'existe pas encore). |

---

## Articulation avec le reste de l'écosystème Spark

| Brique | Vit où | Statut |
|---|---|---|
| Manifeste (vision, niveaux 1-7, thèse IA) | `wiki/topics/manifeste-spark.md` (Spark Vault) | ✅ |
| Architecture technique kit | `wiki/topics/architecture-technique.md` | ✅ |
| Questionnaire onboarding (3 phases) | `wiki/topics/questionnaire-onboarding.md` | ✅ |
| PRD veille (modèle de PRD bien structuré) | `wiki/topics/veille-prd.md` | ✅ (inspirateur de `prd-template.md`) |
| Méta Spark (roadmap, incidents transverses) | [`spark-kit/spark-kit`](https://github.com/spark-kit/spark-kit) | 🟡 |
| Patterns d'intégration réutilisables | `spark-kit/playbooks` (chantier A, futur repo) | 🚫 vide |
| **Gabarits méthodologie** | **ce repo — `spark-kit/templates`** | 🟡 en construction |
| Outillage Claude (MCP n8n, skill NocoDB) | dans `spark-kit/spark-kit` (chantier C) | 🚫 vide |
| Fiches-logiciel et PRD POC d'un client | `spark-kit/<client>/discovery/` | par-site, à instancier |

**Règle** : ne pas dupliquer le contenu des docs wiki ici. Référencer.

---

## Convention de structure par-site

Chaque site Spark a son propre repo dans l'org `spark-kit`. À la racine de ce repo, prévoir :

```
<client>/
├── README.md
├── CLAUDE.md
├── LESSONS-LEARNED.md
├── infra/                # code de déploiement Docker (compose, scripts, config)
└── discovery/
    ├── onboarding/
    │   └── visite-YYYY-MM-DD.md     # rapport de visite, sortie du questionnaire
    ├── fiches/                      # une fiche par logiciel legacy étudié
    │   ├── phone-check.md
    │   ├── google-sheets-erp.md
    │   └── pennylane.md
    └── prds/                        # une PRD par POC envisagé
        ├── prd-001-phone-check-to-noco.md
        └── prd-002-stock-traceability.md
```

Le 1er site Spark déployé en interne sert d'instance de référence de cette convention.

---

## Comment utiliser ce repo

1. **Premier contact client** → utiliser `wiki/topics/questionnaire-onboarding.md` (Spark Vault). Sortie : un rapport de visite client → `<repo-client>/discovery/onboarding/visite-YYYY-MM-DD.md`.
2. **Identification d'un logiciel à brancher** → ouvrir une fiche en suivant [`ingest-legacy-docs.md`](ingest-legacy-docs.md). Sortie : `<repo-client>/discovery/fiches/<soft>.md`.
3. **Cadrage d'un POC** → rédiger un PRD en suivant [`prd-template.md`](prd-template.md). Sortie : `<repo-client>/discovery/prds/prd-NNN-<slug>.md`.
4. **Implémentation** → assembler des briques playbook (chantier A, futur repo `spark-kit/playbooks`). Sortie : workflows n8n + tables NocoDB + écrans + déploiement, qui vivent dans `<repo-client>/infra/` (ou `<repo-client>/workflows/` à créer).

---

*Procédure v1.0 (2026-05-06). À itérer après le 1er POC client réel.*
