# aprendIA Niger — Step 5: Pre-compute dashboard aggregations
# Outputs: data/niger/agg_*.rds, data/niger/dashboard_scalars.rds

#### Setup ####
library(tidyverse)
library(survival)
library(broom)

source("config/niger_config.R")

# processed_data_path is defined in the config above. Create it if absent — a fresh clone has no
# data/ subdirectories and saveRDS will not make them, so every write below would fail.
dir.create(processed_data_path, recursive = TRUE, showWarnings = FALSE)

#### Load data ####
# Read the combined datasets from disk and take the Niger slice. Reading explicitly (not via
# in-memory objects) keeps this order-independent within run_all — each country reads the full
# combined file fresh and filters its own rows.
clean_message_data <- read_csv("data/clean_message_data.csv") %>% filter(country == "niger")
session_data_long  <- read_csv("data/session_data_long.csv")  %>% filter(country == "niger")
session_data       <- read_csv("data/session_data.csv")       %>% filter(country == "niger")
contacts_data      <- read_csv("data/contacts_data.csv")      %>% filter(country == "niger")

# Add dummy cluster columns for schema consistency with Nigeria
clean_message_data <- clean_message_data %>% mutate(cluster_label = "None", cluster_group_label = "None")
session_data_long  <- session_data_long  %>% mutate(cluster_label = "None", cluster_group_label = "None")
session_data       <- session_data       %>% mutate(cluster_label = "None", cluster_group_label = "None")
contacts_data      <- contacts_data      %>% mutate(cluster_label = "None", cluster_group_label = "None")

#### Derived dates ####
first_message_date <- as.Date(min(clean_message_data$time_corrected, na.rm = TRUE))

cutoff_date <- clean_message_data %>%
  filter(impl_week == max(impl_week, na.rm = TRUE)) %>%
  summarise(cutoff = max(as.Date(time_corrected))) %>%
  pull(cutoff)

latest_message <- max(clean_message_data$time_corrected, na.rm = TRUE)
complete_weeks <- floor(as.numeric(difftime(latest_message, first_message_date, units = "weeks")))

#### Active filters ####
active_messages <- clean_message_data %>%
  group_by(contact_id, session_id) %>%
  mutate(session_interaction_ratio = mean(direction == "Incoming")) %>%
  ungroup() %>%
  filter(session_interaction_ratio > 0) %>%
  filter(impl_week <= complete_weeks)

active_sessions <- session_data %>%
  filter(in_msgs_per_session > 0) %>%
  filter(impl_week <= complete_weeks)


# ── 1. Weekly active users ────────────────────────────────────

weekly_impl <- active_messages %>%
  filter(!is.na(impl_week), !is.na(group)) %>%
  group_by(impl_week, group, cluster_label, cluster_group_label) %>%
  summarise(n_users = n_distinct(contact_id), .groups = "drop") %>%
  mutate(
    week      = impl_week,
    week_date = first_message_date + weeks(impl_week - 1) + days(3),
    time_type = "impl_week"
  ) %>%
  select(-impl_week)

weekly_msg <- active_messages %>%
  filter(!is.na(message_week), !is.na(group)) %>%
  group_by(message_week, group, cluster_label, cluster_group_label) %>%
  summarise(n_users = n_distinct(contact_id), .groups = "drop") %>%
  mutate(
    week      = message_week,
    week_date = NA_Date_,
    time_type = "message_week"
  ) %>%
  select(-message_week)

agg_weekly_users <- bind_rows(weekly_impl, weekly_msg)

saveRDS(agg_weekly_users, paste0(processed_data_path, "agg_weekly_users.rds"))
message("✓  agg_weekly_users.rds — ", nrow(agg_weekly_users), " rows")


# ── 2. Survival / persistence model ──────────────────────────
# FIXED to match Nigeria's 2026-09-21 correction (nigeria/05_dashboard.R,
# section 2): population switched from session-level activity
# (session_data_long, in_msgs_per_session > 0) to message-level activity
# (direction == "Incoming" on clean_message_data directly), matching this
# script's own "active" definition elsewhere. Niger has no real clusters,
# so only the "total" curve is genuine; the other three views duplicate it
# for schema consistency with Nigeria's agg_survival shape -- which also
# means the column is now named cluster_label (not cluster_group_label),
# matching Nigeria's naming rather than diverging from it.

