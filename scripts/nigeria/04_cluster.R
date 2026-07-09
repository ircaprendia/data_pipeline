# aprendIA Nigeria — Step 4: User clustering
# When k=2, labels are assigned automatically (higher avg messages → Power users).
# If any group resolves to k>2, the script stops for manual review of that group.
# Outputs: data/nigeria/contacts_data.csv (with cluster columns added)

#### Setup ####
library(tidyverse)

source("config/nigeria_config.R")
source("functions/clustering.R")

#### Load data ####
# Read explicitly from disk rather than reusing in-memory objects: after 02_aggregate the
# in-memory session_data is the COMBINED, unclassified table, so we must take the classified
# Nigeria slice that 03_classify wrote, and slice the combined clean/long files to Nigeria.
contacts_data      <- read_csv("data/nigeria/contacts_data.csv")
session_data       <- read_csv("data/nigeria/session_data.csv")
clean_message_data <- read_csv("data/clean_message_data.csv") %>% filter(country == "nigeria")
session_data_long  <- read_csv("data/session_data_long.csv")  %>% filter(country == "nigeria")

# ── Week-capping: normalise Pilot tenure to Scale-up maximum ──
# Recomputes cumulative features from message/session data capped at each
# user's first n_weeks of programme participation, so Pilot users (who have
# had more time) are not favoured over Scale-up users in clustering.

cap_contacts_to_weeks <- function(msg, sess, sess_long, contacts, n_weeks) {

  # Each user's cap: their start_week + n_weeks - 1
  user_caps <- contacts %>% transmute(contact_id, cap_week = start_week + n_weeks - 1L)

  msg_c  <- msg       %>% left_join(user_caps, by = "contact_id") %>%
    filter(impl_week <= cap_week) %>% select(-cap_week)
  sess_c <- sess      %>% left_join(user_caps, by = "contact_id") %>%
    filter(impl_week <= cap_week) %>% select(-cap_week)
  sl_c   <- sess_long %>% left_join(user_caps, by = "contact_id") %>%
    filter(impl_week <= cap_week) %>% select(-cap_week)

  # Recompute message-level cumulative features
  msg_feats <- msg_c %>%
    group_by(contact_id) %>%
    summarise(
      num_messages         = n(),
      num_sessions         = max(session_id),
      avg_time_btwn_msgs   = mean(time_btwn_msgs,       na.rm = TRUE),
      interaction_ratio    = mean(direction == "Incoming"),
      avg_rcvd_emojis      = mean(msg_rcvd_emoji_count, na.rm = TRUE),
      avg_sent_emojis      = mean(msg_sent_emoji_count, na.rm = TRUE),
      avg_msg_length       = mean(msg_length,           na.rm = TRUE),
      avg_rcvd_msg_length  = mean(msg_length_rcvd,      na.rm = TRUE),
      avg_sent_msg_length  = mean(msg_length_sent,      na.rm = TRUE),
      classroom_mod1_start = sum(classroom_mod1_start),
      classroom_mod2_start = sum(classroom_mod2_start),
      classroom_mod3_start = sum(classroom_mod3_start),
      classroom_mod4_start = sum(classroom_mod4_start),
      maths_mod1_start     = sum(maths_mod1_start),
      maths_mod2_start     = sum(maths_mod2_start),
      maths_mod3_start     = sum(maths_mod3_start),
      maths_mod4_start     = sum(maths_mod4_start),
      maths_mod5_start     = sum(maths_mod5_start),
      reading_mod1_start   = sum(reading_mod1_start),
      reading_mod2_start   = sum(reading_mod2_start),
      reading_mod3_start   = sum(reading_mod3_start),
      reading_mod4_start   = sum(reading_mod4_start),
      reading_mod5_start   = sum(reading_mod5_start),
      .groups = "drop"
    ) %>%
    mutate(
      # Cap at 1 hour: prevents single long-absent users from dominating clustering
      # distance calculations. Treats all extended absences as equivalent.
      avg_time_btwn_msgs = pmin(avg_time_btwn_msgs, 3600),
      classroom_modules  = classroom_mod1_start + classroom_mod2_start +
                           classroom_mod3_start + classroom_mod4_start,
      maths_modules      = maths_mod1_start + maths_mod2_start + maths_mod3_start +
                           maths_mod4_start + maths_mod5_start,
      reading_modules    = reading_mod1_start + reading_mod2_start + reading_mod3_start +
                           reading_mod4_start + reading_mod5_start
    )

  # Recompute churn/reactivation from capped session_data_long
  churn_feats <- sl_c %>%
    group_by(contact_id) %>%
    summarise(
      churn_count      = sum(churned,     na.rm = TRUE),
      reactivate_count = sum(reactivated, na.rm = TRUE),
      .groups = "drop"
    )

  # Recompute session-type features from capped session_data
  sess_feats <- sess_c %>%
    group_by(contact_id) %>%
    summarise(
      n_module_sessions        = sum(session_type == "Module progression",    na.rm = TRUE),
      n_question_sessions      = sum(session_type %in% c("Question asking", "Quick question"), na.rm = TRUE),
      n_lesson_sessions        = sum(session_type == "Lesson/Content request", na.rm = TRUE),
      n_onboarding_sessions    = sum(session_type == "User onboarding",        na.rm = TRUE),
      pct_substantive_sessions = mean(session_type %in% c(
        "Module progression", "Question asking", "Quick question",
        "Lesson/Content request", "User onboarding"), na.rm = TRUE),
      n_session_types          = n_distinct(session_type),
      ever_completed_quiz      = as.integer(any(completed_quiz, na.rm = TRUE)),
      pct_sessions_with_reminder = mean(started_with_reminder == TRUE, na.rm = TRUE),
      n_bot_outreach_sessions  = sum(session_type == "Bot outreach (unanswered)", na.rm = TRUE),
      .groups = "drop"
    )

  # Replace capped features, keep everything else unchanged
  replace_cols <- c(names(msg_feats)[-1], names(churn_feats)[-1], names(sess_feats)[-1])
  contacts %>%
    select(-any_of(replace_cols)) %>%
    left_join(msg_feats,   by = "contact_id") %>%
    left_join(churn_feats, by = "contact_id") %>%
    left_join(sess_feats,  by = "contact_id")
}

