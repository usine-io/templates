# Spark Templates

> Tout ce qu'il faut pour demarrer avec Spark, construire ton premier prototype, et aller plus loin.

Ce repo accompagne [spark-kit](https://github.com/spark-kit/spark-kit) (installation de la stack). Ici : les ressources pour **utiliser** Spark une fois qu'il tourne.

Ces ressources vont vous permettre de vous offrir un guide à partager avec le LLM qui vous accompagne dans le code. Cela vous permettra de prototyper dans un cadre plus sécurisé et plus normé. Lorsque des équipes tech récupéreront le projet pour le passer en prod, elles trouveront un ensemble de documents qui les aidera à faire la transition vers le legacy (si cela est nécessaire).

---

## Par ou commencer

```
  Stack installee ?
        │
        ▼
  1. GETTING-STARTED.md   Premier boot d'un repo client : skills Claude, env, credentials n8n
        │
        ▼
  2. crash-test/          Verifier que tout marche + construire ton premier prototype
        │
        ▼
  3. BIENVENUE.md         Guide du builder : comment bosser avec Claude Code + tips & tricks
        │
        ▼
  4. CLAUDE.md            Template du briefing agent a copier dans chaque repo entreprise
        │
        ▼
  5. Templates            Cadrer un vrai projet (decouverte, PRD, implementation)
        │
        ▼
  6. Playbooks            Briques d'integration reutilisables (a venir)
```

---

## 1. Demarrage

| Ressource | Ce qu'on y trouve |
|-----------|-------------------|
| [**GETTING-STARTED.md**](GETTING-STARTED.md) | Premier boot d'un repo client : skills Claude (`/skill nocodb`, `/skill n8n-*`), .env, premier `docker-compose up`, credentials n8n, verifs |
| [**crash-test/**](crash-test/) | Smoke test des 3 routes n8n-NocoDB, puis premier use case guide par `/plan` |
| [**BIENVENUE.md**](BIENVENUE.md) | Guide du builder : ou travailler, comment utiliser Claude Code, tips & tricks, pieges courants |
| [**CLAUDE.md**](CLAUDE.md) | Briefing agent — le fichier que Claude Code lit automatiquement. A copier et adapter dans chaque repo entreprise |

`GETTING-STARTED` est le **premier truc a faire** sur une nouvelle machine ou un nouveau repo client. Suivi du crash-test pour valider que la chaine bout-en-bout marche, puis le builder peut entrer dans le quotidien (BIENVENUE).

BIENVENUE.md est ton guide de reference au quotidien : comment structurer un repo, quand utiliser un formulaire NocoDB vs un endpoint n8n, ou mettre les secrets, comment nommer les workflows.

CLAUDE.md est le template du guide agent. Copie-le dans le repo de chaque entreprise et adapte-le (logiciels connectes, conventions locales, contacts).

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
│   ├── config/              Caddyfile, init-db.sh
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
| Manifeste, architecture, vision | `<spark-vault>/wiki/` |
| Incidents et lecons transverses | [INCIDENTS.md](https://github.com/spark-kit/spark-kit/blob/main/INCIDENTS.md) |

---

*Spark Templates v1.1 (2026-05-12). Ce repo grandit avec chaque nouveau deploiement.*