persistence_metrics <- clean_message_data %>%
  filter(direction == "Incoming") %>%
  mutate(date = as.Date(date)) %>%
  group_by(contact_id) %>%
  arrange(date) %>%
  summarise(
    first_activity  = min(date),
    last_activity   = max(date),
    active_days     = n_distinct(date),
    days_since_last = as.numeric(cutoff_date - last_activity),
    event           = (days_since_last >= 14) & (first_activity <= cutoff_date),
    .groups = "drop"
  ) %>%
  filter(first_activity <= cutoff_date)

persistence_data <- persistence_metrics %>%
  left_join(
    contacts_data %>% select(contact_id, group),
    by = "contact_id"
  ) %>%
  filter(!is.na(group))

# Niger has one population (no groups/clusters), so all views are the same curve.
# Compute total once and duplicate for schema consistency with Nigeria.
fit_total <- survfit(Surv(active_days, event) ~ 1, data = persistence_data)

base_survival <- broom::tidy(fit_total) %>%
  select(time, estimate, conf.low, conf.high)

agg_survival <- bind_rows(
  base_survival %>% mutate(view = "total",   strata_label = "Total",          group = NA_character_, cluster_label = NA_character_),
  base_survival %>% mutate(view = "4strata", strata_label = "Default · None", group = "Default",     cluster_label = "None"),
  base_survival %>% mutate(view = "group",   strata_label = "Default",        group = "Default",     cluster_label = NA_character_),
  base_survival %>% mutate(view = "cluster", strata_label = "None",           group = NA_character_, cluster_label = "None")
) %>%
  select(view, group, cluster_label, strata_label, time, estimate, conf.low, conf.high)

saveRDS(agg_survival, paste0(processed_data_path, "agg_survival.rds"))
message("✓  agg_survival.rds — ", nrow(agg_survival), " rows")


# ── 3. Average sessions per active user per week ──────────────

sessions_impl <- active_sessions %>%
  filter(!is.na(impl_week), !is.na(group)) %>%
  group_by(impl_week, group, cluster_label, cluster_group_label, contact_id) %>%
  summarise(n_sessions = n(), .groups = "drop") %>%
  group_by(impl_week, group, cluster_label, cluster_group_label) %>%
  summarise(avg_sessions = mean(n_sessions), .groups = "drop") %>%
  mutate(
    week      = impl_week,
    week_date = first_message_date + weeks(impl_week - 1) + days(3),
    time_type = "impl_week"
  ) %>%
  select(-impl_week)

sessions_msg <- active_sessions %>%
  filter(!is.na(message_week), !is.na(group)) %>%
  group_by(message_week, group, cluster_label, cluster_group_label, contact_id) %>%
  summarise(n_sessions = n(), .groups = "drop") %>%
  group_by(message_week, group, cluster_label, cluster_group_label) %>%
  summarise(avg_sessions = mean(n_sessions), .groups = "drop") %>%
  mutate(
    week      = message_week,
    week_date = NA_Date_,
    time_type = "message_week"
  ) %>%
  select(-message_week)

agg_avg_sessions <- bind_rows(sessions_impl, sessions_msg)

saveRDS(agg_avg_sessions, paste0(processed_data_path, "agg_avg_sessions.rds"))
message("✓  agg_avg_sessions.rds — ", nrow(agg_avg_sessions), " rows")


# ── 4. User trajectories ──────────────────────────────────────
# FIXED to match Nigeria's 2026-09-21 correction (nigeria/05_dashboard.R,
# section 4): message_num/last_message recomputed from scratch on
# Incoming-only rows, rather than reusing the pre-existing both-directions
# columns of those names (bot replies counted, and a contact whose final
# message was an outgoing bot reply could lose its endpoint dot once
# filtered to Incoming-only downstream).

agg_user_traj <- clean_message_data %>%
  filter(!is.na(group), direction == "Incoming") %>%
  mutate(date = as.Date(date)) %>%
  group_by(contact_id, date, group, cluster_label, cluster_group_label) %>%
  summarise(n_msgs = n(), .groups = "drop") %>%
  group_by(contact_id) %>%
  arrange(date, .by_group = TRUE) %>%
  mutate(
    message_num  = cumsum(n_msgs),
    day_lapse    = as.numeric(date - min(date)),
    last_message = date == max(date)
  ) %>%
  ungroup() %>%
  mutate(week_lapse = day_lapse / 7) %>%
  select(contact_id, week_lapse, group, cluster_label, cluster_group_label, message_num, last_message)

