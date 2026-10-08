# Code reference

This is the code dictionary — the companion to the [codebook](codebook.md), which defines every column. [How the pipeline works](pipeline.md) explains the stages and datasets; this walks through the actual files behind them: what each script does when it runs, and what each function is for.

## Scripts, in run order

### Universal (all countries)

**`scripts/00_load_raw_data.R`** — reads `aprendia_message_repository.csv` (the permanent, deduplicated store of every message, all countries, kept outside this repository), strips test-user rows using the gitignored `config/local_identifiers.R`, and sets `raw_message_data` in the environment. Every other script depends on this having run first.

**`scripts/01_clean.R`** — loops over Nigeria, Ecuador, and Niger. For each, it sources that country's config (which isolates the country by its phone numbers), runs `clean_messages()` and the feature-adding functions below, stamps a `country` column, then unions all three into one combined table. Writes `data/clean_message_data.csv`. Ends with a sanity check: no `contact_id` should appear under more than one country, since each is anonymised once across the whole repository.

**`scripts/02_aggregate.R`** — runs once on the combined clean data. Builds session-level and contact-level tables via `create_session_data()` and `create_contacts_data()`. Country-aware throughout: a contact who has used the bot in two countries gets two separate rows, one per country, not one row with activity conflated. Writes `data/session_data.csv`, `data/session_data_long.csv`, `data/contacts_data.csv`. Session classification does **not** happen here — that moved to its own step so it could become Nigeria-specific without complicating the universal pass.

### Nigeria only

**`scripts/nigeria/03_classify.R`** — takes the Nigeria slice of the combined session and contact data, and runs the rule-based classifier (`classify_all_sessions_cached()`) to label each session by type. Rebuilds a set of contact-level counts from those labels (how many module-progression sessions, question sessions, and so on) and joins them onto the Nigeria contacts. Writes `data/nigeria/session_data.csv` and `data/nigeria/contacts_data.csv`.

**`scripts/nigeria/04_cluster.R`** — assigns each Nigeria contact to one of two engagement clusters (Power / Occasional users) via k-means. Before clustering, it caps every contact's cumulative features at the maximum number of weeks any Scale-up contact has had in the programme (`cap_contacts_to_weeks()`), so a longer-standing Pilot contact isn't favoured purely for having had more time to accumulate activity. Clusters the full population, then Pilot and Scale-up separately. If any of the three resolves to more than two clusters, the script stops and asks for the cluster labels in `config/nigeria_config.R` to be reviewed by hand before continuing — it does not guess a label for an unexpected cluster shape. Writes the cluster columns back onto all four Nigeria data files.

**`scripts/nigeria/05_dashboard.R`** — pre-computes everything the Shiny dashboard needs, as seven separate blocks: weekly active users, a survival/persistence model (how long contacts keep coming back), average sessions per active user per week, individual engagement trajectories, activation/churn/reactivation flow counts, a handful of headline scalars (total users, four-week averages), and course-engagement counts (module-1 starts and module-progression sessions by topic). Writes one `.rds` file per block into `data/nigeria/`, so the dashboard itself never has to compute anything at runtime.

### Ecuador and Niger

**`scripts/ecuador/05_dashboard.R`** and **`scripts/niger/05_dashboard.R`** — the same seven-block structure as Nigeria's dashboard script, minus one: there's no course-engagement panel. Clustering itself is a separate, upstream step (`nigeria/04_cluster.R`) that Ecuador and Niger simply never run, not a block removed from the dashboard script — these two scripts add dummy `cluster_label`/`cluster_group_label = "None"` columns to the same six remaining blocks Nigeria has, purely so the shared dashboard functions see the same schema Nigeria produces.

### Orchestrators

**`scripts/run_all.R`** — runs the universal prep once, then Ecuador's dashboard, then Niger's, then Nigeria's classify → cluster → dashboard chain in sequence. The full pipeline, start to finish.

**`scripts/run_nigeria.R`**, **`scripts/run_ecuador.R`**, **`scripts/run_niger.R`** — the universal prep plus one country's steps, for refreshing a single country without re-running the others.

## Functions

### `functions/data_cleaning.R` — turning a raw export into a usable table

