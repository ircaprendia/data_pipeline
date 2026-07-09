# aprendIA — the data function

aprendIA is a WhatsApp chatbot that trains teachers in Nigeria, Ecuador, and Niger, built by the International Rescue Committee (IRC). A teacher messages the bot; the bot teaches back — short course modules, quizzes, classroom tools, each reply adapted to what that teacher has said about their own classroom. This repository explains the data function behind the product: what the pipeline does, how raw chat logs become evidence, and what the data has shown so far.

aprendIA is built as an open product. This repository is public by design — it is the methods, not the measurements. No data lives here: the messages stay outside the repository, nothing personal is ever committed, and the contact identifiers are opaque platform tokens carrying no name or number. You can read every method and check every decision; you cannot re-run the pipeline, because the data is not here.

## Start here

- **[aprendia.io](https://aprendia.io/)** — the product's own site: what aprendIA is, and how to start using it.
- **[Bot flow reference](bot_flow_reference.md)** — the teacher's journey through the product, in plain language. No data or engineering background needed.
- **[How the pipeline works](pipeline.md)** — how a raw chat log becomes evidence, and why two of the steps are hard.
- **[Live dashboard](https://philipblue.shinyapps.io/aprendia-dashboard/)** — weekly usage and course engagement for each country, and Nigeria's user types.
- **[Codebook](codebook.md)** — the data dictionary: every column, defined.

## The product, in one minute

A teacher's first conversation is a short onboarding: a few questions about their classroom — gender, grade level, class size, what materials they have. Every later reply draws on those answers.

From then on, each visit starts with the same question, "What do you need today?", and three doors. **Learn a skill** opens a course. Courses run in modules: a short introduction, a run of teaching strategies, a quiz, then on to the next module until the course is complete. **Solve a challenge now** takes the problem the teacher describes ("my class of 70 won't settle after break") and returns an action plan to try tomorrow. **Your classroom toolkit** is for the moment itself: an energy shifter for the class, or a wellbeing moment for the teacher.

The bot improvises within this structure. It is instructed to adapt every message to the teacher's own profile and never to repeat wording verbatim — so two teachers on the same module read what looks like two different bots. The [bot flow reference](bot_flow_reference.md) walks the whole journey with examples. What the improvisation means for measurement is covered [below](#how-the-numbers-get-made).

## What the data has shown

Teachers split into two stable types. Power users, about one in five, average 29 sessions and roughly 390 messages. Occasional users average 7 sessions and roughly 70. The split appears in a teacher's first week and persists. What the chat logs cannot tell us is why: motivation, connectivity, and school context are all invisible here.

Sessions belong to teachers, not the bot. Teachers initiate 89% of them. When reminder messages ramped up (week 9 of the pilot onward), bot-started sessions rose to a fifth of the total — and were far more likely to go unanswered.

A high open rate is not engagement. The standard reminder ("Hi again! 👋 Ready to pick up where you left off?") went out 645 times and drew a 7.8% response rate. An emoji prompt drew a near-100% response rate — and short, shallow sessions.

All of this is engagement data, not learning data. It records what teachers did, not what they learned. Learning outcomes need the linked survey and classroom-observation data, a separate workstream.

## How the numbers get made

None of the findings above came free. The raw material is a chat log: one row per message, no sessions, no user types, no course events — none of the units the findings are stated in exist in the export. Each had to be constructed. A "session" is a definition we wrote and defend; a "power user" is the output of a clustering step that was validated before it was believed; a "module start" is a detector that was checked for what it wrongly catches and what it silently misses.

The pipeline reads that chat log and builds upward: messages sequence into sessions, sessions roll up into teachers. For Nigeria, the most mature deployment, each session is then labelled by type and each teacher assigned to an engagement cluster.

The hard problem is that the bot never repeats itself. Its system prompt instructs it to adapt every message to the teacher's own profile, and forbids reusing module wording near-verbatim in quizzes. We pulled 146 messages marking the same nominal event, the start of maths module 1, and every one was worded differently. Keyword-matching therefore fails by design, not by accident. Two classification systems answer it, both built around a large language model (LLM):

- **Session classification** labels each conversation by type: working through a module, asking a question, requesting a translation. A rule-based classifier is live for Nigeria; a multilingual LLM rebuild, now in validation, aims to extend it to Ecuador and Niger.
- **Event schema** is a long log of timestamped facts about a teacher: selected a course, passed a quiz, reported a class size at onboarding. Every fact carries its detection method, its confidence, and the message it came from; nothing is overwritten. Every detector is checked for precision (do its matches mean what we claim?) and recall (what does it miss?) before its output is trusted.

For the fuller account of both systems — the problems they solve, how they work, and where their validation currently stands — see **[How the pipeline works](pipeline.md)**.

## Pipeline at a glance

```
raw chat log  →  clean  →  aggregate  →  classify   →  cluster    →  dashboard
  (outside      (one row   (sessions,    (session      (engagement   (per country)
   the repo)     per msg)   then teachers) types)        types)
```

- **Clean and aggregate run over all three countries** — messages are cleaned and sequenced into sessions, then rolled up per teacher.
- **Classify and cluster are Nigeria-only for now** — the rule classifier is English/Hausa, and only Nigeria has enough users to segment. Ecuador and Niger wait on the multilingual LLM classifier.
- **The dashboard runs per country** and reads pre-computed aggregates, so it stays fast.

Everything the analysis reads comes down to a few tables — one row per message, per session, per teacher, and per detected fact. The [codebook](codebook.md) defines every column.

## The learning cycle

The research runs as a cycle, not a service desk. Questions enter from the product team's live decisions: what to build, what to fix, whom to nudge and when. Findings raise questions of their own — discovering two user types immediately asks whether the split is predictable from week one. Findings become briefing notes, briefing notes become short summaries for the product team, and every answered question sets the next round.

## What's in this repository

**Documentation**
- **[bot_flow_reference.md](bot_flow_reference.md)** — the teacher's full journey through the product, in plain language.
- **[pipeline.md](pipeline.md)** — how the chat log becomes evidence, including the session-classification and event-schema systems, and the repository layout.
- **[codebook.md](codebook.md)** — the data dictionary for every table the analysis produces.

**Code** (the pipeline itself, in R)
- **`config/`** — per-country parameters. **`functions/`** — the pipeline's building blocks. **`scripts/`** — the ordered stages (`00_load` → `01_clean` → `02_aggregate` → classify → cluster → dashboard). **`app.R`** — the Shiny dashboard.
- It reads but does not run without the data, which lives outside the repository (see [How the pipeline works](pipeline.md#the-code-and-how-it-is-wired)).

For the product itself, see [aprendia.io](https://aprendia.io/); for live figures, the [dashboard](https://philipblue.shinyapps.io/aprendia-dashboard/).