saveRDS(agg_user_traj, paste0(processed_data_path, "agg_user_traj.rds"))
message("✓  agg_user_traj.rds — ", nrow(agg_user_traj), " rows")


# ── 5. Activation / churn / reactivation flows ───────────────

user_active_days <- active_messages %>%
  distinct(contact_id, impl_day, group, cluster_label, cluster_group_label)

activated_counts <- user_active_days %>%
  group_by(contact_id, group, cluster_label, cluster_group_label) %>%
  summarise(first_day = min(impl_day), .groups = "drop") %>%
  count(day = first_day, group, cluster_label, cluster_group_label, name = "activated")

churn_events <- user_active_days %>%
  arrange(contact_id, impl_day) %>%
  group_by(contact_id, group, cluster_label, cluster_group_label) %>%
  mutate(prev_day = lag(impl_day), gap = impl_day - prev_day) %>%
  filter(gap > 14) %>%
  mutate(churn_day = prev_day + 14L) %>%
  ungroup()

churned_counts     <- churn_events %>% count(day = churn_day, group, cluster_label, cluster_group_label, name = "churned")
reactivated_counts <- churn_events %>% count(day = impl_day,  group, cluster_label, cluster_group_label, name = "reactivated")

users_stock <- active_messages %>%
  group_by(day = impl_day, group, cluster_label, cluster_group_label) %>%
  summarise(users = n_distinct(contact_id), .groups = "drop")

agg_activation <- users_stock %>%
  full_join(activated_counts,    by = c("day", "group", "cluster_label", "cluster_group_label")) %>%
  full_join(churned_counts,      by = c("day", "group", "cluster_label", "cluster_group_label")) %>%
  full_join(reactivated_counts,  by = c("day", "group", "cluster_label", "cluster_group_label")) %>%
  filter(!is.na(day)) %>%
  mutate(across(c(activated, churned, reactivated), \(x) replace_na(x, 0L))) %>%
  arrange(group, cluster_label, day)

saveRDS(agg_activation, paste0(processed_data_path, "agg_activation.rds"))
message("✓  agg_activation.rds — ", nrow(agg_activation), " rows")


# ── 6. Summary scalars ────────────────────────────────────────

total_users <- active_messages %>%
  summarise(n = n_distinct(contact_id)) %>%
  pull(n)

last_four_weeks       <- max(agg_weekly_users$week[agg_weekly_users$time_type == "impl_week"]) - 3
prev_four_weeks_end   <- last_four_weeks - 1
prev_four_weeks_start <- prev_four_weeks_end - 3

avg_weekly_users_4wk <- agg_weekly_users %>%
  filter(time_type == "impl_week", week >= last_four_weeks) %>%
  group_by(week) %>%
  summarise(n_users = sum(n_users), .groups = "drop") %>%
  summarise(avg = mean(n_users)) %>%
  pull(avg) %>%
  round()

avg_weekly_users_prev <- agg_weekly_users %>%
  filter(time_type == "impl_week",
         week >= prev_four_weeks_start,
         week <= prev_four_weeks_end) %>%
  group_by(week) %>%
  summarise(n_users = sum(n_users), .groups = "drop") %>%
  summarise(avg = mean(n_users)) %>%
  pull(avg) %>%
  round()

avg_sessions_4wk <- agg_avg_sessions %>%
  filter(time_type == "impl_week", week >= last_four_weeks) %>%
  group_by(week) %>%
  summarise(avg_sessions = mean(avg_sessions), .groups = "drop") %>%
  summarise(avg = mean(avg_sessions)) %>%
  pull(avg) %>%
  round(1)

avg_sessions_prev <- agg_avg_sessions %>%
  filter(time_type == "impl_week",
         week >= prev_four_weeks_start,
         week <= prev_four_weeks_end) %>%
  group_by(week) %>%
  summarise(avg_sessions = mean(avg_sessions), .groups = "drop") %>%
  summarise(avg = mean(avg_sessions)) %>%
  pull(avg) %>%
  round(1)

last_updated <- max(active_messages$time_corrected, na.rm = TRUE)

delta_label <- function(current, previous) {
  pct <- round((current - previous) / previous * 100)
  if (pct > 0) paste0("+", pct, "% vs prev 4 wks")
  else paste0(pct, "% vs prev 4 wks")
}

