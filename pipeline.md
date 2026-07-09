# How the pipeline works

This is the fuller version of [How the numbers get made](README.md#how-the-numbers-get-made). It explains, without engineering detail, how a raw WhatsApp chat log becomes the figures on the [dashboard](https://philipblue.shinyapps.io/aprendia-dashboard/) — and why two of the steps are harder than they look.

## The starting point is a chat log, nothing more

The raw material is one row per message: who sent it, to whom, when, and the text. That is all. None of the units the findings are stated in — sessions, user types, course events, quiz results — exist in the export. Every one of them is constructed by the pipeline. A "session" is a definition we wrote and defend. A "power user" is the output of a clustering step. A "module completion" is a detector that was checked for what it wrongly catches and what it silently misses. The pipeline is the only route from the chat log to an answer, and it was built from nothing over the life of the project.

## The stages

```
raw chat log  →  clean  →  aggregate  →  classify   →  cluster    →  dashboard
  (outside      (one row   (sessions,    (session      (engagement   (per country)
   the repo)     per msg)   then teachers) types)        types)
```

**Clean** takes the raw export, removes test users, standardises timestamps into each country's local time, and engineers the first features on each message.

**Aggregate** builds upward. Messages that arrive close together become a session; sessions belonging to one teacher roll up into that teacher's whole history — tenure, session counts, course starts. This is where the log stops being a list of messages and becomes a picture of people.

**Classify and cluster** are Nigeria-only for now. Classification labels each session by what kind of conversation it was; clustering sorts teachers into engagement types. Ecuador and Niger have the first two stages but not these — the classifier is still English/Hausa, and the other two countries do not yet have enough users to segment.

**The dashboard** reads pre-computed summaries for each country, so it stays fast and does no heavy work at view time.

## The hard problem: the bot never repeats itself

Most of the difficulty comes from one design choice in the product. The bot is instructed to adapt every message to the teacher's own profile, and it is forbidden from reusing module wording near-verbatim in quizzes. We pulled 146 messages marking the same nominal event — the start of maths module 1 — and every single one was worded differently. So a teacher's progress cannot be read off by matching fixed phrases: keyword-matching fails by design, not by accident. Two systems answer this, and they are the intellectual core of the data function.

### Session classification

Every session is one of a small set of types: working through a module, asking a question, requesting a lesson, asking for a translation. Knowing the mix — and how it shifts — is how we tell genuine learning activity from casual use.

A rule-based classifier is live for Nigeria, built on English and Hausa keyword lists. It works, but it is language-bound, which is why Ecuador (Spanish) and Niger (French) do not yet have it. A rebuild around a large language model (LLM) is in validation; because it reads meaning rather than keywords, it should work in any language and extend classification to all three countries.

We are honest about where this stands. A pilot compared the rule classifier and the LLM on the same 1,121 sessions and found they agreed 55% of the time — but that measures *disagreement between two systems*, not the accuracy of either. Deciding which is right, where they differ, needs a human-labelled reference set. Building that reference set is the next step, and until it exists we treat the labels as directional, not final.

### Event schema

The event schema is a long log of timestamped facts about a teacher: selected a course, started a module, passed a quiz, reported a class size at onboarding. It replaced an earlier wide table of one-off yes/no flags that had no audit trail and no way to record a teacher correcting an earlier answer.

Each fact carries three things: the method that detected it, a confidence, and the exact message it came from. Nothing is ever overwritten — if a later step refines a fact, both versions stay on record. Detection runs in two tiers. A fast first tier catches the parts of the bot's output that genuinely are fixed — menu choices, structural signposts. A second tier, an LLM, handles everything the first cannot, which is most of it, because the bot personalises its replies. A fact only counts once, whichever tier resolved it.

The discipline that makes the schema trustworthy is that **every detector is checked two ways before its output is believed**: precision (of the events it flags, how many are real?) and recall (of the real events, how many does it catch?). A detector that looks clean on one measure can be quietly broken on the other, so both are required. This is first-pass validation done by close reading of real messages; a formal, independently-labelled gold standard is the planned next step, and the figures are directional until it exists.

## What the schema makes possible

With facts logged this way, a teacher's path through a course can be traced end to end: started a course, attempted a quiz, answered it correctly or not, completed a module, completed the course. Laid side by side across courses, that becomes a funnel — where teachers enter, where they progress, and where they drop off. It is also how the two engagement types were found: cluster teachers on how much and how deeply they use the bot, and a stable split appears — roughly one in five are high-intensity users, and it shows in their first week.

## The code, and how it is wired

The pipeline is R. The repository holds the code that does everything described above:

```
config/      per-country parameters — timezones, group definitions, clustering settings
functions/   the building blocks — cleaning, session sequencing, aggregation,
             classification, clustering, event detection and resolution, dashboard charts
scripts/     the ordered stages, run in sequence:
               00_load → 01_clean → 02_aggregate → {country}/05_dashboard
             with Nigeria adding nigeria/03_classify → nigeria/04_cluster first
             run_all.R runs the whole chain; run_{country}.R runs the prep plus one country
app.R        the Shiny dashboard (one tab per country)
```

**You cannot run it here, and that is by design.** The raw messages live outside the
repository, under an environment variable, and are never committed. Two small local files
the pipeline expects are also absent on purpose: the processed `data/` folder (gitignored),
and `config/local_identifiers.R` — a private file naming the test users to strip and the
bot's phone number per country, kept out so no real name or number ever enters a public
repository. Clone this and the scripts will read, review, and check out; they simply have
nothing to run on. The repository is the methods, not the measurements.

## What the data can and cannot say

Everything here is **engagement data, not learning data**. It records what teachers did — how often they came, how far they got, what they asked — not what they learned in their classrooms. Learning outcomes need the linked survey and classroom-observation data, which is a separate workstream. And the chat log is silent on *why*: motivation, connectivity, school context, and workload are all invisible in a stream of messages. Where a finding cannot be supported by the data, we say so, and say what can be supported instead.
