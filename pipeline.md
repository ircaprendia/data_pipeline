# How the pipeline works

This describes how the pipeline turns a raw WhatsApp chat log into the tables reported on the [dashboard](https://philipblue.shinyapps.io/aprendia-dashboard/). It is the longer companion to the [README](README.md).

## The starting point

The raw export is one row per message: sender, recipient, timestamp, and text. It contains no sessions, user types, or course events — those are all constructed by the pipeline. A "session" is a defined grouping of messages; an engagement type is the output of a clustering step; a course completion is the output of a detector. The pipeline is the route from the chat log to those units.

## The stages

```         
raw chat log → update repository → load → clean → aggregate → classify → cluster → dashboard
  (outside        (merge new        (test     (per         (sessions,    (session     (engag.      (Nigeria,
   the repo)       exports)         users      message)     teachers)     types)       segments)    deployed)
                                    removed)
```

- **Update repository** merges each new export into a permanent, deduplicated message store held outside this repository. If a backup location is configured, it also writes an off-machine backup.
- **Load** reads that store and removes test users.
- **Clean** standardises timestamps to each country's local time and derives per-message features.
- **Aggregate** groups messages into sessions and rolls sessions up into per-teacher histories.
- **Classify and cluster** (Nigeria only) label each session by type and assign each teacher to an engagement cluster. Ecuador and Niger run the first stages but not these.
- **Dashboard** reads pre-computed aggregates. The current dashboard (`dashboard_v2/`, Nigeria only) reads one data model built in `scripts/nigeria/05_dashboard.R`. The archived first dashboard (`app.R`) reads per-country aggregates.

Alongside this chain, a second track uses language-model agents to read conversations and produce the onboarding tables. It is described under [Onboarding schema](#onboarding-schema) below. The dashboard's third row is built from it.

## The datasets

The pipeline writes a small set of tables; the [codebook](codebook.md) defines every column. What each table is, and how it is built:

- **`clean_message_data`** — one row per message, all countries. Timestamps are converted to each country's local time, test users are removed, and per-message features are derived (message length, emoji counts, time since the previous message).
- **`session_data`** — one row per session. Consecutive messages from the same teacher are grouped into a session. A gap of more than 90 minutes starts a new one (the threshold is set in each country's config). Each session records its length, the count of messages in and out, and the in/out interaction ratio.
- **`session_data_long`** — `session_data` extended with churn and reactivation. A teacher is counted as churned once 14 days pass with no message, and as reactivated if they return after churning (both thresholds are config parameters).
- **`contacts_data`** — one row per teacher per country. Each teacher's sessions roll up into totals and averages — number of messages and sessions, average messages per session, average time between messages, interaction ratio, and first-week behaviour. For Nigeria it also carries the engagement cluster, calculated via a k-means clustering algorithm.
- **`onboarding_attempts` and `onboarding_answers`** — the onboarding schema's two long tables (Nigeria only), built from the reading agents' results by an analysis-side script and not published. See the onboarding schema below.

The engagement clusters come from k-means on these per-teacher features (Nigeria only). Tenure is capped before clustering, so teachers who have simply been in the programme longer are not favoured by having accumulated more activity.

## Why detection is hard

The bot adapts every message to the teacher and does not reuse module wording in quizzes. The same nominal event — the start of maths module 1, say — is worded differently each time, so fixed-phrase matching is unreliable. Two systems handle this.

### Session classification

Each session is labelled by type: module progression, question, lesson request, translation request, and so on. A rule-based classifier runs for Nigeria, using English and Hausa keyword and keyphrase lists; it is language-bound, which is why Ecuador and Niger are not yet covered. A version built on a large language model (LLM) is in validation; because it reads meaning rather than keywords, it is intended to work across all three languages.

Its status is provisional. A pilot compared the rule classifier and the LLM and found substantial disagreement — which measures disagreement between the two systems, not the accuracy of either. A human-labelled reference set is needed to arbitrate and is the next step; until then the labels are treated as directional.

### Onboarding schema

The onboarding schema has a language model read each conversation in full and fill in a structured record. It records where onboarding started, how far it got, what the teacher answered, and why any answer is missing. It exists because the bot rewords everything, so a fixed text search cannot find every onboarding conversation or read every answer.

Two tasks feed it. In one, the pipeline's start detector has already found an onboarding start, and the agent reads that range. In the other, the detector found nothing, and the agent reads the whole history and decides whether onboarding happened under other wording. Each answer carries the teacher's own words and the message it came from, so a reader can check any record. About one item in ten is read a second time, independently, so that agreement between readers can be measured. Two readers agreeing shows consistency, not correctness.

[The onboarding schema page](onboarding_schema.md) describes the method and the instructions the agents follow. The [codebook](codebook.md), Level 4, defines the tables.

### An earlier event schema, and the engagement schema to come

An earlier event schema logged timestamped facts about a teacher (course selected, module completed, quiz passed). It is no longer live. An engagement schema, covering courses, modules and quizzes, is in development and will take its place. The functions that built the event schema are kept in `functions/` for reference.

## What the onboarding schema supports

Because every answer and every missing reason is recorded with the message it came from, onboarding can be traced and compared by script: how far teachers get, which questions go unanswered and why, and which teachers never onboarded and what they did instead. Coverage is partial, because reading proceeds in batches.

## The code

The pipeline is R:

```         
config/      per-country parameters — timezones, group definitions, clustering settings
functions/   the building blocks — cleaning, session sequencing, aggregation,
             classification, clustering, dashboard charts, and the retired event-schema detectors
scripts/     the ordered stages: update_repository → 00_load → 01_clean → 02_aggregate → {country}/05_dashboard,
             with Nigeria adding nigeria/03_classify → nigeria/04_cluster first.
             run_all.R runs the whole chain; run_{country}.R runs the prep plus one country
dashboard_v2/  the current Shiny dashboard (Nigeria), a self-contained folder that deploys on its own
app.R        the first Shiny dashboard (one tab per country), archived
```

What each script and function actually does — a plain-English walkthrough, not just the directory-level summary above — is in the [code reference](code_reference.md).

The pipeline cannot be run from this repository. The raw messages are held outside it, under an environment variable, and are never committed. Two local files the pipeline expects are also absent by design: the processed `data/` folder (gitignored), and `config/local_identifiers.R` — a private file naming the test users to remove and the bot's phone number per country, kept out so no real name or number enters a public repository. The code can be read and checked; it has nothing to run on.

## Scope

This is engagement data, not learning data: it records what teachers did, not what they learned. Learning outcomes require the linked survey and classroom-observation data, a separate workstream. The chat log is also silent on why — motivation, connectivity, and school context are not visible in it.
