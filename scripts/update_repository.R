# aprendIA — Update message repository
#
# Run this after each Telerivet download to incorporate new data.
# On first run (no repository yet), seeds from all date-prefixed archive
# files found anywhere under aprendia_data_path + message_data.csv.
#
# Usage: source("scripts/update_repository.R")
#
# Inputs (all under aprendia_data_path/):
#   message_data.csv                — latest Telerivet download
#   aprendia_message_repository.csv — existing repository (if any)
#   YYYY.MM.DD_*/                   — any date-prefixed archive files (seed only)

library(tidyverse)
library(janitor)
library(lubridate)

repo_file    <- "aprendia_message_repository.csv"
new_file     <- "message_data.csv"
data_root    <- Sys.getenv("aprendia_data_path")

repo_path    <- file.path(data_root, repo_file)
new_path     <- file.path(data_root, new_file)

# ── Helpers ───────────────────────────────────────────────────

read_raw <- function(path) {
  read_csv(path, show_col_types = FALSE) %>% clean_names()
}

parse_dates <- function(df) {
  # Use time_sent where available, fall back to date; both are dmy_hms strings
  dates <- dmy_hms(df$time_sent, quiet = TRUE)
  dates[is.na(dates)] <- dmy_hms(df$date[is.na(dates)], quiet = TRUE)
  dates
}

# ── Load new Telerivet export ──────────────────────────────────

cat("Loading new Telerivet export...\n")
new_data <- read_raw(new_path)
new_dates <- parse_dates(new_data)

cat("  ", nrow(new_data), "messages\n")
cat("  Range:", format(min(new_dates, na.rm = TRUE), "%Y-%m-%d"),
    "to", format(max(new_dates, na.rm = TRUE), "%Y-%m-%d"), "\n")

# ── Seed or update ─────────────────────────────────────────────

if (!file.exists(repo_path)) {

  # ── First run: seed from all date-prefixed archive files + new download ──
  cat("\nNo repository found — seeding from all source files.\n")

  # Collect all date-prefixed files (YYYY.MM.DD_*) anywhere under data_root,
  # excluding the repository and current download
  exclude <- c(repo_file, new_file)
  historical_files <- list.files(
    data_root,
    pattern    = "^\\d{4}\\.\\d{2}\\.\\d{2}_",
    recursive  = TRUE,
    full.names = TRUE
  ) %>% .[!basename(.) %in% exclude]

  if (length(historical_files) == 0) {
    cat("  No archive files found — seeding from new download only.\n")
    combined <- new_data
  } else {
    cat("  Archive files found:\n")
    for (f in historical_files) cat("    -", basename(f), "\n")

    historical <- map(historical_files, read_raw) %>% bind_rows()
    combined   <- bind_rows(historical, new_data) %>%
      distinct(message_id, .keep_all = TRUE) %>%
      arrange(date)

    cat("  Historical messages:", nrow(historical), "\n")
    cat("  After deduplication:", nrow(combined), "total messages\n")
  }

  # On a seed build every row is new
  new_rows <- nrow(combined)

} else {

  # ── Subsequent runs: append new data ──────────────────────────
  cat("\nLoading existing repository...\n")
  repo       <- read_raw(repo_path)
  repo_dates <- parse_dates(repo)

  cat("  ", nrow(repo), "messages in repository\n")
  cat("  Repository range:", format(min(repo_dates, na.rm = TRUE), "%Y-%m-%d"),
      "to", format(max(repo_dates, na.rm = TRUE), "%Y-%m-%d"), "\n")

  # ── Gap check ────────────────────────────────────────────────
  repo_max <- max(repo_dates, na.rm = TRUE)
  new_min  <- min(new_dates,  na.rm = TRUE)
  gap_days <- as.numeric(difftime(new_min, repo_max, units = "days"))

  cat("\n── Gap check ──────────────────────────────────────────────\n")
  if (gap_days > 1) {
    cat("WARNING: gap of", round(gap_days, 1), "days between repository and new download.\n")
    cat("  Repository ends:", format(repo_max, "%Y-%m-%d"), "\n")
    cat("  New data starts:", format(new_min,  "%Y-%m-%d"), "\n")
    cat("  Messages in this window may have been deleted by Telerivet.\n")
    cat("  Consider saving this download as a new archive before proceeding.\n")
  } else {
    overlap <- round(-gap_days)
    cat("OK — new download overlaps repository by", overlap, "day(s).\n")
  }

  # ── Bind and deduplicate ─────────────────────────────────────
  combined  <- bind_rows(repo, new_data) %>%
    distinct(message_id, .keep_all = TRUE) %>%
    arrange(date)

  new_rows <- nrow(combined) - nrow(repo)
  cat("\n── Summary ────────────────────────────────────────────────\n")
  cat("  New messages added: ", new_rows, "\n")
  cat("  Repository total:  ", nrow(combined), "\n")
}

