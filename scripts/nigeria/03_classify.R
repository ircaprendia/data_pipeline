# aprendIA Nigeria — Step 3: Classify sessions (Nigeria only)
# Runs the rule-based session classifier on the Nigeria slice of the combined
# session_data, then rebuilds the contact-level session_type features and joins them
# onto the Nigeria contacts. Classification is Nigeria-only — the rule classifier is
# English/Hausa keyword-based, so cross-country classification waits for the LLM rebuild.
#
# Classification runs through classify_all_sessions_cached(), which reuses cached labels for
# unchanged sessions and only recomputes changed ones (or everything, if classifier_version
# is bumped). The underlying classify_all_sessions() rules are untouched.
#
# Inputs : data/session_data.csv, data/contacts_data.csv  (combined, from 02_aggregate)
# Outputs: data/nigeria/session_data.csv   (session_data_nigeria, with session_type)
#          data/nigeria/contacts_data.csv  (contacts_data_nigeria, + session_type features)

#### Setup ####
library(tidyverse)

source("functions/session_classification.R")

#### Load combined data ####
# Read explicitly from disk (not in-memory objects): within run_all the per-country dashboards
# overwrite the shared session_data/contacts_data with their own filtered slices, so relying on
# the in-memory objects here would take the wrong country. 02_aggregate writes these files.
session_data  <- read_csv("data/session_data.csv")
contacts_data <- read_csv("data/contacts_data.csv")

#### Take the Nigeria slice ####
# country holds the lowercase cohort_name set in each config ("nigeria", "ecuador", "niger").
session_data_nigeria  <- session_data  %>% filter(country == "nigeria")
contacts_data_nigeria <- contacts_data %>% filter(country == "nigeria")

#### Classify ####
# Cached classifier: only sessions whose six inputs changed (or whose classifier_version was
# bumped) are recomputed; everything else is reused from data/session_classification_cache.csv.
cat("\nClassifying Nigeria sessions...\n")
session_data_nigeria <- classify_all_sessions_cached(session_data_nigeria)

cat("Session type distribution:\n")
print(
  session_data_nigeria %>%
    dplyr::count(session_type) %>%
    arrange(desc(n))
)
cat("\n")

#### Contact-level session_type features ####
# Moved verbatim from the old nigeria/02_aggregate.R:46-68. Summarises the classified
# sessions up to the contact level, then joins onto the Nigeria contacts.
session_type_features <- session_data_nigeria %>%
  group_by(contact_id) %>%
  summarise(
    n_module_sessions        = sum(session_type == "Module progression",    na.rm = TRUE),
    n_question_sessions      = sum(session_type %in% c("Question asking", "Quick question"), na.rm = TRUE),
    n_lesson_sessions        = sum(session_type == "Lesson/Content request", na.rm = TRUE),
    n_onboarding_sessions    = sum(session_type == "User onboarding",        na.rm = TRUE),
    pct_substantive_sessions = mean(session_type %in% c(
      "Module progression", "Question asking", "Quick question",
      "Lesson/Content request", "User onboarding"
    ), na.rm = TRUE),
    n_session_types             = n_distinct(session_type),
    ever_completed_quiz         = as.integer(any(completed_quiz, na.rm = TRUE)),
    pct_sessions_with_reminder  = mean(started_with_reminder == TRUE, na.rm = TRUE),
    n_bot_outreach_sessions     = sum(session_type == "Bot outreach (unanswered)", na.rm = TRUE),
    .groups = "drop"
  )

contacts_data_nigeria <- contacts_data_nigeria %>%
  left_join(session_type_features, by = "contact_id")

#### Save ####
cat("Saving Nigeria classified datasets...\n")
dir.create("data/nigeria", recursive = TRUE, showWarnings = FALSE)
write_csv(session_data_nigeria,  "data/nigeria/session_data.csv")
write_csv(contacts_data_nigeria, "data/nigeria/contacts_data.csv")

#### Summary ####
cat("\n=== Step 3 Summary (Nigeria) ===\n")
cat("Sessions classified:", nrow(session_data_nigeria), "\n")
cat("Contacts:", nrow(contacts_data_nigeria), "\n")
cat("\nSaved:\n")
cat("  - data/nigeria/session_data.csv\n")
cat("  - data/nigeria/contacts_data.csv\n")
