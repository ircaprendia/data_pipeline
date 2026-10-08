# Configuration for Nigeria Pilot cohort

# Cohort identification
cohort_name <- "nigeria"
start_date <- ymd("2024-08-15")
end_date <- ymd("2026-01-14")  # Day before scaleup starts

# Group definitions (for within-country grouping like Pilot vs Scale-up)
# If you don't want groups, set group_definitions <- NULL and everyone gets "Default"
cohort_pilot_start <- ymd_hms("2025-08-15 14:41:46", tz = "Africa/Lagos")
cohort_scaleup_start <- cohort_pilot_start + weeks(21)  # Scale-up started in week 22

group_definitions <- list(
  list(name = "Scale-up", start = cohort_scaleup_start),
  list(name = "Pilot", start = cohort_pilot_start)
)

# Analysis parameters
latest_week <- 29  # Adjust when new data is added
session_timeout <- 5399.99  # Set in seconds (just under 90 minutes)
churn_threshold <- 14 * 24 * 60 * 60  # 14 day threshold in seconds
session_classification <- TRUE  # Run session classifier in step 2 (Nigeria only)

# Nigeria parameters
# The raw download lives outside the repo, at the path set in .Renviron
# (gitignored, so it must be recreated in every clone). Fail here with a usable
# message rather than later on a path that silently resolves to a bare filename.
if (!nzchar(Sys.getenv("aprendia_data_path"))) {
  stop("aprendia_data_path is not set — .Renviron is gitignored and must be recreated per repo. It should point at the offline_data location holding the raw download.")
}

# Bot phone numbers and test-user names live in config/local_identifiers.R
# (gitignored — real names and production numbers stay out of the tracked repo)
if (!file.exists("config/local_identifiers.R")) {
  stop("config/local_identifiers.R is missing — it holds the bot phone numbers and test-user names (gitignored). Restore it from backup before running.")
}
source("config/local_identifiers.R")
phone_num_from <- local_identifiers$nigeria$phone_num_from
phone_num_to <- local_identifiers$nigeria$phone_num_to
source_timezone <- "America/Mexico_City"  # Where downloads happen
target_timezone <- "Africa/Lagos"  # Nigeria timezone

# Columns to exclude
redundant_cols <- c(
  "parts", "call_duration", "labels", "currency", "price", "reaction_to", 
  "whats_app_flow_id", "whats_app_template", "whats_app_template_language"
)

# Test users to exclude (names in config/local_identifiers.R, gitignored)
test_users <- local_identifiers$nigeria$test_users

# Gender identification options
female_options <- c(
  "Am female",
  "Female",
  "female",
  "Female ✅",
  "Female ♀️",
  "Female gender",
  "I am a female",
  "I am a female by gender",
  "My gender female",
  "Okay am a female"
)

# File paths
raw_data_path <- file.path(Sys.getenv("APRENDIA_DATA_PATH"), "message_data.csv")

processed_data_path <- "data/nigeria/"
output_path <- "output/figures/nigeria/"

# Clustering parameters
clustering_seed <- 506
clustering_k_range <- 2:3
clustering_iter_max <- 50
clustering_runs <- 10

# Variables to exclude from clustering
clustering_exclude_vars <- c(
  "contact_id", "country", "female", "start_time", "avg_emojis", "given_options", "end_first_week", "to",
  "phone_num_match", "select_classroom_mgmt", "select_maths", "select_reading", "group", "start_week",
  "days_until_second_session", "user_phone_country",
  # Cluster output columns from previous run — present in contacts_data.csv on re-runs
  "cluster", "cluster_group", "cluster_label", "cluster_order", "cluster_group_label", "cluster_group_order",
  # Phase 1 of the field-reliability audit, summarised in the codebook (2026-09-07/08): restrict clustering
  # to tier-A (era-invariant) features only. The `_start` module flags are already caught by
  # step_rm(contains("_start")) in functions/clustering.R; these are the remaining B/D/E-tier
  # fields that survived to contacts_data.csv without being excluded.
  # Tier B (bot-template detectors, dark since 2026): select_course, select_question, and the
  # module-start sums they roll up into.
  "select_course", "select_question", "classroom_modules", "maths_modules", "reading_modules",
  "asked_question_week_one", "selected_course_week_one",
  # Tier D (mixed-source, speaker-blind) and E (rule-based session typing, unvalidated):
  "pct_sessions_with_reminder", "ever_completed_quiz",
  "n_module_sessions", "n_question_sessions", "n_lesson_sessions", "n_onboarding_sessions",
  "pct_substantive_sessions", "n_session_types"
)

# Cluster labels (update after reviewing cluster profiles)
# Labels for within-group clustering (cluster_group column)
cluster_group_lookup <- tribble(
  ~group,      ~cluster_group, ~cluster_group_label,     ~cluster_group_order,
  "Pilot",     1,              "Occasional users",        1,
  "Pilot",     2,              "Power users",             2,
  "Scale-up",  1,              "Occasional users",        1,
  "Scale-up",  2,              "Power users",             2
)

# Labels for full population clustering (cluster column)
cluster_lookup <- tribble(
  ~cluster, ~cluster_label,     ~cluster_order,
  2,        "Occasional users", 2,
  1,        "Power users",      1
)