saveRDS(
  list(
    total_users            = total_users,
    avg_weekly_users_4wk   = avg_weekly_users_4wk,
    avg_weekly_users_delta = delta_label(avg_weekly_users_4wk, avg_weekly_users_prev),
    avg_sessions_4wk       = avg_sessions_4wk,
    avg_sessions_delta     = delta_label(avg_sessions_4wk, avg_sessions_prev),
    last_updated           = last_updated
  ),
  paste0(processed_data_path, "dashboard_scalars.rds")
)


# ── 7. Dashboard v2 data model (Rows 1–2 only) ──────────────────
# Trimmed port of Nigeria's dashboard_v2_data.rds (nigeria/05_dashboard.R,
# section 8) for scratch/row1_prototype in the analysis repo. No
# active_users_weekly_by_cluster (no real clusters here), no
# row3_scalars/row3_breakdown (no onboarding_schema equivalent for this
# country), no course engagement (course/module-flag columns are
# structurally all-zero here -- see the dashboard redesign plan).
# Survival and trajectory are reused from sections 2 and 4 above, same as
# Nigeria, so the two can't silently disagree on the same underlying fact.

incoming_v2 <- clean_message_data %>%
  filter(direction == "Incoming") %>%
  mutate(date = as.Date(date))

max_date_v2 <- max(incoming_v2$date, na.rm = TRUE)

# A week only counts once it's genuinely complete (start + 6 days has
# passed) -- matches the analysis repo's prepare_real_data.R / Nigeria's
# section 8, ported here so the pipeline regenerates it.
week_dates_v2 <- incoming_v2 %>%
  group_by(impl_week) %>%
  summarise(week_date = min(date, na.rm = TRUE), .groups = "drop")

complete_weeks_v2 <- week_dates_v2 %>%
  filter(week_date + 6 <= max_date_v2)

last_complete_impl_week_v2 <- max(complete_weeks_v2$impl_week)

active_users_weekly <- incoming_v2 %>%
  group_by(impl_week) %>%
  summarise(active = n_distinct(contact_id), .groups = "drop") %>%
  inner_join(complete_weeks_v2, by = "impl_week") %>%
  rename(week = impl_week) %>%
  arrange(week)

first_week_per_contact_v2 <- incoming_v2 %>%
  group_by(contact_id) %>%
  summarise(first_week = min(impl_week, na.rm = TRUE), .groups = "drop")

new_users_weekly <- first_week_per_contact_v2 %>%
  count(first_week, name = "new_users") %>%
  inner_join(complete_weeks_v2, by = c("first_week" = "impl_week")) %>%
  rename(week = first_week) %>%
  arrange(week)

# ── Row 1 scalars, anchored to the same last-complete-week the charts use ──
# sum(), not bare [] indexing: a week with zero new users has NO ROW in
# new_users_weekly (count() only emits observed values), so indexing with no
# match returns a zero-length vector rather than 0 -- crashed delta_label()
# downstream (if(pct >= 0) on numeric(0) -> "argument is of length zero").
# Nigeria's scale never hits an all-zero week, so the same bare-[] pattern
# there hasn't shown this, but the fix applies there too, for the same reason.
active_7d_v2     <- sum(active_users_weekly$active[active_users_weekly$week == last_complete_impl_week_v2])
new_users_7d_v2  <- sum(new_users_weekly$new_users[new_users_weekly$week == last_complete_impl_week_v2])
msgs_7d_v2       <- incoming_v2 %>% filter(impl_week == last_complete_impl_week_v2) %>% nrow()

active_prior_avg_v2 <- active_users_weekly %>%
  filter(week < last_complete_impl_week_v2) %>%
  arrange(desc(week)) %>%
  slice_head(n = 4) %>%
  summarise(avg = mean(active)) %>%
  pull(avg)

new_users_prior_avg_v2 <- new_users_weekly %>%
  filter(week < last_complete_impl_week_v2) %>%
  arrange(desc(week)) %>%
  slice_head(n = 4) %>%
  summarise(avg = mean(new_users)) %>%
  pull(avg)

