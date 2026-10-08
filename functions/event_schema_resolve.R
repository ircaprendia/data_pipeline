# aprendIA — resolve event_schema's two-tier (R_prefilter/LLM) rows into one clean value
# per fact. event_schema_audit.csv itself is never collapsed -- both tiers stay on disk for audit
# (per the provenance discipline in the event schema design note). This is a downstream,
# read-only view for analysis, answering the "should contacts_data prefer LLM over
# R_prefilter" open question in llm_onboarding_enum_schema_v1.md.
#
# Grouping key is (contact_id, event_type, source_message_id), NOT (contact_id, session_id,
# event_type) -- several event types (quiz_interaction, course_start, module_complete) have
# multiple distinct facts per contact per session, each tied to its own message. Grouping on
# session would silently merge separate facts into one row. source_message_id is what an
# LLM row and its originating R_prefilter row actually share -- the LLM resolves THAT
# message's value, it doesn't invent a new one -- so it's the correct join key for "same
# underlying fact, two tiers", not session position.

library(tidyverse)

# Event types where a completed LLM job means "no LLM row" = the reply was judged
# unresolvable junk, not "not yet processed". For these, a surviving R_prefilter-only row
# resolves to NA in the output rather than the raw text. Every other event type either has
# no job yet (the raw text is the only thing that exists) or the R_prefilter tier is already
# the final answer by design (course/quiz/module detectors), so their R_prefilter value
# stands as final when no LLM row exists.
ONBOARDING_FIELDS_WITH_COMPLETED_JOB <- c(
  "gender_reported", "materials_tier_reported", "learner_level_reported",
  "grade_level_reported", "student_ages_reported", "class_size_reported"
)

# Event types where the LLM job's job is to RECLASSIFY the event_type itself, not just
# resolve a value within the same type -- module_or_deepdive_complete -> module_complete /
# deep_dive_complete; toolkit_content_delivered -> energizer_delivered /
# wellbeing_moment_delivered; quiz_interaction -> quiz_content_generated (the
# classroom_resource subset the R-tier regex missed). Grouping naively by event_type would
# put the stale R_prefilter placeholder row and its LLM reclassification in DIFFERENT
# groups (different event_type strings), so both would survive -- confirmed as a real bug
# 2026-07-04, 1,615 messages producing two "true" rows instead of one. A message with any
# LLM row is used as the signal that a placeholder-typed R_prefilter row at that SAME
# message has been reclassified -- there is no other reason an LLM row would exist for a
# message whose R_prefilter type is one of these placeholders.
RECLASSIFICATION_PLACEHOLDER_TYPES <- c(
  "module_or_deepdive_complete", "toolkit_content_delivered", "quiz_interaction"
)

# Arguments:
#   event_schema: the full two-tier table (data/nigeria/event_schema_audit.csv)
#   null_if_unresolved: event_types where a surviving R_prefilter-only row means "judged
#     junk, resolve to NA" rather than "keep the raw text" -- defaults to the six onboarding
#     fields with a completed LLM job.
# Returns: one row per genuine fact -- LLM value (and, where relevant, LLM-reclassified
#   event_type) where one exists, R_prefilter value/event_type otherwise (or NA, for the
#   fields above). A message can still legitimately produce more than one surviving row
#   when it carries genuinely distinct facts (eg quiz_question_feedback + quiz_interaction
#   from the same message) -- only rows whose event_type is a known reclassification
#   placeholder, or whose event_type exactly matches an LLM row at the same message, are
#   ever dropped. Rows with no source_message_id (onboarding questions asked but never
#   answered) pass through unchanged -- they can never have an LLM counterpart, since there
#   was no message to send.
resolve_event_schema <- function(event_schema,
                                  null_if_unresolved = ONBOARDING_FIELDS_WITH_COMPLETED_JOB) {

  no_message <- event_schema %>% filter(is.na(source_message_id))

  resolved <- event_schema %>%
    filter(!is.na(source_message_id)) %>%
    group_by(contact_id, source_message_id) %>%
    group_modify(function(d, ...) {
      llm_types <- d$event_type[d$detection_method == "LLM"]
      if (length(llm_types) == 0) return(d)
      superseded <- d$detection_method == "R_prefilter" &
        (d$event_type %in% llm_types | d$event_type %in% RECLASSIFICATION_PLACEHOLDER_TYPES)
      d[!superseded, ]
    }) %>%
    ungroup() %>%
    mutate(
      value = if_else(
        event_type %in% null_if_unresolved & detection_method != "LLM",
        NA_character_,
        value
      )
    )

  bind_rows(resolved, no_message) %>%
    arrange(contact_id, event_date)
}
