# event_schema LLM resolution -- content-addressed cache for the LLM-resolved tier.
#
# Mirrors classify_all_sessions_cached() in functions/session_classification.R: a row is a
# cache hit only when its key AND content_hash AND prompt_version all match a cached entry.
# Bumping prompt_version invalidates every row classified under the old version, the same
# lever classifier_version is for session reclassification.
#
# One real difference from the session classifier: there is no wired-up API call yet, so
# resolution happens by batching cache misses to an LLM by hand (currently via Claude Code's
# Agent tool). This file's job is the diffing -- what's new or changed since the last run --
# and merging results back in. The functions below are meant to be called in sequence, once
# per LLM job (onboarding enum resolution, quiz_interaction resolution, etc. -- each job is
# its own versioned schema/prompt doc in research/, see llm_event_resolution_batching.md for
# how multiple jobs' misses can be combined into a single physical agent call while staying
# independently versioned and cached):
#   1. get_llm_resolution_status()  -- split candidates into hits / misses
#   2. (send misses$... to the LLM, however that happens this run)
#   3. validate_llm_batch()         -- confirm what came back matches what was sent
#   4. update_llm_cache()           -- merge the LLM's results into the cache file
#   5. build_*_llm_event_rows()     -- job-specific: materialize event_schema rows ready to
#      bind_rows() alongside the R_prefilter rows already in event_schema_audit.csv. This step is
#      NOT generic across jobs -- each job's result columns map to event_schema's
#      (value, event_type, ...) shape differently (see build_onboarding_llm_event_rows()
#      below for the pattern; a quiz_interaction equivalent gets written when that job runs).
#
# The LLM's output format stays JSON, not an edited copy of the sent CSV: an agent hand-
# writing CSV text has to manually quote embedded commas/quotes in free-text `rationale`
# values, and a mis-quoted row shifts every column after it silently. JSON string escaping
# is something LLMs handle natively; validate_llm_batch() closes JSON's actual weak point
# (a dropped/altered row) with a loud check instead.
#
# GENERALIZED 2026-07-02 while designing the quiz_interaction job: the first draft of this
# file (built for the onboarding job alone) hardcoded `raw_value` as both the content-hash
# input and part of validate_llm_batch()'s identity key. That doesn't generalize -- quiz
# candidates have no `raw_value` field at all (they have `message` + `prior_context`), and
# it turned out to be a latent bug even for onboarding: that job's own prompt contract never
# echoes `raw_value` back, so validate_llm_batch() would have errored on a missing column
# the first time it ran against real output, not just synthetic test data. Fixed by keying
# validation on `source_message_id` alone (globally unique per message, already required in
# every job's output contract) and making content_cols an explicit per-job argument instead
# of a hardcoded assumption.

library(tidyverse)