scalars <- list(
  total_users         = n_distinct(incoming_v2$contact_id),
  active_7d           = active_7d_v2,
  active_prior_avg    = round(active_prior_avg_v2),
  # NA, not Inf/NaN, when the prior-4-week average is itself 0 -- a real
  # possibility at this country's scale. app.R's delta_label() renders NA
  # as "n/a" rather than crashing on it.
  active_delta_pct    = if (active_prior_avg_v2 == 0) NA_real_ else round((active_7d_v2 - active_prior_avg_v2) / active_prior_avg_v2 * 100, 1),
  new_users_7d        = new_users_7d_v2,
  new_users_prior_avg = round(new_users_prior_avg_v2),
  new_users_delta_pct = if (new_users_prior_avg_v2 == 0) NA_real_ else round((new_users_7d_v2 - new_users_prior_avg_v2) / new_users_prior_avg_v2 * 100, 1),
  incoming_msgs_7d    = msgs_7d_v2,
  max_date            = max_date_v2
)


# ── Row 2: retention cohort boxes ──────────────────────────────
# Reporting cohort: 29+ days' tenure, so every member has had the full
# Weeks-3-4 window to be observed. Same definitions as Nigeria's section 8.

contact_days_v2 <- incoming_v2 %>%
  distinct(contact_id, date)

first_date_by_contact_v2 <- contact_days_v2 %>%
  group_by(contact_id) %>%
  summarise(first_date = min(date), .groups = "drop")

contact_days_v2 <- contact_days_v2 %>%
  left_join(first_date_by_contact_v2, by = "contact_id") %>%
  mutate(day_lapse = as.numeric(date - first_date))

activity_summary_v2 <- contact_days_v2 %>%
  group_by(contact_id) %>%
  summarise(first_date = min(first_date), last_date = max(date), active_days = n_distinct(date), .groups = "drop") %>%
  mutate(
    days_since_last = as.numeric(max_date_v2 - last_date),
    tenure_days     = as.numeric(max_date_v2 - first_date),
    churned         = days_since_last >= 14,
    churn_date      = last_date + 14
  )

cohort_v2   <- activity_summary_v2 %>% filter(tenure_days >= 29)
n_cohort_v2 <- nrow(cohort_v2)

week1_active_v2 <- incoming_v2 %>%
  filter(contact_id %in% cohort_v2$contact_id, hrs_lapse > 6, hrs_lapse <= 168) %>%
  pull(contact_id) %>%
  n_distinct()

week2_active_v2 <- contact_days_v2 %>%
  filter(contact_id %in% cohort_v2$contact_id, day_lapse >= 8, day_lapse <= 14) %>%
  pull(contact_id) %>%
  n_distinct()

weeks3_4_active_v2 <- contact_days_v2 %>%
  filter(contact_id %in% cohort_v2$contact_id, day_lapse >= 15, day_lapse <= 28) %>%
  pull(contact_id) %>%
  n_distinct()

n_churned_7d_v2 <- activity_summary_v2 %>%
  filter(churn_date > max_date_v2 - 7, churn_date <= max_date_v2) %>%
  nrow()

row2_scalars <- list(
  n_cohort        = n_cohort_v2,
  week1_active    = week1_active_v2,
  week2_active    = week2_active_v2,
  weeks3_4_active = weeks3_4_active_v2,
  n_active_total  = n_distinct(incoming_v2$contact_id),
  n_churned_7d    = n_churned_7d_v2
)


# ── Row 2: survival curve and trajectory data, reused from sections 2/4 ──
# Only the "total" view is genuine (no real clusters) -- unlike Nigeria's
# survival_curve, which also keeps the "cluster" view.

survival_curve <- agg_survival %>%
  filter(view == "total") %>%
  transmute(view, cluster = cluster_label, time, estimate, conf.low, conf.high)

trajectory_data <- agg_user_traj %>%
  transmute(
    contact_id,
    day_lapse = round(week_lapse * 7),
    cum_msgs  = message_num,
    cluster   = as.character(cluster_group_label)
  )

saveRDS(
  list(
    scalars              = scalars,
    active_users_weekly  = active_users_weekly,
    new_users_weekly     = new_users_weekly,
    row2_scalars         = row2_scalars,
    survival_curve       = survival_curve,
    trajectory_data      = trajectory_data
  ),
  paste0(processed_data_path, "dashboard_v2_data.rds")
)
message("✓  dashboard_v2_data.rds — Rows 1-2 only (no clusters, no onboarding funnel)")

message("\n✓  All done. ", processed_data_path, " ready for app.R.")