# ── Final date range ───────────────────────────────────────────
combined_dates <- parse_dates(combined)
cat("\nFinal range:", format(min(combined_dates, na.rm = TRUE), "%Y-%m-%d"),
    "to", format(max(combined_dates, na.rm = TRUE), "%Y-%m-%d"), "\n")

# ── Save ───────────────────────────────────────────────────────
write_csv(combined, repo_path)
cat("\n✓  Repository saved:", repo_path, "\n")

# ── Back up off-machine ────────────────────────────────────────
# The repository still carries identifiable contact details (anonymisation
# happens downstream in 00_load_raw_data.R), so the off-machine backup goes to a
# restricted store, not a synced folder. Writes a rolling copy plus a date-stamped
# snapshot. Only runs when new rows were added and the backup location is set and
# present; otherwise it skips with a message rather than erroring.

# The backup location is set in .Renviron as aprendia_backup_path (gitignored, so
# it is recreated per clone). Unset, the backup is skipped. The skip branch is
# deliberately non-fatal, so a wrong path silently skips every backup: check
# the log message after any change to the path.
backup_archive <- Sys.getenv("aprendia_backup_path")

if (new_rows > 0 && nzchar(backup_archive) && dir.exists(backup_archive)) {

  # Rolling copy — overwrite the canonical backup
  write_csv(combined, file.path(backup_archive, repo_file))

  # Date-stamped snapshot — matches the existing YYYY.MM.DD_message_data.csv convention
  snapshot_name <- paste0(format(Sys.Date(), "%Y.%m.%d"), "_message_data.csv")
  write_csv(combined, file.path(backup_archive, "Archive", snapshot_name))

  cat("\n✓  Backed up:\n")
  cat("     rolling: ", file.path(backup_archive, repo_file), "\n")
  cat("     snapshot:", file.path(backup_archive, "Archive", snapshot_name), "\n")

} else if (new_rows <= 0) {
  cat("\n—  No new rows added; Box backup skipped.\n")
} else {
  cat("\n⚠  Box archive not found — backup skipped. THE LAPTOP IS NOW THE ONLY COPY.\n")
  cat("     Expected:", backup_archive, "\n")

  # A rename is the likeliest cause, and the skip is deliberately non-fatal, which is exactly
  # how the 2026-09-04 lapse went unnoticed for a week. So look for near matches and report the
  # age of whatever backup does exist, rather than leaving it to be guessed at.
  box_root <- dirname(backup_archive)

  if (dir.exists(box_root)) {
    candidates <- list.dirs(box_root, recursive = FALSE, full.names = TRUE)
    candidates <- candidates[grepl("archive", basename(candidates), ignore.case = TRUE)]

    if (length(candidates) > 0) {
      cat("     Similar folders that DO exist — has this been renamed?\n")
      for (candidate in candidates) {
        cat("       ", candidate, "\n")
      }

      existing <- file.path(candidates, repo_file)
      existing <- existing[file.exists(existing)]

      if (length(existing) > 0) {
        age_days <- round(
          as.numeric(difftime(Sys.time(), file.mtime(existing[1]), units = "days")),
          1
        )
        cat("     Newest backup found is", age_days, "day(s) old:\n")
        cat("       ", existing[1], "\n")
      }
    }
  } else {
    cat("     Box root not present either — is Box Drive running and signed in?\n")
  }
}
