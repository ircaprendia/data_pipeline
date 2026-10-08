# aprendIA Nigeria — Cluster assignment baseline snapshot
#
# One-off capture, not part of the numbered 01-05 pipeline chain. Writes the
# first rows of data/nigeria/cluster_assignments.csv, the dated assignment
# log proposed in the cluster persistence design note ("half two").
#
# What this captures: the cluster labels as they stood on disk BEFORE the
# Phase 1 tier-A-only re-fit (the field-reliability audit, summarised in the codebook
# 2026-09-08) — ie the OLD 53-feature clustering recipe, not the new one.
# This is a baseline for comparison, not a claim about when that fit was
# originally run: model_version and assigned_at record when THIS SNAPSHOT was
# taken, because the original fit date was never logged anywhere before now.
#
# Two clustering schemes exist (see codebook "Cluster variables"):
#   global — cluster_label,       compares all users against the full population
#   group  — cluster_group_label, compares users within their own cohort (Pilot/Scale-up)
# Both are captured, tagged by `scheme`, rather than picking one.
#
# Append-only going forward: re-running this script for a NEW fit should
# append new rows with a new model_version, not overwrite this file.

library(tidyverse)

contacts_data <- read_csv("data/nigeria/contacts_data.csv", show_col_types = FALSE)

snapshot_time <- Sys.time()

baseline_global <- contacts_data %>%
  filter(!is.na(cluster_label)) %>%
  transmute(
    contact_id    = contact_id,
    scheme        = "global",
    cluster_label = cluster_label,
    model_version = "pre_phase1_53feat",
    assigned_at   = snapshot_time
  )

baseline_group <- contacts_data %>%
  filter(!is.na(cluster_group_label)) %>%
  transmute(
    contact_id    = contact_id,
    scheme        = "group",
    cluster_label = cluster_group_label,
    model_version = "pre_phase1_53feat",
    assigned_at   = snapshot_time
  )

cluster_assignments <- bind_rows(baseline_global, baseline_group)

out_path <- "data/nigeria/cluster_assignments.csv"

if (file.exists(out_path)) {
  stop(
    "cluster_assignments.csv already exists — this script only writes the ",
    "first (baseline) snapshot. Append new rows for a new fit instead of ",
    "re-running this script; overwriting would destroy prior assignment history."
  )
}

write_csv(cluster_assignments, out_path)

cat(sprintf(
  "Baseline written: %d rows (%d contacts x %d schemes) to %s\n",
  nrow(cluster_assignments),
  n_distinct(cluster_assignments$contact_id),
  n_distinct(cluster_assignments$scheme),
  out_path
))
cat("model_version = 'pre_phase1_53feat' — the fit in place before the tier-A-only re-fit.\n")
cat("assigned_at reflects when this snapshot was taken, not the original fit date (never logged).\n")
