# aprendIA bot version guide

*Drafted 2026-10-08. A reference for telling bot versions apart, dating them, and finding the right file. It is built from the bot's knowledge-base files and describes what those files say. It does not say what is deployed to teachers, because no file does.*

## Read this first

Three cautions apply to everything below.

1. **"Version 3" and "version 4" are labels used in this project, not the product's.** They are two snapshots of the bot's knowledge base, taken on 1 July and 30 September 2026. Separately, two prompt architectures sit side by side in both snapshots: an earlier system prompt and a later one (`system_prompt.2.0`). Neither pair of labels is a release number from the product team.
2. **A commit is not a deployment.** The dates below are when a change reached the knowledge-base repository. The repository starts on 25 June 2026, after several courses were already live, so its history does not cover earlier changes. For the one course where both dates are clean, the message log shows the change reaching teachers 12 days after the commit: Keeping Children Safe was committed on 7 August and first appeared in a course list on 19 August, with regular use from 9 September. No file states which system prompt is live.
3. **The bot does not repeat its own wording.** Its instructions require it to adapt every message, so a version cannot be identified by a stock phrase. Dating a change in the message log needs a structural signal, such as the course list a teacher is shown.

## The two snapshots

| | Snapshot 3 | Snapshot 4 |
|---|---|---|
| Taken | 2026-07-01 | 2026-09-30 |
| Files | 53 | 68 |
| Matches repository state | The commit of 30 June 2026 (all 53 files byte-identical) | The repository at 30 September 2026 |

## Knowledge-base history

Seven commits, all in 2026. File counts include every change in the commit.

| Date | Files | What changed |
|---|---|---|
| 25 Jun | 54 | First commit. The whole file set, which is the base of snapshot 3. |
| 30 Jun | 10 | Summative quiz updates. Active & Inclusive Learning and Math for Every Learner course and module files, two deep dives, the keywords file. **This is snapshot 3.** |
| 30 Jul | 44 | Ecuador added (system prompt and local-context file). Lesson planning added as its own file. Three summative quizzes added (Building Strong Readers, Classroom Management, Teacher Wellbeing). Five course instructions, most deep dives and modules, the pathway-selection agent and `system_prompt.2.0` changed. |
| 7 Aug | 30 | Keeping Children Safe added: course instruction, three modules, summative quiz. A general local-context file added. Wider content updates. `system_prompt.2.0` changed. |
| 27 Aug | 19 | Content updates to deep dives and modules, lesson planning, the chat-history summarisation prompt, the pathway-selection agent and `system_prompt.2.0`. |
| 30 Sep | 5 | Three authoring templates added. The classroom toolkit file and `system_prompt.2.0` changed. |
| 30 Sep | 69 | Files moved to the repository root. Renames only, no content change. |

`system_prompt.2.0` changed in four commits (30 Jul, 7 Aug, 27 Aug, 30 Sep). The earlier system prompt, the onboarding agent file and the Niger prompt did not change at all between the two snapshots.

## What differs between snapshot 3 and snapshot 4

15 files are new and none was removed. Of the 53 shared files, 38 changed and 15 are byte-identical (the operating-system `.DS_Store` file excluded).

**New in snapshot 4**
- A sixth course, Keeping Children Safe, with three modules and a quiz. It is the only course that requires 3 of 3 quiz items correct to pass a module, and it has no deep dives.
- A second country, Ecuador, with its own system prompt and local-context file.
- A dedicated search tool for retrieving course content.
- A chat-history summarisation worker. Its output, a "Context State Summary", is treated by the main prompt as the source of truth for onboarding status each turn.
- A standalone Lesson Planning feature with its own file. The classroom toolkit file now points to it.
- A general local-context file, which the system prompts name as the source of truth for tone and culture.
- Three authoring templates: course instruction, module content and onboarding flow.
- Three summative quiz files that were missing in snapshot 3.

**Changed in `system_prompt.2.0`**
- A new "Mentor Tone" section.
- A "Resuming an Incomplete Course" subsection under progress tracking.
- An explicit rule that a teacher's claim of completion is not enough to pass the final gate. The tracked state must confirm it.
- Quiz mechanics made explicit: each module has a bank of items, one item per type is shown per attempt, and a retake draws a different item.
- The WhatsApp formatting section rewritten to explain stray asterisks.
- A check from snapshot 3 that asked whether an example matched the teacher's grade level, class size and materials no longer appears. The files do not say whether it was removed or moved.

**Unchanged:** the earlier system prompt, the onboarding agent file, the country prompt for Niger, and the Solve a Challenge agent.

## The course catalogue

Courses reached teachers on these dates, taken from the first outgoing messages that name each course. "Regular" means the first day with ten or more such messages. The first five were live before the repository began on 25 June, so their "in the knowledge base" date is only when the repository started.

| Course | In the knowledge base | First seen in a course list, then regular from |
|---|---|---|
| Classroom Management (Healing Classrooms) | 25 Jun | From the start of the data, 2025-08-20 |
| Building Strong Readers | 25 Jun | From the start of the data |
| Math for Every Learner | 25 Jun | From the start of the data |
| Teacher Wellbeing | 25 Jun | 2025-11-14 (one message), then 2026-05-05 |
| Active & Inclusive Learning | 25 Jun | 2026-07-08, then 2026-07-09 |
| Keeping Children Safe | 7 Aug | 2026-08-19 (five messages in two days), then 2026-09-09 |

The older structured courses (units delivered before May 2026) and the newer free-form versions are different generations. The last old Classroom Module 1 introduction is dated 29 April 2026 and the first new one 3 May 2026.

Current structure, from the snapshot-4 specification:

| Course | Required modules | Deep dives |
|---|---|---|
| Math for Every Learner | 2 | 5, unlocked together |
| Building Strong Readers | 2 | 5, unlocked together |
| Classroom Management | 2 | 2 |
| Active & Inclusive Learning | 3, in sequence | 3, unlocked together |
| Teacher Wellbeing | 4, in sequence | none |
| Keeping Children Safe | 3, in sequence | none |

## Dated markers in the message log

These dates were found in the message log and should be checked against it before quoting.

| Marker | Date |
|---|---|
| The post-onboarding offer reads "three short courses" | 2025-08-20 to 2026-04-29 |
| The offer reads "four short courses" | From 2026-05-01 |
| Daily "Hi again" reminder | 2025-10-14 to 2026-04-05 |
| "Welcome back, you were last at…" wording | Last seen 2026-04-29 |
| Newer resume wording | First seen 2026-07-09 |
| "Not a valid option" reply | Absent before May 2026 |

## Questions the files cannot answer

- Which system prompt is deployed to teachers.
- Whether the chat-history worker is live in production, and since when.
- Whether the onboarding agent file is still the operative onboarding spec, or has been replaced by the "deterministic worker" described in the system prompt. The file still says "6 questions" while only 5 are scripted.
- The date each knowledge-base change reached teachers. The product team can supply deployment dates.

## Where to look

| Need | File |
|---|---|
| How a teacher moves through the bot, with real examples | [bot_flow_reference.md](bot_flow_reference.md) |
| How onboarding is read from conversations and turned into data | [onboarding_schema.md](onboarding_schema.md) |
| How a chat log becomes analysis-ready tables | [pipeline.md](pipeline.md) |
| Definitions of every field | [codebook.md](codebook.md) |

## Keeping this guide current

When the knowledge base changes, read its commit history and add each new commit to the history table, with the files it added and changed. Do not add a deployment date until someone on the product team confirms it.
