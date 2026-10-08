# aprendIA — Step 2: Aggregate to session and contact level (universal, all countries)
# Runs once on the combined clean_message_data. Aggregation is country-aware: the shared
# functions add country to the grouping grain when the column is present, so sessions and
# contacts are split per country (contact_id x country). This keeps a dual-country contact's
# activity separate and removes the session-collision and fan-out bugs of the post-hoc join.
# Classification does NOT happen here — it has moved to scripts/nigeria/03_classify.R.
# Outputs (all countries, with a country column):
#   data/session_data.csv, data/session_data_long.csv, data/contacts_data.csv

#### Setup ####
library(tidyverse)

source("functions/data_aggregation.R")

#### Load data ####
if (!exists("clean_message_data")) {
  clean_message_data <- read_csv("data/clean_message_data.csv")
}

# churn_threshold is identical across all country configs (14 days), so a single value is
# correct for the combined data. session_timeout is not needed here — it was applied during
# cleaning, so session_id is already assigned per contact.
churn_threshold <- 14 * 24 * 60 * 60  # 14 days in seconds

#### Create session-level data ####
cat("Creating session-level datasets...\n")
session_datasets <- create_session_data(clean_message_data, churn_threshold)
session_data <- session_datasets$session_data
session_data_long <- session_datasets$session_data_long

#### Create contact-level data ####
cat("Creating contact-level dataset...\n")
contacts_data <- create_contacts_data(clean_message_data, session_data_long)

#### Save ####
cat("Saving combined datasets...\n")
write_csv(session_data,      "data/session_data.csv")
write_csv(session_data_long, "data/session_data_long.csv")
write_csv(contacts_data,     "data/contacts_data.csv")

#### Summary ####
cat("\n=== Step 2 Summary (combined) ===\n")
cat("Sessions:", nrow(session_data), "\n")
cat("Contacts:", nrow(contacts_data), "\n")

cat("\nSessions and contacts by country:\n")
print(
  contacts_data %>%
    group_by(country) %>%
    summarise(
      contacts = n(),
      .groups = "drop"
    )
)
print(
  session_data %>%
    group_by(country) %>%
    summarise(
      sessions = n(),
      .groups = "drop"
    )
)

# Country should now flow through aggregation natively — any NA means a session row lost its
# country in the grain (should be zero).
missing_country <- sum(is.na(session_data$country))
if (missing_country > 0) {
  cat("\nWARNING:", missing_country, "session(s) have no country.\n")
} else {
  cat("\nEvery session has a country.\n")
}

cat("\nSaved:\n")
cat("  - data/session_data.csv\n")
cat("  - data/session_data_long.csv\n")
cat("  - data/contacts_data.csv\n")

#### Run manifest ####
# Appended once per run, one row per country. data/ is shared with the analysis repo by symlink,
# so this is the only record of when the numbers behind a given figure were produced. Any later
# analysis can state "data as of X" from here instead of guessing at file timestamps.
# NA handling is deliberate: n_time_missing is recorded as a column rather than dropped quietly,
# so na.rm below cannot hide a parsing problem in time_corrected.

# --dirty matters here: HEAD alone would claim the figures came from a committed state when the
# working tree may have uncommitted edits. A "-dirty" suffix says the running code is not any
# commit, which is the honest answer to "what produced this number".
pipeline_sha <- tryCatch(
  {
    sha <- suppressWarnings(
      system("git describe --always --dirty", intern = TRUE, ignore.stderr = TRUE)
    )
    if (length(sha) == 1 && nzchar(sha)) sha else NA_character_
  },
  error = function(e) NA_character_
)

run_manifest <- clean_message_data %>%
  group_by(country) %>%
  summarise(
    messages = n(),
    n_time_missing = sum(is.na(time_corrected)),
    data_min = min(time_corrected, na.rm = TRUE),
    data_max = max(time_corrected, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(
    contacts_data %>% count(country, name = "contacts"),
    by = "country"
  ) %>%
  left_join(
    session_data %>% count(country, name = "sessions"),
    by = "country"
  ) %>%
  mutate(
    run_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    pipeline_sha = pipeline_sha
  ) %>%
  select(
    run_at, pipeline_sha, country, messages, contacts, sessions,
    data_min, data_max, n_time_missing
  )

write_csv(
  run_manifest,
  "data/run_manifest.csv",
  append = file.exists("data/run_manifest.csv")
)

cat("\nRun manifest appended — data/run_manifest.csv\n")
print(run_manifest %>% select(country, messages, contacts, sessions, data_max))
