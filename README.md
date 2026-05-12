# Spark Templates

> Tout ce qu'il faut pour demarrer avec Spark, construire ton premier prototype, et aller plus loin.

Ce repo accompagne [spark-kit](https://github.com/spark-kit/spark-kit) (installation de la stack). Ici : les ressources pour **utiliser** Spark une fois qu'il tourne.

---

## Par ou commencer

```
  Stack installee ?
        │
        ▼
  1. crash-test/          Verifier que tout marche + construire ton premier prototype
        │
        ▼
  2. BIENVENUE.md         Guide pour les utilisateurs de ton equipe
        │
        ▼
  3. Templates            Cadrer un vrai projet (decouverte, PRD, implementation)
        │
        ▼
  4. Playbooks            Briques d'integration reutilisables (a venir)
```

---

## 1. Demarrage

| Ressource | Pour qui | Ce qu'on y trouve |
|-----------|----------|-------------------|
| [**crash-test/**](crash-test/) | Le builder (toi + Claude Code) | Smoke test des 3 routes n8n-NocoDB, puis premier use case guide par `/plan` |
| [**BIENVENUE.md**](BIENVENUE.md) | Les utilisateurs de l'equipe | Ce qu'est Spark, ce qu'ils peuvent utiliser, comment demander un nouvel outil |

Le crash-test est le **premier truc a faire** apres l'installation. Il valide la stack et te fait construire un prototype fonctionnel en une session.

BIENVENUE.md est le document a partager avec ton equipe une fois que le premier outil est pret. Il repond a "c'est quoi ce truc ?" sans jargon technique.

---

## 2. Templates de projet

Quand tu passes du prototype a un vrai projet (decouverte d'une entreprise, branchement d'un logiciel existant, cadrage d'un POC) :

| Template | Role | Quand l'utiliser |
|----------|------|-----------------|
| [**ingest-legacy-docs.md**](ingest-legacy-docs.md) | Documenter un logiciel existant → fiche-logiciel structuree | Tu decouvres un logiciel a brancher |
| [**prd-template.md**](prd-template.md) | Cadrer un POC → PRD avec scope, criteres de succes, plan | Tu sais ce que tu veux construire |
| `poc-from-prd.md` *(a venir)* | Du PRD → assemblage de playbooks → implementation | Le PRD est valide, tu passes au code |

### Flux complet

```
  Questionnaire onboarding (wiki Spark)
         │
         ▼
  Fiches-logiciel (ingest-legacy-docs.md)
         │
         ▼
  PRD du POC (prd-template.md)
         │
         ▼
  Implementation (poc-from-prd.md + playbooks)
         │
         ▼
  Deploye → iteration
```

Les instances de ces templates (fiches d'un logiciel precis, PRD d'un POC precis) vivent dans le repo du site concerne (`<entreprise>/discovery/`), pas ici.

---

## 3. Playbooks *(a venir)*

Briques d'integration reutilisables — chaque playbook est un pattern prouve qu'on assemble pour construire un POC :

- `n8n-nocodb-bridge` — pseudo-API n8n devant NocoDB (operations multi-tables)
- `legacy-api-pull` — polling API legacy → NocoDB
- `legacy-csv-import` — import periodique CSV → NocoDB
- `n8n-webhook-out` — NocoDB row change → API externe

Ces playbooks n'existent pas encore. Ils emergeront des premiers vrais POCs — le crash-test mini-CRM en est le prototype.

---

## Structure d'un site Spark

Chaque entreprise deployee a son propre repo. Convention :

```
<entreprise>/
├── CLAUDE.md                guide agent, adapte a l'entreprise
├── LESSONS-LEARNED.md       ce qui a casse et ce qu'on a appris
├── infra/
│   ├── docker-compose.yml
│   ├── config/              Caddyfile, init-db.sh, nocodb-mcp/
│   ├── apps/                pages HTML servies sur <prefix>-app.<domain>
│   └── scripts/             tunnel, MCP wrappers
└── discovery/
    ├── onboarding/          rapports de visite
    ├── fiches/              une fiche par logiciel legacy etudie
    └── prds/                une PRD par POC envisage
```

---

## Liens

| Ressource | Ou |
|-----------|---|
| Installation de la stack | [spark-kit/spark-kit](https://github.com/spark-kit/spark-kit) |
| Manifeste, architecture, vision | `~/Documents/spark-vault/wiki/` |
| Incidents et lecons transverses | [INCIDENTS.md](https://github.com/spark-kit/spark-kit/blob/main/INCIDENTS.md) |

---

*Spark Templates v1.1 (2026-05-12). Ce repo grandit avec chaque nouveau deploiement.*
