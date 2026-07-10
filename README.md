# aprendIA — data pipeline

aprendIA is a WhatsApp chatbot from the International Rescue Committee (IRC) that is a mentor and trainer to teachers in Nigeria, Ecuador and Niger. Teachers send a WhatsApp message to aprendIA. It delivers short course modules, quizzes, and classroom tools, adapting each reply to the teacher's profile. This repository is the data pipeline behind the product: the R code that turns raw chat logs into sessions, per-teacher histories, and course events, and the Shiny dashboard that reports them.

aprendIA is an open product, and this repository is public. It contains methods, not data. No messages or personal data are committed, and contact identifiers are opaque platform tokens. The code can be forked, but the pipeline cannot be run here, because the data is held outside the repository.

## Start here

- 🌐 [**aprendia.io**](https://aprendia.io/) — the product site.
- 💬 [**Bot flow reference**](bot_flow_reference.md) — the teacher's journey through the product, in plain language.
- ⚙️ [**How the pipeline works**](pipeline.md) — how a chat log becomes analysis-ready tables.
- 📖 [**Codebook**](codebook.md) — the data dictionary.
- 📊 [**Live dashboard**](https://philipblue.shinyapps.io/aprendia-dashboard/) — weekly usage and course engagement per country.
- 🎨 [**Palette guide**](palette_guide.md) — the dashboard's colour system.

## The product

A teacher's first session is onboarding: a few questions about their classroom (gender, grade level, class size, materials). Later replies draw on those answers. Each subsequent visit offers three options: **Learn a skill** (a course, delivered as modules with quizzes), **Solve a challenge** (an action plan for a problem the teacher describes), and **Classroom toolkit** (a class energiser or a teacher wellbeing moment). The bot adapts every message to the teacher and does not reuse wording, so no two teachers see identical text. The [bot flow reference](bot_flow_reference.md) describes the full journey.

## What the pipeline produces

The raw export is a chat log — one row per message. The pipeline constructs the units analysis needs:

- **sessions** — messages grouped into conversations;
- **per-teacher histories** — tenure, session counts, course activity
- **session types** (Nigeria) — what kind of conversation each session was
- **engagement clusters** (Nigeria) — teacher segments by usage, machine learning-driven
- **course events** — course starts, quiz interactions, module and course completions

## How it works

The bot does not reuse wording, so fixed-phrase matching is only a part of the solution. Two systems address this:

- **Session classification** labels each conversation by type (module progression, question, translation request, and so on). A rule-based classifier runs for Nigeria (English and Hausa); a multilingual version built on a large language model (LLM) is in validation, intended to cover all three countries.
- **Event schema** is a log of time-stamped facts about a teacher (course selected, quiz passed, class size reported). Detection uses fixed-string matching where the bot's text is stable, and an LLM where it is not. Each detector is checked for precision and recall before its output is used.

[How the pipeline works](pipeline.md) describes both in full.

## Pipeline stages

```         
raw chat log   →   clean   →   aggregate   →   classify   →   cluster   →   dashboard
  (outside)         (per        (sessions,      (session       (engag.       (per
   the repo)         message)    teachers)       types)         types)        country)
```

- **Clean and aggregate** run over all three countries.
- **Classify and cluster** are Nigeria-only for now; Ecuador and Niger await the multilingual classifier.
- **The dashboard** runs per country from pre-computed aggregates.

## The data

The analysis reads a small set of tables — one row per message, per session, per teacher, and per detected fact. The [codebook](codebook.md) defines every column. No data files are included; the pipeline reads them from outside the repository.

## Repository layout

- **`config/`** — per-country parameters (timezones, groups, clustering).
- **`functions/`** — the pipeline's building blocks.
- **`scripts/`** — the ordered stages (`00_load` → `01_clean` → `02_aggregate` → classify → cluster → dashboard).
- **`app.R`** — the Shiny dashboard.

The code reads but does not run without the data. See [How the pipeline works](pipeline.md#the-code).

## Scope

This is engagement data, not learning data: it records what teachers did, not what they learned. Learning outcomes require the linked survey and classroom-observation data, a separate workstream. Nigeria is the most developed deployment. Classification and clustering are Nigeria-only so far.