- **`clean_messages()`** — the first real transformation. Strips redundant Telerivet columns, filters to real chat messages from the right phone numbers (excluding test users and failed sends), then derives a long list of per-message features: gender flags from the onboarding reply, timezone-corrected timestamps, the teacher's phone country (from the dialling code, not the raw number, which is dropped), emoji and URL counts, and message length split by direction. Returns one row per message, ready for the next stage.
- **`add_selection_indicators()`** — flags messages around course/question selection, based on fixed bot-template strings from an earlier bot generation: `given_options` (the bot presenting its menu), `select_course`/`select_question` (a menu-driven choice), and the three per-course emoji flags. These are the legacy flags described in the [codebook](codebook.md) as retired — kept for backward compatibility with older data, not the current detection method.

### `functions/message_processing.R` — sessions, timing, and (legacy) module signposts

- **`add_message_sequencing()`** — the function that actually creates sessions. Orders each contact's messages by time, and starts a new session whenever the gap since the last message exceeds `session_timeout` (a country config parameter). Also derives message counts per day/week/session and the running message number within a contact's history.
- **`add_group_variable()`** — assigns each contact to a cohort (e.g. "Pilot" or "Scale-up" for Nigeria) based on when their first message fell relative to the cohort start dates in the country config. Everyone gets `"Default"` if no cohort definitions are supplied.
- **`add_module_signposts()`** — the older, regex-based attempt at detecting course and module starts, matching literal titles like "Module 1" plus a course-specific keyword. Superseded by the [event schema](pipeline.md#event-schema) for current analysis; described in the codebook as version-pinned to an earlier bot generation and unreliable for anything after it.
- **`add_implementation_timing()`** — adds `impl_day`/`impl_week`: days and weeks elapsed since the programme's start date (not the contact's own first message — see `message_day`/`message_week` in `add_message_sequencing()` for that).

### `functions/data_aggregation.R` — messages to sessions to contacts

- **`create_session_data()`** — collapses messages into one row per session: start/end time, message counts in and out, the full concatenated transcript (for the classifier to read), and the first few teacher messages specifically (for better question detection). Also computes churn and reactivation: a synthetic "final gap" row is appended per contact so that a contact who goes quiet before the data ends is still counted as having possibly churned, not silently ignored.
- **`create_contacts_data()`** — collapses sessions into one row per contact: totals and averages (messages, sessions, time between messages, emoji use), first-week and first-day behaviour, and the legacy course/module selection counts. Country-aware, so a dual-country contact gets a separate row for each country's activity.

### `functions/session_classification.R` — labelling what kind of session each one was

- **`classify_session()`** — the core rule-based classifier, one session at a time. Works through a fixed priority order (bot outreach with no reply, session continuation, translation request, quick question vs. micro-session, onboarding, module progression, lesson/content request, question asking, prayer/religious request, technical support, and a general-engagement catch-all), returning the first type that matches. Also computes five universal flags on every session regardless of type (started with a reminder, course selected, which course, quiz completed, asked a question) — several of these are documented in the codebook as unreliable and superseded by the event schema; `which_course` in particular has a known bug explained in the code's own comments.
- **`classify_all_sessions()`** — runs `classify_session()` over every row of a session table and reshapes the per-session results (which come back as list columns) into ordinary data-frame columns.
- **`summarise_classification()`** — a reporting helper: session counts and average engagement, broken down by type, and by type-and-engagement-level.
- **`add_content_hash()`** — fingerprints the six inputs that fully determine a session's classification into one hash, so a session whose content hasn't changed can be recognised as unchanged even if it's re-read from disk.
- **`classify_all_sessions_cached()`** — wraps the classifier with a cache keyed on that content hash plus a `classifier_version` string. Only sessions whose inputs (or the classifier version) have changed since the last run are actually reclassified; everything else is read back from `data/session_classification_cache.csv`. Bumping `classifier_version` forces a full recompute — the mechanism for rolling out a corrected rule set, or eventually the LLM classifier, without silently mixing old and new labels.

### `functions/clustering.R` — engagement segments

