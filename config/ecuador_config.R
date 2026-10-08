# Configuration for Ecuador Pilot cohort

# Cohort identification
cohort_name <- "ecuador"
start_date <- ymd("2024-08-15")
end_date <- ymd("2026-01-14")  # Day before scaleup starts

group_definitions <- NULL

# Analysis parameters
latest_week <- 27  # Adjust when new data is added
session_timeout <- 1200  # Set in seconds (20 minutes)
churn_threshold <- 14 * 24 * 60 * 60  # 14 day threshold in seconds

# Ecuador parameters
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
phone_num_from <- local_identifiers$ecuador$phone_num_from
phone_num_to <- local_identifiers$ecuador$phone_num_to
source_timezone <- "America/Mexico_City"  # Where downloads happen
target_timezone <- "America/Guayaquil"  # Ecuador timezone

# Test users to exclude (names in config/local_identifiers.R, gitignored)
test_users <- local_identifiers$ecuador$test_users

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
raw_data_path <- file.path(Sys.getenv("aprendia_data_path"), "message_data.csv")
processed_data_path <- "data/ecuador/"
output_path <- "output/figures/ecuador/"

# Clustering parameters
clustering_seed <- 506
clustering_k_range <- 2:7
clustering_iter_max <- 50
clustering_runs <- 10

# Variables to exclude from clustering
clustering_exclude_vars <- c("contact_id", "female", "start_time", "avg_emojis", 
                             "given_options", "end_first_week", "to", "phone_num_match",
                             "select_classroom_mgmt", "select_maths", "select_reading", 
                             "group")