# Cross-session course-history hint for quiz_interaction candidates (added 2026-07-02).
# Widening prior_context from 3 to 6 messages (v1.1) found a structural ceiling: course
# display names essentially never appear near an arbitrary mid-quiz message -- they're
# stated once, at course selection or module completion, often many turns or entire
# sessions earlier. No context window size fixes that; the fix is computing the answer in
# R (which already has the full event history) and giving it to the model as a hint to
# confirm or override, not asking the model to rediscover text that isn't nearby.
#
# Checked before building: `course_selected` alone (the strict "you've selected X" regex)
# only covers 1.6% of the still-unresolved quiz_interaction pool (28/1794), because most
# contacts with quiz activity never trigger that specific phrasing. Extending to also carry
# forward `module_complete`/`deep_dive_complete` titles (resolved to lineage_id the same way
# course_name_lookup/module_title_lookup already do) covers 16.4% (294/1794) -- worth
# building. This is CROSS-session, unlike consolidate_quiz_context()'s within-session
# forward-fill: a contact could genuinely switch courses between sessions (unlike within a
# session, where every checked case showed no interleaving), so this is a weaker signal,
# passed as a hint for the model to weigh, not a resolved fact the way in-session
# forward-fill is.
build_quiz_cross_session_hint <- function(quiz_candidates, clean_message_data, event_schema) {
  titles_maths <- c("Exploring Math Domains", "Math for Every Learner", "Shifting Math Mindsets",
                     "Math Process Skills", "Making Math Hands-On", "Inclusive Math Instruction",
                     "Assessment for Math Learning")
  titles_reading <- c("How We Learn to Read", "Making Reading Engaging",
                       "The Building Blocks of Word Reading", "Making Meaning with Vocabulary",
                       "Creating Joyful and Healing Reading Experiences", "Supporting All Learners",
                       "Texts")
  titles_classroom <- c("Creating Safety and Predictability", "Building Belonging",
                         "Relationships", "Engagement, Inclusion")
  titles_wellbeing <- c("Understanding Teacher Wellbeing", "Building Resilience",
                         "Building Positive Relationships", "Creating a Wellbeing Plan")
  titles_active <- c("The Three Elements of Active Learning", "Active Learning in Action",
                      "Active Learning for Every Child", "Hands-On Learning with Low-Cost Materials",
                      "Drama, Role Play", "Planning an Active Lesson")

  lineage_from_title <- function(v) {
    case_when(
      is.na(v) ~ NA_character_,
      str_detect(v, regex(paste(titles_maths, collapse = "|"), ignore_case = TRUE)) ~ "maths",
      str_detect(v, regex(paste(titles_reading, collapse = "|"), ignore_case = TRUE)) ~ "reading",
      str_detect(v, regex(paste(titles_classroom, collapse = "|"), ignore_case = TRUE)) ~ "classroom_sel",
      str_detect(v, regex(paste(titles_wellbeing, collapse = "|"), ignore_case = TRUE)) ~ "wellbeing",
      str_detect(v, regex(paste(titles_active, collapse = "|"), ignore_case = TRUE)) ~ "active_inclusive",
      TRUE ~ NA_character_
    )
  }

  history <- bind_rows(
    event_schema %>% filter(event_type == "course_selected") %>%
      transmute(contact_id, event_date, course = value),
    event_schema %>% filter(event_type %in% c("module_complete", "deep_dive_complete")) %>%
      transmute(contact_id, event_date, course = lineage_from_title(value))
  ) %>% filter(!is.na(course))

  # Compute the hint on a candidates-with-valid-prior-history subset, then LEFT JOIN it back
  # onto the full candidate set by .row -- this is what actually preserves every input row.
  # An earlier version filtered before joining back, which silently dropped any candidate
  # whose contact had SOME course history but none of it prior to the quiz date (the filter
  # emptied that .row's group entirely, so slice_max had nothing to return and the row
  # vanished from the output instead of correctly getting hint = NA). Caught by comparing
  # input/output row counts before trusting this in a real run -- 1794 in, 1592 out.
  candidates_with_row_id <- quiz_candidates %>% mutate(.row = row_number())

  hints <- candidates_with_row_id %>%
    select(.row, contact_id, event_date) %>%
    inner_join(history, by = "contact_id", relationship = "many-to-many") %>%
    filter(event_date.y < event_date.x) %>%
    group_by(.row) %>%
    slice_max(event_date.y, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(.row, cross_session_course_hint = course)

  candidates_with_row_id %>%
    left_join(hints, by = ".row") %>%
    select(-.row)
}

# Each job defines its own cache column spec -- result shapes genuinely differ (onboarding
# resolves to one `normalized_value`; quiz_interaction resolves to three fields), so forcing
# one shared schema would either lose structure or paper over the difference with unused
# columns. `contact_id`, `session_id`, `event_type`, `content_hash`, `prompt_version`,
# `source_message_id`, `event_date`, `classified_at` are the common spine every job needs;
# add the job's own result columns alongside them.
onboarding_llm_cache_col_types <- cols(
  contact_id = col_character(),
  session_id = col_double(),
  event_type = col_character(),
  content_hash = col_character(),
  prompt_version = col_character(),
  normalized_value = col_character(),
  confidence = col_double(),
  rationale = col_character(),
  source_message_id = col_character(),
  event_date = col_character(),
  classified_at = col_character()
)

quiz_interaction_llm_cache_col_types <- cols(
  contact_id = col_character(),
  session_id = col_double(),
  event_type = col_character(),
  content_hash = col_character(),
  prompt_version = col_character(),
  interaction_type = col_character(),
  resolved_course = col_character(),
  resolved_module_number = col_double(),
  confidence = col_double(),
  rationale = col_character(),
  source_message_id = col_character(),
  event_date = col_character(),
  classified_at = col_character()
)

module_role_llm_cache_col_types <- cols(
  contact_id = col_character(),
  session_id = col_double(),
  event_type = col_character(),
  content_hash = col_character(),
  prompt_version = col_character(),
  resolved_role = col_character(),
  resolved_generation = col_character(),
  is_duplicate_or_summary = col_logical(),
  confidence = col_double(),
  rationale = col_character(),
  source_message_id = col_character(),
  event_date = col_character(),
  classified_at = col_character()
)

toolkit_branch_llm_cache_col_types <- cols(
  contact_id = col_character(),
  session_id = col_double(),
  event_type = col_character(),
  content_hash = col_character(),
  prompt_version = col_character(),
  resolved_branch = col_character(),
  confidence = col_double(),
  rationale = col_character(),
  source_message_id = col_character(),
  event_date = col_character(),
  classified_at = col_character()
)

# Fingerprint the LLM input. content_cols names whichever columns fully determine what the
# model was actually asked to decide -- onboarding: event_type + raw_value; quiz_interaction
# will be event_type + message (prior_context is informational, not part of the candidate's
# own identity, since it's derived from session data that doesn't change between runs for a
# given message).
add_llm_content_hash <- function(candidates_df, content_cols) {
  content_df <- candidates_df %>% select(all_of(content_cols))
  candidates_df %>%
    mutate(content_hash = pmap_chr(content_df, function(...) rlang::hash(paste(..., sep = "||"))))
}

# Split candidates into cache hits (already resolved, reusable) and misses (need sending to
# the LLM this run). candidates_df must contain contact_id, session_id, event_type,
# source_message_id, plus whatever content_cols names for this job.
get_llm_resolution_status <- function(candidates_df,
                                       cache_path,
                                       prompt_version,
                                       content_cols,
                                       col_types) {

  key_cols <- c("contact_id", "session_id", "event_type")
  candidates_df <- candidates_df %>% add_llm_content_hash(content_cols)

  valid_cache <- NULL
  if (file.exists(cache_path)) {
    cache <- read_csv(cache_path, col_types = col_types)
    valid_cache <- cache %>%
      filter(prompt_version == !!prompt_version) %>%
      # DEFENSIVE DEDUP, added 2026-07-03: a genuinely repeated identical message within
      # one contact+session (eg a bot retry resending the same quiz question verbatim)
      # produces two candidate rows sharing the same (key_cols, content_hash) -- and if
      # both were ever sent through and cached separately, two cache rows share that same
      # combination too. Without deduping here, the join below many-to-many-explodes and
      # errors (caught 2026-07-03 running quiz_interaction's miss count: 4 pre-existing
      # duplicate combos in the cache, 11 in the fresh candidate pool). Keeping the first
      # is correct, not arbitrary: identical content_hash means the LLM's resolution would
      # be identical regardless of which copy was sent.
      distinct(across(all_of(c(key_cols, "content_hash"))), .keep_all = TRUE)
  }

  if (!is.null(valid_cache) && nrow(valid_cache) > 0) {
    is_hit <- candidates_df %>%
      select(all_of(c(key_cols, "content_hash"))) %>%
      left_join(
        valid_cache %>%
          select(all_of(c(key_cols, "content_hash"))) %>%
          mutate(.is_hit = TRUE),
        by = c(key_cols, "content_hash")
      ) %>%
      pull(.is_hit)
    is_hit <- !is.na(is_hit)
  } else {
    is_hit <- rep(FALSE, nrow(candidates_df))
  }

  hits <- candidates_df %>% filter(is_hit)
  misses <- candidates_df %>% filter(!is_hit)

  # Guard the join: when there are no hits, valid_cache may be NULL (no cache file yet), and
  # left_join() with a NULL y errors regardless of hits' row count.
  if (nrow(hits) > 0) {
    hits <- hits %>%
      select(all_of(c(key_cols, "content_hash"))) %>%
      left_join(valid_cache, by = c(key_cols, "content_hash"))
  }

  cat(sprintf(
    "LLM resolution cache: %d hit(s), %d miss(es) [prompt_version %s]\n",
    nrow(hits), nrow(misses), prompt_version
  ))

  list(hits = hits, misses = misses)
}

# Verify a batch of returned LLM results actually matches what was sent, before anything
# gets near the cache. Catches a dropped, duplicated, or malformed row -- the failure mode
# seen in practice (2026-07-02: an agent dropped source_message_id from its JSON output on
# one batch) -- as a loud error here rather than a silent corruption once merged.
#
# Keyed on source_message_id alone, not a job-specific composite key: it's globally unique
# per message and already required in every job's output contract, so it generalizes across
# jobs without needing the LLM to echo back potentially large content (a raw onboarding
# reply, a full quiz message) just to prove row correspondence.
validate_llm_batch <- function(sent, returned, id_col = "source_message_id") {
  stopifnot(id_col %in% names(sent), id_col %in% names(returned))

  if (nrow(sent) != nrow(returned)) {
    stop(sprintf(
      "LLM batch mismatch: sent %d rows, got %d rows back.",
      nrow(sent), nrow(returned)
    ))
  }

  sent_ids <- sort(sent[[id_col]])
  returned_ids <- sort(returned[[id_col]])

  if (!identical(sent_ids, returned_ids)) {
    stop(sprintf(
      "LLM batch mismatch: returned rows do not match the sent %s values -- a row was ",
      id_col
    ), "dropped, duplicated, or altered. Inspect the batch before merging into the cache.")
  }

  invisible(TRUE)
}

# Merge a batch of returned LLM results into the cache file. Call validate_llm_batch() first.
# new_results needs every column col_types expects except prompt_version/classified_at,
# which this function stamps. Call once per batch as results come back.
update_llm_cache <- function(new_results,
                              cache_path,
                              prompt_version,
                              col_types) {

  key_cols <- c("contact_id", "session_id", "event_type")

  new_entries <- new_results %>%
    mutate(
      prompt_version = prompt_version,
      classified_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    ) %>%
    select(all_of(names(col_types$cols))) %>%
    # Same defensive dedup as get_llm_resolution_status() -- if a batch happens to include
    # two genuinely-identical-content candidates (same key_cols + content_hash, eg a
    # repeated verbatim message within a session), keep only the first result rather than
    # writing two cache rows sharing a key+hash combination, which is exactly what breaks
    # the read-side join later.
    distinct(across(all_of(c("contact_id", "session_id", "event_type", "content_hash"))), .keep_all = TRUE)

  if (file.exists(cache_path)) {
    cache <- read_csv(cache_path, col_types = col_types)
    # CRITICAL FIX 2026-07-03: this anti_join used to key on key_cols ALONE, not
    # key_cols + content_hash. That's wrong whenever more than one distinct item can
    # legitimately share (contact_id, session_id, event_type) -- eg a session with many
    # quiz_interaction turns, each a different message/content_hash. Every incremental
    # update_llm_cache() call was silently deleting every OTHER cached resolution for that
    # same session, not just replacing the one row actually being updated. Confirmed via
    # arithmetic on real runs: quiz_interaction's cache went from 1790 rows, +1188 new
    # resolutions, to only 2461 (expected ~2978, ~517 pre-existing rows silently destroyed)
    # -- and again from 2461 +508 to only 2475 (expected ~2969, ~494 more destroyed). Onboarding
    # and module_role were unaffected by this same bug only because their key_cols happen to
    # be unique per real candidate in practice (each onboarding question asked at most once
    # per contact) -- not because the bug didn't exist for them too.
    retained <- cache %>% anti_join(new_entries %>% select(all_of(c(key_cols, "content_hash"))), by = c(key_cols, "content_hash"))
    updated_cache <- bind_rows(retained, new_entries)
  } else {
    updated_cache <- new_entries
  }

  dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
  write_csv(updated_cache, cache_path)
  cat(sprintf("LLM cache updated: %d total entries\n", nrow(updated_cache)))
  invisible(updated_cache)
}

# Materialize LLM-resolved event_schema rows from the ONBOARDING cache, ready to bind_rows()
# alongside the existing R_prefilter rows in event_schema_audit.csv. Per
# llm_onboarding_enum_schema_v1.md, a null normalized_value is a signal for human review, not
# a fact -- excluded here, not written to event_schema. source_version_id is always NA: no
# course-version concept applies to onboarding facts.
#
# Job-specific, not generic: quiz_interaction's result shape (interaction_type +
# resolved_course + resolved_module_number, sometimes reclassifying the event_type itself)
# doesn't map onto event_schema the same way a single normalized_value does. Write a
# build_quiz_interaction_llm_event_rows() alongside this one when that job actually runs,
# rather than forcing both through one falsely-generic function.
build_onboarding_llm_event_rows <- function(cache_path = "data/nigeria/event_llm_cache_onboarding.csv",
                                             prompt_version) {
  cache <- read_csv(cache_path, col_types = onboarding_llm_cache_col_types) %>%
    filter(prompt_version == !!prompt_version, !is.na(normalized_value))

  cache %>%
    transmute(
      contact_id,
      event_type,
      event_date,
      value = normalized_value,
      detection_method = "LLM",
      confidence,
      source_version_id = NA_character_,
      source_message_id,
      session_id
    )
}

# Materialize LLM-resolved event_schema rows from the QUIZ_INTERACTION cache. Per
# llm_quiz_interaction_schema_v1.md:
# - interaction_type = "genuine_quiz": a quiz_interaction row, value = resolved_course (or
#   resolved_module_number if course stayed null but module resolved), source_version_id set
#   from resolved_course the same way the R detectors do.
# - interaction_type = "classroom_resource": reclassifies the event TYPE itself to
#   quiz_content_generated (a regex-split miss caught by this job), value always NA -- same
#   convention as the R-detected rows of that type.
# - interaction_type = "not_a_quiz": no row at all -- flagged for review, not written.
build_quiz_interaction_llm_event_rows <- function(cache_path = "data/nigeria/event_llm_cache_quiz_interaction.csv",
                                                   prompt_version) {
  cache <- read_csv(cache_path, col_types = quiz_interaction_llm_cache_col_types) %>%
    filter(prompt_version == !!prompt_version, interaction_type != "not_a_quiz")

  cache %>%
    transmute(
      contact_id,
      event_type = if_else(interaction_type == "genuine_quiz", "quiz_interaction", "quiz_content_generated"),
      event_date,
      value = if_else(
        interaction_type == "genuine_quiz",
        coalesce(resolved_course, as.character(resolved_module_number)),
        NA_character_
      ),
      detection_method = "LLM",
      confidence,
      source_version_id = if_else(
        interaction_type == "genuine_quiz" & !is.na(resolved_course),
        paste0(resolved_course, "_v2_current"),
        NA_character_
      ),
      source_message_id,
      session_id
    )
}

# Materialize LLM-resolved event_schema rows from the MODULE_ROLE cache. Per
# llm_module_role_schema_v1.md: resolved_role determines event_type (module_complete /
# deep_dive_complete); is_duplicate_or_summary = TRUE or resolved_role = NA both produce no
# row. `value` (the module title or number) isn't part of this job's OWN output -- the LLM
# resolves role, not re-extracts what R already found -- so this function joins back to the
# original module_or_deepdive_complete R_prefilter rows in event_schema to reuse their
# already-extracted `value`, rather than asking the LLM to redundantly echo it.
build_module_role_llm_event_rows <- function(cache_path = "data/nigeria/event_llm_cache_module_role.csv",
                                              prompt_version,
                                              event_schema) {
  cache <- read_csv(cache_path, col_types = module_role_llm_cache_col_types) %>%
    filter(prompt_version == !!prompt_version, !is_duplicate_or_summary, !is.na(resolved_role))

  # Reuse the original R_prefilter row's value AND its source_version_id -- the latter is
  # course context the R tier backfilled from session position (consolidate_completion_context(),
  # 2026-07-09). This job resolves only role (core vs deep dive), not course, so hardcoding
  # source_version_id = NA here would silently discard the course tag on every row it
  # reclassifies. Carry it through instead; it stays NA only where the R tier couldn't
  # recover the course either.
  original_values <- event_schema %>%
    filter(event_type == "module_or_deepdive_complete") %>%
    select(source_message_id, original_value = value, original_version = source_version_id)

  cache %>%
    left_join(original_values, by = "source_message_id") %>%
    transmute(
      contact_id,
      event_type = if_else(resolved_role == "core", "module_complete", "deep_dive_complete"),
      event_date,
      value = original_value,
      detection_method = "LLM",
      confidence,
      source_version_id = original_version,
      source_message_id,
      session_id
    )
}

# Materialize LLM-resolved event_schema rows from the TOOLKIT_BRANCH cache. Per
# llm_toolkit_branch_schema_v1.md: resolved_branch determines event_type
# (energizer_delivered / wellbeing_moment_delivered); `null` produces no row. `value` (the
# extracted content title) isn't part of this job's own output either -- same reasoning as
# module_role above -- so this joins back to the original toolkit_content_delivered
# R_prefilter rows to reuse their already-extracted title.
build_toolkit_branch_llm_event_rows <- function(cache_path = "data/nigeria/event_llm_cache_toolkit_branch.csv",
                                                 prompt_version,
                                                 event_schema) {
  cache <- read_csv(cache_path, col_types = toolkit_branch_llm_cache_col_types) %>%
    filter(prompt_version == !!prompt_version, !is.na(resolved_branch))

  original_values <- event_schema %>%
    filter(event_type == "toolkit_content_delivered") %>%
    select(source_message_id, original_value = value)

  cache %>%
    left_join(original_values, by = "source_message_id") %>%
    transmute(
      contact_id,
      event_type = if_else(resolved_branch == "energizer", "energizer_delivered", "wellbeing_moment_delivered"),
      event_date,
      value = original_value,
      detection_method = "LLM",
      confidence,
      source_version_id = NA_character_,
      source_message_id,
      session_id
    )
}