- **`run_user_clustering()`** — runs k-means on a contacts table, after removing excluded columns (identifiers, legacy flags, previous clustering output) and any column ending `_start`, then standardising the rest. Tries a range of *k* values and returns whichever the fit procedure selects.
- **`summarise_cluster_profiles()`** — a reporting helper: average values of the key engagement features, one row per cluster, for sense-checking that "Power users" and "Occasional users" actually look the way those names imply.
- **`apply_cluster_factor()`** / **`apply_cluster_labels()`** — turn the numeric cluster IDs into ordered, human-readable factor labels ("Power users" / "Occasional users") using the lookup tables in the country config, so charts sort and colour consistently rather than by an arbitrary cluster number.

### `functions/event_detection.R` — the event schema's R-based detectors (retired)

*The event schema is no longer live, and an engagement schema is in development. The three event-schema files below are retained for reference.*

Each `detect_*()` function scans the cleaned messages for one kind of fact and returns rows in the event schema's shape (`contact_id`, `event_type`, `event_date`, `value`, `detection_method`, `confidence`, `source_version_id`, `source_message_id`, `session_id`). Several are marked `"R_prefilter"` rather than a final `"R"` detection method — these are high-recall filters meant to hand candidates to the LLM resolution stage, not final answers on their own.

- **`lookup_lineage_id()`** — internal helper mapping a message's course-name text to a canonical course identifier (`maths`, `reading`, `wellbeing`, `classroom_sel`, `active_inclusive`), using the `course_name_lookup` table above it.
- **`detect_course_selected()`** — the cleanest event in the schema: matches the bot's own verbatim confirmation line ("Great — you've selected \[course]. Let's begin!"), reviewed against every real candidate message.
- **`detect_course_start()`** — a coarser, contact-level "did they ever start this course" signal, built because `course_selected` alone was found to miss the large majority of real course starts. Uses per-course title patterns, each independently checked against real message samples rather than assumed correct.
- **`detect_course_complete_candidates()`** — a high-recall pre-filter for course completions, since the completion message's exact wording isn't specified anywhere in the bot's own scripts and has to be found by reading real examples.
- **`detect_quiz_candidates()`** — a pre-filter distinguishing the bot delivering its own course quiz from the bot generating quiz content *for the teacher's own students* (a related but distinct thing), plus extracting whatever course/module context is available in the message itself.
- **`detect_quiz_question_feedback()`** — flags per-question quiz feedback ("Correct!", "Almost!", and several wrong-answer openers), which is the only place a pass/fail signal exists — there's no single message anywhere that reports a quiz's overall final score.
- **`consolidate_quiz_context()`** — fills in a quiz message's missing course context by carrying forward the last known course earlier in the same session, rather than guessing from the quiz message alone (verified safe because Nigeria contacts don't mix courses within one session).
- **`consolidate_completion_context()`** — the same idea applied to module and course completions: if every course-bearing event in a session agrees on one course, an otherwise-untagged completion in that session is tagged with it.
- **`lookup_module_role()`** — internal helper mapping a module or deep-dive title to its course and its role (core vs. deep dive), using the `module_title_lookup` table above it.
- **`has_linear_next_module_reference()`** — internal helper: a completion message that also names the *next* module number is a core (sequential) module by construction, since deep dives unlock all at once rather than one at a time. Used to correct cases where the title lookup alone would mislabel the role.
- **`detect_module_complete_candidates()`** — a pre-filter for module and deep-dive completions, resolving role from title where possible and from the linear-next-module signal otherwise.
- **`detect_challenge_delivered()`** — flags a genuine Solve-a-Challenge delivery, from the bot's own fixed output-format slot labels ("I hear you:", "Do this now:").
- **`detect_toolkit_content_delivered()`** — flags a Classroom Toolkit delivery (structured `Title:`/`Steps:`/`Notice:` block), and resolves it to `energizer_delivered` or `wellbeing_moment_delivered` specifically when the framing sentence names which branch it is.
- **`detect_onboarding_facts()`** — for each fixed onboarding question, finds the first time a contact was ever asked it, then walks forward through their replies — skipping junk acknowledgments and any reply the bot itself rejected with a retry message — to find the one that actually answers it, rather than naively pairing the question with whatever message comes immediately after.

### `functions/event_llm_resolution.R` — the event schema's LLM resolution tier (retired)