# Compute dynamic cap: max weeks any Scale-up user could have accumulated
scale_up_max_weeks <- contacts_data %>%
  filter(group == "Scale-up") %>%
  mutate(available_weeks = max(clean_message_data$impl_week, na.rm = TRUE) - start_week + 1L) %>%
  pull(available_weeks) %>%
  max(na.rm = TRUE)

cat(sprintf("Week cap: %d weeks (Scale-up maximum)\n", scale_up_max_weeks))

contacts_data <- cap_contacts_to_weeks(
  msg      = clean_message_data,
  sess     = session_data,
  sess_long = session_data_long,
  contacts  = contacts_data,
  n_weeks   = scale_up_max_weeks
)

# ── Helpers for automatic k=2 label assignment ────────────────
# Power users = cluster with higher average message count

build_k2_overall_lookup <- function(data_with_cluster) {
  profiles <- data_with_cluster %>%
    group_by(cluster) %>%
    summarise(avg_msgs = mean(num_messages, na.rm = TRUE), .groups = "drop") %>%
    arrange(desc(avg_msgs))

  tribble(
    ~cluster, ~cluster_label,     ~cluster_order,
    profiles$cluster[1], "Power users",      1,
    profiles$cluster[2], "Occasional users", 2
  )
}

build_k2_group_lookup <- function(data_with_cluster_group, group_name) {
  profiles <- data_with_cluster_group %>%
    group_by(cluster_group) %>%
    summarise(avg_msgs = mean(num_messages, na.rm = TRUE), .groups = "drop") %>%
    arrange(desc(avg_msgs))

  tribble(
    ~group, ~cluster_group,        ~cluster_group_label,  ~cluster_group_order,
    group_name, profiles$cluster_group[1], "Power users",      2,
    group_name, profiles$cluster_group[2], "Occasional users", 1
  )
}

needs_review <- character(0)

# ── 1. Full population clustering ─────────────────────────────
cat("Clustering all users...\n")
overall_clustering <- run_user_clustering(
  data         = contacts_data,
  exclude_vars = clustering_exclude_vars,
  k_range      = clustering_k_range,
  seed         = clustering_seed,
  iter_max     = clustering_iter_max,
  runs         = clustering_runs
)
contacts_data$cluster <- overall_clustering$assignments
k_overall <- length(unique(overall_clustering$assignments))

cat("\n=== Overall Cluster Profiles (k =", k_overall, ") ===\n")
print(summarise_cluster_profiles(contacts_data))

if (k_overall == 2) {
  cluster_lookup <- build_k2_overall_lookup(contacts_data)
  cat("Auto-assigned: cluster", cluster_lookup$cluster[1], "→ Power users,",
      "cluster", cluster_lookup$cluster[2], "→ Occasional users\n")
} else {
  needs_review <- c(needs_review, sprintf("Overall population (k=%d) — update cluster_lookup", k_overall))
}

# ── 2. Pilot clustering ───────────────────────────────────────
cat("\nClustering Pilot users...\n")
pilot_data <- contacts_data %>% filter(group == "Pilot")
pilot_clustering <- run_user_clustering(
  data         = pilot_data,
  exclude_vars = clustering_exclude_vars,
  k_range      = clustering_k_range,
  seed         = clustering_seed,
  iter_max     = clustering_iter_max,
  runs         = clustering_runs
)
pilot_data$cluster_group <- pilot_clustering$assignments
k_pilot <- length(unique(pilot_clustering$assignments))

