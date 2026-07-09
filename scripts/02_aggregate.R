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