There is no wired-up API call yet, so this file manages a **cache**, not a live model connection: resolution happens by hand (via Claude Code), and these functions handle deciding what's new, merging results in, and turning the cache into event-schema-shaped rows.

- **`build_quiz_cross_session_hint()`** — computes, in R, the last course a contact was known to be doing in an *earlier* session, as a hint for the LLM to weigh (not trust blindly) when a quiz message gives no in-session course context at all.
- **`add_llm_content_hash()`** — fingerprints whichever columns fully determine what the model was actually asked to decide, so a candidate can be recognised as unchanged (or flagged as genuinely different) between runs.
- **`get_llm_resolution_status()`** — splits a batch of candidates into cache hits (already resolved under the current prompt version) and misses (need sending to the LLM this run).
- **`validate_llm_batch()`** — checks that what the LLM returned actually matches what was sent — no dropped or mismatched rows — before anything touches the cache.
- **`update_llm_cache()`** — merges validated results into the job's cache file, replacing only the rows that actually changed.
- **`build_onboarding_llm_event_rows()`**, **`build_quiz_interaction_llm_event_rows()`**, **`build_module_role_llm_event_rows()`**, **`build_toolkit_branch_llm_event_rows()`** — job-specific functions turning each cache's raw resolved columns into proper event-schema rows, ready to combine with the R-detected ones. Not interchangeable: each job's result shape is different enough (a single normalised value vs. three resolved fields vs. a role reclassification) that one generic function would either lose structure or carry a pile of unused columns.

### `functions/event_schema_resolve.R` — one row per fact (retired)

- **`resolve_event_schema()`** — the function behind the clean, analysis-ready `event_schema` table. Where both an R-detected row and an LLM-resolved row exist for the same message, the LLM's version wins (it's later evidence, one level of resolution) — and where the R tier only produced a "there's *something* here but I can't tell which fact" placeholder that the LLM has since sorted into a specific event type, the placeholder is dropped so the same real-world event isn't counted twice. Nothing is deleted from the underlying audit table — this is a downstream, read-only view.

### `functions/dash_visualisations.R` — the dashboard's interactive charts

One `plot_dash_*()` function per dashboard panel, each taking pre-computed aggregate data and returning a ggplot object for the Shiny app to render:

- **`plot_dash_weekly()`** — weekly active users over time, split by cohort and cluster.
- **`plot_dash_persistence()`** — the survival/retention curve (how long contacts keep returning before going quiet).
- **`plot_dash_sessions()`** — average sessions per active user per week.
- **`plot_dash_trajectories()`** — individual engagement trajectories (a "spaghetti plot" of message counts over each contact's own tenure).
- **`plot_dash_course_starts()`** / **`plot_dash_module_time()`** — the course-engagement panel: module-1 starts and module-progression activity by topic, over time.
- **`plot_dash_activation()`** — activation, churn, and reactivation flows.
- **`build_strata_pal()`**, **`col_fill_helper()`**, **`dash_theme()`**, **`add_bar_labels()`**, **`.filter_course_cohort()`** — shared internal helpers for consistent colours, the dashboard's ggplot theme, bar-chart value labels, and cohort filtering, used across several of the plotting functions above rather than repeated in each.

### `functions/visualisations.R` — earlier, static chart versions

**`aprendia_theme()`**, **`plot_weekly_users()`**, **`plot_avg_sessions()`** — an earlier, non-interactive set of chart functions, largely superseded by the `ggiraph`-based interactive versions in `dash_visualisations.R`.

### `functions/dashboard_module.R` — the Shiny app itself

- **`dashboard_ui()`** — builds one country's tab: the sidebar controls (cohort/cluster filters, date range) and the layout of chart cards.
- **`dashboard_server()`** — the reactive logic behind that tab: responds to filter changes and calls the appropriate `plot_dash_*()` function to render each chart.

`app.R` calls both once per country, so the same module code drives all three tabs from each country's own pre-computed data.

## Configuration

`config/{nigeria,ecuador,niger}_config.R` each define that country's cohort start dates, session and churn thresholds, cluster label lookups (Nigeria only), and phone-number parameters, then source the gitignored `config/local_identifiers.R` for the actual bot number and test-user names. Changing an analysis parameter (the churn window, the session-timeout gap) means editing the relevant country's config, not the shared functions above.