cat("\n=== Pilot Cluster Profiles (k =", k_pilot, ") ===\n")
print(summarise_cluster_profiles(
  pilot_data %>% select(-cluster) %>% rename(cluster = cluster_group)
))

if (k_pilot == 2) {
  pilot_group_lookup <- build_k2_group_lookup(pilot_data, "Pilot")
  cat("Auto-assigned: cluster", pilot_group_lookup$cluster_group[1], "→ Power users,",
      "cluster", pilot_group_lookup$cluster_group[2], "→ Occasional users\n")
} else {
  needs_review <- c(needs_review, sprintf("Pilot group (k=%d) — update cluster_group_lookup", k_pilot))
  pilot_group_lookup <- NULL
}

# ── 3. Scale-up clustering ────────────────────────────────────
scaleup_data <- contacts_data %>% filter(group == "Scale-up")

if (nrow(scaleup_data) >= 50) {
  cat("\nClustering Scale-up users...\n")
  scaleup_clustering <- run_user_clustering(
    data         = scaleup_data,
    exclude_vars = clustering_exclude_vars,
    k_range      = clustering_k_range,
    seed         = clustering_seed,
    iter_max     = clustering_iter_max,
    runs         = clustering_runs
  )
  scaleup_data$cluster_group <- scaleup_clustering$assignments
  k_scaleup <- length(unique(scaleup_clustering$assignments))

  cat("\n=== Scale-up Cluster Profiles (k =", k_scaleup, ") ===\n")
  print(summarise_cluster_profiles(
    scaleup_data %>% select(-cluster) %>% rename(cluster = cluster_group)
  ))

  if (k_scaleup == 2) {
    scaleup_group_lookup <- build_k2_group_lookup(scaleup_data, "Scale-up")
    cat("Auto-assigned: cluster", scaleup_group_lookup$cluster_group[1], "→ Power users,",
        "cluster", scaleup_group_lookup$cluster_group[2], "→ Occasional users\n")
  } else {
    needs_review <- c(needs_review, sprintf("Scale-up group (k=%d) — update cluster_group_lookup", k_scaleup))
    scaleup_group_lookup <- NULL
  }
} else {
  cat("\nNot enough Scale-up users (n =", nrow(scaleup_data), "), skipping.\n")
  scaleup_data$cluster_group <- NA
  scaleup_group_lookup <- tribble(
    ~group,      ~cluster_group, ~cluster_group_label, ~cluster_group_order,
    "Scale-up",  NA_integer_,    NA_character_,         NA_integer_
  )
}

# ══════════════════════════════════════════════════════════════
# Stop if any group needs manual label review
# ══════════════════════════════════════════════════════════════
if (length(needs_review) > 0) {
  cat("\n⚠️  Manual review required for:\n")
  for (g in needs_review) cat("  -", g, "\n")
  stop("Update cluster_lookup / cluster_group_lookup in config/nigeria_config.R, comment out this stop(), and re-run from step 3.")
}

# ── 4. Build final lookups and apply labels ───────────────────
cluster_group_lookup <- bind_rows(pilot_group_lookup, scaleup_group_lookup)

cluster_group_assignments <- bind_rows(
  pilot_data   %>% select(contact_id, cluster_group),
  scaleup_data %>% select(contact_id, cluster_group)
)

contacts_data <- contacts_data %>%
  select(-any_of(c("cluster_group", "cluster_label", "cluster_order", "cluster_group_label", "cluster_group_order"))) %>%
  left_join(cluster_group_assignments, by = "contact_id") %>%
  apply_cluster_labels()

clean_message_data <- clean_message_data %>%
  select(-any_of(c("cluster", "cluster_group", "cluster_label", "cluster_order", "cluster_group_label", "cluster_group_order"))) %>%
  left_join(contacts_data %>% select(contact_id, cluster, cluster_group), by = "contact_id") %>%
  apply_cluster_labels()

session_data <- session_data %>%
  select(-any_of(c("cluster", "cluster_group", "cluster_label", "cluster_order", "cluster_group_label", "cluster_group_order"))) %>%
  left_join(contacts_data %>% select(contact_id, cluster, cluster_group), by = "contact_id") %>%
  apply_cluster_labels()

session_data_long <- session_data_long %>%
  select(-any_of(c("cluster", "cluster_group", "cluster_label", "cluster_order", "cluster_group_label", "cluster_group_order"))) %>%
  left_join(contacts_data %>% select(contact_id, cluster, cluster_group), by = "contact_id") %>%
  apply_cluster_labels()

# ── 5. Save ───────────────────────────────────────────────────
write_csv(contacts_data,      "data/nigeria/contacts_data.csv")
write_csv(clean_message_data, "data/nigeria/clean_message_data.csv")
write_csv(session_data,       "data/nigeria/session_data.csv")
write_csv(session_data_long,  "data/nigeria/session_data_long.csv")

cat("\nClustering complete. All datasets updated with cluster labels.\n")
