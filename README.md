# aprendIA — data pipeline

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

aprendIA is a WhatsApp chatbot from the International Rescue Committee (IRC) that is a mentor and trainer to teachers in Nigeria, Ecuador and Niger. Teachers send a WhatsApp message to aprendIA. It delivers short course modules, quizzes, and classroom tools, adapting each reply to the teacher's profile. This repository is the data pipeline behind the product: the R code that turns raw chat logs into sessions, per-teacher histories, and course events, and the Shiny dashboard that reports them.

aprendIA is an open product, and this repository is public. It contains methods, not data. No messages or personal data are committed, and contact identifiers are opaque platform tokens. The code can be forked, but the pipeline cannot be run here, because the data is held outside the repository.

## Start here

- 🌐 [**aprendia.io**](https://aprendia.io/) — the product site.
- 💬 [**Bot flow reference**](bot_flow_reference.md) — the teacher's journey through the product, in plain language.
- 🗂️ [**Bot version guide**](bot_version_guide.md) — how the bot's versions differ, and how to date a change.
- ⚙️ [**How the pipeline works**](pipeline.md) — how a chat log becomes analysis-ready tables.
- 🧩 [**Code reference**](code_reference.md) — what each script and function does.
- 📖 [**Codebook**](codebook.md) — the data dictionary.
- 🧪 [**Onboarding schema**](onboarding_schema.md) — how onboarding is read from conversations and turned into data.
- 📊 [**Live dashboard**](https://philipblue.shinyapps.io/aprendia-dashboard/) — the current dashboard (Nigeria): weekly usage, retention and onboarding.
- 🎨 [**Palette guide**](palette_guide.md) — the dashboard's colour system, and the brand palette.

## The product

A teacher's first session is onboarding: a few questions about their classroom (gender, grade level, class size, materials). Later replies draw on those answers. Each subsequent visit offers three options: **Learn a skill** (a course, delivered as modules with quizzes), **Solve a challenge** (an action plan for a problem the teacher describes), and **Classroom toolkit** (a class energiser or a teacher wellbeing moment). The bot adapts every message to the teacher and does not reuse wording, so no two teachers see identical text. The [bot flow reference](bot_flow_reference.md) describes the full journey.

## How it works today

*Status as of 2026-10-08. This repository is meant to show the pipeline as it runs now. Parts that are retired, archived or still in development are marked in the table below.*

The system has two tracks. They read the same raw chat log.

**Track 1: the R pipeline.** It runs on every data refresh. It is deterministic, and it produces the tables the dashboard reads.

```
raw chat log ─► update ─► load ─► clean ─► aggregate ─► classify ─► cluster ─► dashboard
(held outside   repository                (sessions,    (session     (engagement  (Nigeria,
 the repo)                                 teachers)     types)       segments)    deployed)
```

**Track 2: the agentic reading layer.** Fixed text rules cannot reliably read the onboarding of a bot that rewords everything. So language-model agents read each conversation in full, under written, versioned instructions, and fill in a structured record. A person writes the instructions, sets the definitions, checks a sample, and decides what is published.

```
one teacher's messages
          │
 did the detector find an onboarding start?
    yes │                         │ no
        ▼                         ▼
 agent reads that range     agent reads the whole history
 and records each answer    and decides what happened
        └────────────┬────────────┘
                     ▼
 results file ─► checked ─► ledger ─► onboarding tables ─► dashboard, Row 3
                     ▲
  one item in ten is read a second time, independently
```

Every answer carries the teacher's own words and the message it came from, so a reader can check it. Prompts are versioned, and the ledger records which version read what. [The onboarding schema page](onboarding_schema.md) describes the method. An engagement schema, which will do the same for courses, modules and quizzes, is in development.

### What is current, and what is not

| Part | Status | Where |
|---|---|---|
| R pipeline: update, load, clean, aggregate | Current | `scripts/`, `functions/`, `config/` |
| Session classification, rule-based (Nigeria) | Current, provisional. A multilingual version built on a language model is in validation | `scripts/nigeria/03_classify.R` |
| Engagement clusters (Nigeria) | Current | `scripts/nigeria/04_cluster.R` and the cluster assignment scripts |
| Dashboard v2 (Nigeria) | Current, and the live link above | `dashboard_v2/` |
| Onboarding schema (Nigeria) | Current. Partial coverage, because reading proceeds in batches | [onboarding_schema.md](onboarding_schema.md), codebook Level 4 |
| Engagement schema | In development | |
| Dashboard v1 (all three countries) | Archived. Kept for reference and still deployed under a separate name | `app.R`, `scripts/ecuador/`, `scripts/niger/` |
| Event schema | Retired. Code kept for reference | `functions/event_*.R` |
| Module-start flags and other legacy flags | Retired 2026-09-08 | [codebook](codebook.md) |

## What the pipeline produces

The raw export is a chat log — one row per message. The pipeline constructs the units analysis needs:

- **sessions** — messages grouped into conversations;
- **per-teacher histories** — tenure, session counts, activity;
- **session types** (Nigeria) — what kind of conversation each session was;
- **engagement clusters** (Nigeria) — teacher segments by usage, machine learning-driven;
- **onboarding records** (Nigeria) — what each teacher was asked and answered, read by agents. Coverage is partial and the tables are not published.

Course, module and quiz events are not available as a table at present. The engagement schema is intended to provide them.

## The data

The analysis reads a small set of tables — one row per message, per session and per teacher, plus the onboarding schema's two long tables. The [codebook](codebook.md) defines every column. No data files are included; the pipeline reads them from outside the repository.

## Repository layout

- **`config/`** — per-country parameters (timezones, groups, clustering).
- **`functions/`** — the pipeline's building blocks.
- **`scripts/`** — the ordered stages (`update_repository` → `00_load` → `01_clean` → `02_aggregate` → classify → cluster → dashboard), plus the cluster-assignment, deployment and codebook-count scripts.
- **`dashboard_v2/`** — the current Shiny dashboard (Nigeria).
- **`app.R`** — the first Shiny dashboard (all three countries), archived.

What each script and function actually does is in the [code reference](code_reference.md). The code reads but does not run without the data. See [How the pipeline works](pipeline.md#the-code).

## Scope

This is engagement data, not learning data: it records what teachers did, not what they learned. Learning outcomes require the linked survey and classroom-observation data, a separate workstream. Nigeria is the most developed deployment. Classification and clustering are Nigeria-only so far.
