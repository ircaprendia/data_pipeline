# Refresh the dataset row-count table in codebook.md.
#
# Row counts in a codebook go stale the moment new data arrives. This script
# reads the current processed data files, counts their rows, and rewrites the
# table sitting between the <!-- BEGIN/END auto-counts --> markers in the
# codebook — so the counts always reflect the data on disk. Run it after a
# pipeline run (or add it to run_all.R).
#
# The unit descriptions and key-identifier notes are static text owned here;
# only the Rows column is computed. Counts reflect whatever is in each file —
# the combined files are all-country. The event_schema row was removed 2026-10-08
# (the event schema is no longer live).

library(tidyverse)

# Each dataset: the label and descriptive text shown in the table, its file,
# and the key-identifier note. Only `rows` is computed below.
datasets <- tribble(
  ~dataset,             ~unit,                            ~path,                           ~key,
  "clean_message_data", "One row per message",            "data/clean_message_data.csv",   "`message_id`",
  "session_data",       "One row per session",            "data/session_data.csv",         "`session_id`",
  "session_data_long",  "One row per session (extended)", "data/session_data_long.csv",    "`session_id`",
  "contacts_data",      "One row per user",               "data/contacts_data.csv",        "`contact_id`"
)

# Count data rows in a CSV by reading a single column only — fast, and it still
# handles quoted newlines correctly (a raw line count would not).
count_rows <- function(path) {
  if (!file.exists(path)) {
    warning("Missing file, count left blank: ", path)
    return(NA_integer_)
  }
  read_csv(
    path,
    col_select = 1,
    show_col_types = FALSE,
    progress = FALSE
  ) %>%
    nrow()
}

counts <- datasets %>%
  mutate(
    rows = map_int(path, count_rows),
    rows_fmt = if_else(
      is.na(rows),
      "—",
      format(rows, big.mark = ",", trim = TRUE)
    )
  )

# Rebuild the markdown table from the computed counts.
table_lines <- c(
  "| Dataset | Unit | Rows | Key identifier |",
  "|---|---|---|---|",
  counts %>%
    mutate(line = str_glue("| `{dataset}` | {unit} | {rows_fmt} | {key} |")) %>%
    pull(line)
)

refreshed_note <- str_glue(
  "*Row counts auto-generated {Sys.Date()} by `scripts/update_codebook_counts.R`.*"
)

block <- c(table_lines, "", refreshed_note)

# Splice the rebuilt block between the markers, leaving the rest untouched.
codebook_path <- "codebook.md"
lines <- read_lines(codebook_path)

begin <- str_which(lines, fixed("<!-- BEGIN auto-counts"))
end <- str_which(lines, fixed("<!-- END auto-counts"))
stopifnot(
  "expected exactly one BEGIN marker" = length(begin) == 1,
  "expected exactly one END marker" = length(end) == 1,
  "BEGIN marker must precede END marker" = begin < end
)

new_lines <- c(
  lines[seq_len(begin)],      # everything up to and including the BEGIN marker
  block,                      # the freshly built table
  lines[end:length(lines)]    # the END marker onward
)
write_lines(new_lines, codebook_path)

# Report what changed.
cat("Updated", codebook_path, "\n")
counts %>%
  select(dataset, rows) %>%
  print()
