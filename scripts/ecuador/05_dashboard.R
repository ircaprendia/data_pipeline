# aprendIA Ecuador — Step 5: Pre-compute dashboard aggregations
# Outputs: data/ecuador/agg_*.rds, data/ecuador/dashboard_scalars.rds

#### Setup ####
library(tidyverse)
library(survival)
library(broom)

source("config/ecuador_config.R")

#### Load data ####
# Read the combined datasets from disk and take the Ecuador slice. Reading explicitly (not via
# in-memory objects) keeps this order-independent within run_all — each country reads the full
# combined file fresh and filters its own rows.
clean_message_data <- read_csv("data/clean_message_data.csv") %>% filter(country == "ecuador")
session_data_long  <- read_csv("data/session_data_long.csv")  %>% filter(country == "ecuador")
session_data       <- read_csv("data/session_data.csv")       %>% filter(country == "ecuador")
contacts_data      <- read_csv("data/contacts_data.csv")      %>% filter(country == "ecuador")

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

persistence_metrics <- session_data_long %>%
  filter(!is.na(session_start), in_msgs_per_session > 0) %>%
  mutate(date = as.Date(session_start)) %>%
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
    contacts_data %>% select(contact_id, group, cluster_group_label),
    by = "contact_id"
  ) %>%
  filter(!is.na(group), !is.na(cluster_group_label)) %>%
  mutate(strata_label = paste0(group, " · ", cluster_group_label))

# Niger has one population (no groups/clusters), so all views are the same curve.
# Compute total once and duplicate for schema consistency with Nigeria.
fit_total <- survfit(Surv(active_days, event) ~ 1, data = persistence_data)

base_survival <- broom::tidy(fit_total) %>%
  select(time, estimate, conf.low, conf.high)

agg_survival <- bind_rows(
  base_survival %>% mutate(view = "total",   strata_label = "Total",          group = NA_character_, cluster_group_label = NA_character_),
  base_survival %>% mutate(view = "4strata", strata_label = "Default · None", group = "Default",     cluster_group_label = "None"),
  base_survival %>% mutate(view = "group",   strata_label = "Default",        group = "Default",     cluster_group_label = NA_character_),
  base_survival %>% mutate(view = "cluster", strata_label = "None",           group = NA_character_, cluster_group_label = "None")
) %>%
  select(view, group, cluster_group_label, strata_label, time, estimate, conf.low, conf.high)

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

agg_user_traj <- clean_message_data %>%
  filter(!is.na(group)) %>%
  select(contact_id, day_lapse, message_num, last_message, group, cluster_label, cluster_group_label) %>%
  group_by(contact_id, day_lapse, group, cluster_label, cluster_group_label) %>%
  summarise(
    message_num  = max(message_num,  na.rm = TRUE),
    last_message = any(last_message, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(week_lapse = day_lapse / 7) %>%
  select(-day_lapse)

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

message("\n✓  All done. ", processed_data_path, " ready for app.R.")
