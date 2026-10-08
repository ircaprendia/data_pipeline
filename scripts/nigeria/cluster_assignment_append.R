# aprendIA Nigeria — append a new cluster assignment snapshot
#
# Companion to cluster_assignment_baseline.R. That script wrote the FIRST
# rows of data/nigeria/cluster_assignments.csv (the cluster persistence design note,
# "half two") and refuses to run twice. This script appends a NEW model_version's
# labels without touching prior rows — never overwrite, only add.
#
# Set model_version below before each run. Refuses to append a version that's
# already logged, so a re-run isn't silently duplicated.

library(tidyverse)

# Naming records what differed from the previous fit, so the log can be read later without
# cross-referencing anything. iter50 matters here: this fit hit clustering.R's iter_max = 50
# ceiling and reported "Quick-TRANSfer stage steps exceeded maximum (= 312350)", ie, 50 x 6,247
# contacts, so it stopped short of convergence. A re-fit at a higher ceiling should be logged
# as iter200 rather than replacing this one.
model_version <- "phase1_tier_a_20feat_20260911_iter50"  # <-- set before each run

log_path <- "data/nigeria/cluster_assignments.csv"

if (!file.exists(log_path)) {
  stop("cluster_assignments.csv does not exist — run cluster_assignment_baseline.R first.")
}

existing_log <- read_csv(log_path, show_col_types = FALSE)

if (model_version %in% existing_log$model_version) {
  stop(sprintf(
    "model_version '%s' is already logged (%d rows) — refusing to duplicate. ",
    model_version, sum(existing_log$model_version == model_version)
  ), "Set a new model_version if this is a genuinely new fit.")
}

contacts_data <- read_csv("data/nigeria/contacts_data.csv", show_col_types = FALSE)

snapshot_time <- Sys.time()

new_global <- contacts_data %>%
  filter(!is.na(cluster_label)) %>%
  transmute(
    contact_id    = contact_id,
    scheme        = "global",
    cluster_label = cluster_label,
    model_version = model_version,
    assigned_at   = snapshot_time
  )

new_group <- contacts_data %>%
  filter(!is.na(cluster_group_label)) %>%
  transmute(
    contact_id    = contact_id,
    scheme        = "group",
    cluster_label = cluster_group_label,
    model_version = model_version,
    assigned_at   = snapshot_time
  )

new_rows <- bind_rows(new_global, new_group)

write_csv(bind_rows(existing_log, new_rows), log_path)

cat(sprintf(
  "Appended: %d rows (%d contacts x %d schemes) under model_version = '%s'\n",
  nrow(new_rows), n_distinct(new_rows$contact_id), n_distinct(new_rows$scheme), model_version
))
cat(sprintf("cluster_assignments.csv now holds %d model_version(s): %s\n",
    n_distinct(c(existing_log$model_version, model_version)),
    paste(unique(c(existing_log$model_version, model_version)), collapse = ", ")))
