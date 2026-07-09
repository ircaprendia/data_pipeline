# aprendIA — Load and anonymise raw Telerivet data
# Sets raw_message_data in the environment.
# Run once before any country-specific 01_clean.R script.
#
# Reads from aprendia_message_repository.csv — run scripts/update_repository.R
# first whenever a new Telerivet download is available.
#
# CORRECTED 2026-07-03: contact_id now passes through as Telerivet's own (confirmed
# non-PII, opaque internal) contact identifier, not a freshly reassigned integer. The
# previous scheme reassigned contact_id via `arrange(contact_id) %>% row_number()` --
# recomputed from scratch on every load, over whatever contacts happened to be in the
# repository at that moment. This is NOT stable across repository updates: adding new
# Telerivet contacts can shift the sort order and reassign every existing contact to a
# different integer, silently invalidating every downstream contact-keyed artifact
# (event_schema_audit.csv, LLM caches, session_classification_cache.csv, cluster labels, any
# historical "how did this contact's behaviour change over time" analysis) without any
# error or warning. Caught 2026-07-03 checking event_schema_audit.csv against a freshly
# reloaded clean_message_data.csv after a routine data update -- 32,141 of 33,209 rows
# had a contact_id that no longer matched the real message. Telerivet's own ID doesn't
# have this problem: Telerivet assigns it once per contact and never changes it.

library(tidyverse)
library(janitor)

# Test-user exclusion list lives in the gitignored config/local_identifiers.R (real names
# never enter a repo that may go public). It defines `all_test_users`; stop clearly if the
# file is missing rather than silently letting test contacts through.
if (!file.exists("config/local_identifiers.R")) {
  stop("config/local_identifiers.R not found — it defines all_test_users (tester exclusion list). See README.")
}
source("config/local_identifiers.R")

cat("Loading raw data...\n")
raw_message_data <- read_csv(
  file.path(Sys.getenv("aprendia_data_path"), "aprendia_message_repository.csv"),
  show_col_types = FALSE
) %>%
  clean_names() %>%
  filter(!contact_name %in% all_test_users) %>%
  select(-contact_name)

cat("Loaded", nrow(raw_message_data), "messages,",
    n_distinct(raw_message_data$contact_id), "contacts\n")
