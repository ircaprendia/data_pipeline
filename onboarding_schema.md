# The onboarding schema

*How aprendIA's onboarding is read from conversations and turned into data. This page describes the method and summarises the instructions given to the reading agents. It contains no findings and no data. The full prompt texts are available on request. A data dictionary for the resulting tables is in the [codebook](codebook.md), Level 4.*

## What it is for

Every teacher answers a short set of classroom questions the first time they use aprendIA. The answers (grade level, class size, materials and so on) shape the bot's later replies, so they matter for analysis too. The bot adapts its wording, so a fixed text search cannot find every onboarding conversation or read every answer reliably.

The onboarding schema has a language model read each conversation in full and fill in a structured record. It reads for two things: where onboarding started and how far it got, and what the teacher actually answered.

An engagement schema, which will do the same for courses, modules and quizzes, is in development. It will follow the same pattern.

## Two tasks, two prompts

Each task has its own prompt, versioned separately. Both give the agent the same background: aprendIA is a teacher-training chatbot used in Nigeria, and onboarding is a scripted set of classroom questions.

### Task A: a known episode (prompt version 1.2)

The pipeline's start detector has already found an onboarding start in this contact's history. The agent is told the contact, the episode number, and the message range to read. For an episode with no known end it reads to the end of the history.

**Goal.** The prompt sets the agent's main job as closing out the episode by identifying the real answer to each question. Describing the bot's faults is secondary. The agent is told it has hindsight the bot did not have, so a later message can settle what was unclear at the time. It should not default to "unknown" when the answer is recoverable.

**Which questions.** Onboarding has existed in two forms. The older script asks six questions: gender, students' ages, grade level, main challenge, materials and priority outcome. The newer script asks five: gender, grade level, class size, materials and learner level. The prompt tells the agent to work out which was used from the conversation, because upstream labels are not always right and a hybrid is possible.

**Values.** Closed-set answers are normalised to fixed values, including when the teacher replied with a button number, an emoji-decorated word, a typo or a paraphrase. The original words are kept alongside. Free-text answers are kept as given, lightly cleaned. A non-English answer gets a short English gloss. Grade level also gets a derived age band using the Nigerian school system (nursery, primary, junior secondary, senior secondary, tertiary), or "ambiguous" where the text does not support one.

**What counts as an attempt.** The prompt defines this carefully, because the count feeds the record:
- A clarification round-trip is part of the retry chain and counts.
- An on-topic reply in the wrong format counts. A reply to a different question does not.
- A greeting or resume nudge after a gap does not count.
- A duplicate reply sent twice in a row counts once.
- If a teacher answers a later question early, the answer is recorded against its own field and marked as early.
- If the bot fires an unrelated prompt before the teacher can reply, the agent attributes the next reply only if its content makes the attribution clear. Otherwise the field is left unanswered and both readings are noted.

**Answer or bug, not either.** If the bot rejects a valid answer, the agent still records what the teacher said, and flags the fault separately. If a rejected answer is later replaced by one the bot accepts, the agent weighs both and notes any difference in substance.

**Why an answer is missing.** The agent gives exactly one of seven reasons: not part of this script, asked and never answered, answered but rejected by the bot, skipped by the bot, never reached, the conversation ended first, or the flow was abandoned for another feature.

**Completeness.** The agent judges the episode completed, partial or abandoned. It reports a fraction based on the questions actually asked in that episode, and the furthest question reached.

**Episodes and restarts.** The episode number is reported exactly as given, never inferred. If the conversation contains a full restart, the first complete attempt is the main record and later attempts are noted briefly.

### Task B: no start found (prompt version 1.4)

The detector found no onboarding start for this contact. The agent reads the whole history and first decides whether genuine onboarding happened under any wording.

**Two look-alikes that are not onboarding.** A lesson-plan builder asks about grade, duration and materials for one lesson. A short topic intake asks two or three free-text questions after a teacher names a topic. The agent is told to tell these apart from the classroom-profile questions.

**If onboarding happened,** the agent quotes the opening text it found, which is used to improve the detector, and then records the questions and answers as in Task A.

**If it did not,** the agent assigns one category. They are defined by what happened at the consent step and what the teacher reached:
- consent was affirmed and onboarding was skipped;
- consent was affirmed and nothing further was granted;
- a consent notice was shown and never affirmed, with no access granted;
- no consent was affirmed, yet a course was reached;
- a side feature was used instead of onboarding;
- the teacher received ordinary question-and-answer replies from the start, with no setup step;
- there was too little conversation to tell;
- the onboarding opening line was reused as a menu label.

**Priority order.** A history can show more than one shape, so the agent works down a fixed order and stops at the first that applies. The first test is whether a course was reached without an affirmed consent. For each course access, the agent finds the consent exchange immediately before it and judges that pair. One valid consent covers what follows, and a later replay of the welcome text does not undo it. A "yes" to a generic "ready to begin?" does not count as consent to the disclosure text. "Too few messages" is the last resort and applies only when no other category can be decided.

**Also reported.** The contact's total message count and a rough engagement level (barely used it, moderate ad hoc use, or substantial sustained use).

### Shared instructions

Both prompts ask the agent to note any bot fault in one sentence, to flag anything that looks like a safeguarding concern with the message and a one-line description, and to note any personal information a teacher volunteers. These notes are for tallying and follow-up. They do not change the record.

Both prompts tell the agent how to read the data: with a script, in the foreground, selecting only the columns needed, from the message log in order of message number and never by time. Each agent works in its own scratch folder and changes nothing else. Where several contacts are assigned, each is read afresh and no pattern from an earlier contact is carried over.

## Outputs

Each agent writes a results file with one row per field per episode, or per contact. Results are appended to a ledger that records which episodes and contacts have been read, with the prompt version that read them. They are then rebuilt into two long tables, one row per onboarding attempt and one row per answer. The [codebook](codebook.md) documents the columns and the allowed values.

## How quality is managed

- **Versioned prompts.** Every change that could alter what an agent records bumps the prompt version. The ledger stores the version, so work done under an earlier version can be found and, where needed, repeated.
- **Boundaries come from the detector.** An episode's start and end are copied from the detector's own table, never recomputed from the agent's answers. Recomputing them once caused work to be repeated.
- **Seeded random order.** Work is drawn in a seeded, stratified random order, so any batch is representative of the whole backlog and no batch concentrates one period.
- **Audit sample.** About one in ten items is flagged for a second, independent reading, so that agreement between readers can be measured. Two readers agreeing shows consistency. It does not show correctness.
- **Contacts are re-read if they grow.** A contact with no detected start is read again if their history has grown by 15 or more messages since the last read.
- **Checks before ledger.** Result files are checked for the required columns, for truncation, and for exact agreement between the contacts or episodes assigned and the ones returned.
- **Read-only.** Agents read the message log and write only their own results file. The raw message data is never edited.

## What the schema does not claim

An agent's reading is a judgement made from text. It is not ground truth. Some cases sit between two categories, and different agents can reasonably choose differently. The prompt's conventions exist to reduce this, and the audit sample measures what remains. The schema describes onboarding as it appears in the message log, and says nothing about teachers who never wrote.

## Where the rest lives

The design notes, batch records and validation work live in a separate private repository, because they quote conversations. No message data is published in this repository. The prompt texts, and anything else mentioned here, are available on request.
