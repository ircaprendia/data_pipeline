# aprendIA — Step 1: Clean message data (universal, all countries)
# Loops over each country's config, cleans that country's slice (isolated by the
# phone-number filter inside clean_messages), stamps a country column, then unions
# the result into a single combined dataset.
# Output: data/clean_message_data.csv  (all countries, with a country column)

#### Setup ####
library(tidyverse)
library(janitor)

source("functions/data_cleaning.R")
source("functions/message_processing.R")

if (!exists("raw_message_data")) source("scripts/00_load_raw_data.R")

#### Clean each country, then combine ####
# Each config sets the cleaning parameters (phone numbers, timezones, session_timeout,
# group_definitions) and cohort_name, which we use as the country label. Country is only
# knowable here, because clean_messages isolates a country by its phone numbers.

countries <- c("nigeria", "ecuador", "niger")
clean_list <- vector("list", length(countries))

for (i in seq_along(countries)) {
  ctry <- countries[i]
  cat("\n──", ctry, "──────────────────────────────────────────\n")

  # Sourcing the config sets the parameters used just below. Each iteration overwrites
  # the previous country's globals, which is fine — they are consumed before the next source.
  source(paste0("config/", ctry, "_config.R"))

  country_clean <- clean_messages(
    raw_data = raw_message_data,
    phone_num_from = phone_num_from,
    phone_num_to = phone_num_to,
    female_options = female_options,
    source_timezone = source_timezone,
    target_timezone = target_timezone
  ) %>%
    # Drop WhatsApp system-event payloads (number-change / identity notices) that get ingested
    # as messages — they are not human interactions, so they must not form or pollute sessions.
    # Filtered before sequencing so session_ids are assigned over real messages only.
    filter(!str_detect(message_corrected, "user_changed_number|user_identity_changed|wa_id")) %>%
    add_selection_indicators() %>%
    add_implementation_timing() %>%
    add_message_sequencing(session_timeout) %>%
    add_module_signposts() %>%
    add_group_variable(group_definitions) %>%
    mutate(country = cohort_name)

  cat("  messages:", nrow(country_clean),
      " contacts:", n_distinct(country_clean$contact_id), "\n")

  clean_list[[i]] <- country_clean
}

clean_message_data <- bind_rows(clean_list)

#### Save ####
cat("\nSaving combined clean message data...\n")
dir.create("data", recursive = TRUE, showWarnings = FALSE)
write_csv(clean_message_data, "data/clean_message_data.csv")

#### Summary ####
cat("\n=== Step 1 Summary (combined) ===\n")
cat("Messages processed:", nrow(clean_message_data), "\n")
cat("Date range:",
    format(min(clean_message_data$time_corrected), "%Y-%m-%d"),
    "to",
    format(max(clean_message_data$time_corrected), "%Y-%m-%d"), "\n")

cat("\nMessages and contacts by country:\n")
print(
  clean_message_data %>%
    group_by(country) %>%
    summarise(
      messages = n(),
      contacts = n_distinct(contact_id),
      .groups = "drop"
    )
)

# Cross-country contact_id collision check — should be zero. contact_id is anonymised
# once over the whole repository, so each id belongs to exactly one country.
collisions <- clean_message_data %>%
  distinct(contact_id, country) %>%
  count(contact_id) %>%
  filter(n > 1)

if (nrow(collisions) > 0) {
  cat("\nWARNING:", nrow(collisions), "contact_id(s) appear in more than one country.\n")
} else {
  cat("\nNo contact_id collisions across countries.\n")
}

cat("\nSaved: data/clean_message_data.csv\n")
