# How the pipeline works

This describes how the pipeline turns a raw WhatsApp chat log into the tables reported on the [dashboard](https://philipblue.shinyapps.io/aprendia-dashboard/). It is the longer companion to the [README](README.md).

## The starting point

The raw export is one row per message: sender, recipient, timestamp, and text. It contains no sessions, user types, or course events — those are all constructed by the pipeline. A "session" is a defined grouping of messages; an engagement type is the output of a clustering step; a course completion is the output of a detector. The pipeline is the route from the chat log to those units.

## The stages

```         
raw chat log   →   clean   →   aggregate   →   classify   →   cluster   →   dashboard
  (outside          (per        (sessions,      (session       (engag.       (per
   the repo)         message)    teachers)       types)         types)        country)
```

- **Clean** removes test users, standardises timestamps to each country's local time, and derives per-message features.
- **Aggregate** groups messages into sessions and rolls sessions up into per-teacher histories.
- **Classify and cluster** (Nigeria only) label each session by type and assign each teacher to an engagement cluster. Ecuador and Niger run the first two stages but not these.
- **Dashboard** reads pre-computed per-country aggregates.

## The datasets

The pipeline writes a small set of tables; the [codebook](codebook.md) defines every column. What each table is, and how it is built:

- **`clean_message_data`** — one row per message, all countries. Timestamps are converted to each country's local time, test users are removed, and per-message features are derived (message length, emoji counts, time since the previous message).
- **`session_data`** — one row per session. Consecutive messages from the same teacher are grouped into a session. A gap of more than 90 minutes starts a new one (the threshold is set in each country's config). Each session records its length, the count of messages in and out, and the in/out interaction ratio.
- **`session_data_long`** — `session_data` extended with churn and reactivation. A teacher is counted as churned once 14 days pass with no message, and as reactivated if they return after churning (both thresholds are config parameters).
- **`contacts_data`** — one row per teacher per country. Each teacher's sessions roll up into totals and averages — number of messages and sessions, average messages per session, average time between messages, interaction ratio, and first-week behaviour. For Nigeria it also carries the engagement cluster, calculated via a k-means clustering algorithm.
- **`event_schema`** — one row per detected fact (course selected, quiz passed, module completed, class size reported at onboarding). Nigeria only, see the event schema below.

The engagement clusters come from k-means on these per-teacher features (Nigeria only). Tenure is capped before clustering, so teachers who have simply been in the programme longer are not favoured by having accumulated more activity.

## Why detection is hard

The bot adapts every message to the teacher and does not reuse module wording in quizzes. The same nominal event — the start of maths module 1, say — is worded differently each time, so fixed-phrase matching is unreliable. Two systems handle this.

### Session classification

Each session is labelled by type: module progression, question, lesson request, translation request, and so on. A rule-based classifier runs for Nigeria, using English and Hausa keyword and keyphrase lists; it is language-bound, which is why Ecuador and Niger are not yet covered. A version built on a large language model (LLM) is in validation; because it reads meaning rather than keywords, it is intended to work across all three languages.

Its status is provisional. A pilot compared the rule classifier and the LLM and found substantial disagreement — which measures disagreement between the two systems, not the accuracy of either. A human-labelled reference set is needed to arbitrate and is the next step; until then the labels are treated as directional.

### Event schema

The event schema is a log of timestamped facts about a teacher: course selected, module completed, quiz passed, class size reported at onboarding. It replaced a wide table of one-off flags that had no audit trail and could not record a teacher correcting an earlier answer.

Each fact records its detection method, a confidence, and the source message; nothing is overwritten. Detection runs in two tiers — a fixed-string tier for the parts of the bot's output that are stable, and an LLM tier for everything else. Each detector is checked two ways before use: precision (are the flagged events real?) and recall (are real events missed?). This is first-pass validation by reading real messages; a formal labelled reference set is the planned next step, and figures are treated as directional until it exists.

## What the event schema supports

Because facts are logged per teacher over time, a teacher's path through a course can be traced end to end — course start, quiz attempt, correct or incorrect answer, module completion, course completion — and compared across courses as a funnel. The same per-teacher facts feed the engagement clustering.

## The code

The pipeline is R:

```         
config/      per-country parameters — timezones, group definitions, clustering settings
functions/   the building blocks — cleaning, session sequencing, aggregation,
             classification, clustering, event detection and resolution, dashboard charts
scripts/     the ordered stages: 00_load → 01_clean → 02_aggregate → {country}/05_dashboard,
             with Nigeria adding nigeria/03_classify → nigeria/04_cluster first.
             run_all.R runs the whole chain; run_{country}.R runs the prep plus one country
app.R        the Shiny dashboard (one tab per country)
```

What each script and function actually does — a plain-English walkthrough, not just the directory-level summary above — is in the [code reference](code_reference.md).

The pipeline cannot be run from this repository. The raw messages are held outside it, under an environment variable, and are never committed. Two local files the pipeline expects are also absent by design: the processed `data/` folder (gitignored), and `config/local_identifiers.R` — a private file naming the test users to remove and the bot's phone number per country, kept out so no real name or number enters a public repository. The code can be read and checked; it has nothing to run on.

## Scope

This is engagement data, not learning data: it records what teachers did, not what they learned. Learning outcomes require the linked survey and classroom-observation data, a separate workstream. The chat log is also silent on why — motivation, connectivity, and school context are not visible in it.
