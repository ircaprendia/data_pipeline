# aprendIA Nigeria — Step 5: Pre-compute dashboard aggregations
# Run once after clustering to produce .rds files for the Shiny app.
# Outputs: data/nigeria/agg_*.rds, data/nigeria/dashboard_scalars.rds

#### Setup ####
library(tidyverse)
library(survival)
library(broom)

source("config/nigeria_config.R")
source("functions/clustering.R")

#### Load data ####
if (!exists("clean_message_data")) clean_message_data <- read_csv("data/nigeria/clean_message_data.csv")
if (!exists("session_data_long"))  session_data_long  <- read_csv("data/nigeria/session_data_long.csv")
if (!exists("session_data"))       session_data       <- read_csv("data/nigeria/session_data.csv")
if (!exists("contacts_data"))      contacts_data      <- read_csv("data/nigeria/contacts_data.csv")

# Re-apply ordered factors (lost on CSV round-trip)
clean_message_data <- apply_cluster_factor(clean_message_data)
session_data_long  <- apply_cluster_factor(session_data_long)
session_data       <- apply_cluster_factor(session_data)
contacts_data      <- apply_cluster_factor(contacts_data)

#### Derived dates ####
first_message_date <- as.Date(min(clean_message_data$time_corrected, na.rm = TRUE))

cutoff_date <- clean_message_data %>%
  filter(impl_week == max(impl_week, na.rm = TRUE)) %>%
  summarise(cutoff = max(as.Date(time_corrected))) %>%
  pull(cutoff)

latest_message <- max(clean_message_data$time_corrected, na.rm = TRUE)
complete_weeks <- floor(as.numeric(difftime(latest_message, first_message_date, units = "weeks")))

#### Active filters ####
# Excludes bot-initiated sessions with no user response; truncates to complete weeks
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

saveRDS(agg_weekly_users, "data/nigeria/agg_weekly_users.rds")
message("✓  agg_weekly_users.rds — ", nrow(agg_weekly_users), " rows")


# ── 2. Survival / persistence model ──────────────────────────
# FIXED 2026-09-21: population switched from session-level activity
# (session_data_long, in_msgs_per_session > 0) to message-level activity
# (direction == "Incoming" on clean_message_data directly) -- "active" is
# defined throughout this script's newer sections as "sent aprendIA a
# message", and this brings the persistence model in line with that,
# rather than counting a contact as active on a day the bot messaged them
# inside an otherwise-qualifying session. Event definition (14+ days
# quiet) is unchanged.

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
    contacts_data %>% select(contact_id, group, cluster_label),
    by = "contact_id"
  ) %>%
  filter(!is.na(group), !is.na(cluster_label)) %>%
  mutate(strata_label = paste0(group, " · ", cluster_label))

tidy_fit <- function(fit, view_label) {
  broom::tidy(fit) %>% mutate(view = view_label)
}

fit_4strata <- survfit(Surv(active_days, event) ~ strata_label,  data = persistence_data)
fit_group   <- survfit(Surv(active_days, event) ~ group,          data = persistence_data)
fit_cluster <- survfit(Surv(active_days, event) ~ cluster_label,  data = persistence_data)
fit_total   <- survfit(Surv(active_days, event) ~ 1,              data = persistence_data)

agg_survival <- bind_rows(

  tidy_fit(fit_4strata, "4strata") %>%
    mutate(
      strata_label  = str_remove(strata, "strata_label="),
      group         = str_extract(strata_label, "^[^·]+") %>% str_trim(),
      cluster_label = str_extract(strata_label, "[^·]+$")  %>% str_trim()
    ),

  tidy_fit(fit_group, "group") %>%
    mutate(
      group         = str_remove(strata, "group="),
      cluster_label = NA_character_,
      strata_label  = group
    ),

  tidy_fit(fit_cluster, "cluster") %>%
    mutate(
      cluster_label = str_remove(strata, "cluster_label="),
      group         = NA_character_,
      strata_label  = cluster_label
    ),

  tidy_fit(fit_total, "total") %>%
    mutate(
      strata        = "Total",
      strata_label  = "Total",
      group         = NA_character_,
      cluster_label = NA_character_
    )

) %>%
  select(view, group, cluster_label, strata_label, time, estimate, conf.low, conf.high)

saveRDS(agg_survival, "data/nigeria/agg_survival.rds")
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

saveRDS(agg_avg_sessions, "data/nigeria/agg_avg_sessions.rds")
message("✓  agg_avg_sessions.rds — ", nrow(agg_avg_sessions), " rows")


# ── 4. User trajectories ──────────────────────────────────────
# FIXED 2026-09-21: was counting both directions -- `message_num` here used
# to be the pre-existing column of that name, which the codebook defines as
# "sequential across all of a user's messages" (bot replies included, ~60%
# of volume), and `last_message` used to be the codebook's "TRUE if this is
# the user's most recent message" -- also both-directions, so a contact
# whose final message in the whole conversation was an outgoing bot reply
# had NO row left with last_message == TRUE once anything got filtered to
# Incoming, silently dropping their endpoint dot rather than erroring.
# Both are now recomputed from scratch on Incoming-only rows: message_num
# is a genuine cumulative count of messages the contact sent, and
# last_message flags the contact's most recent day with an incoming
# message, not the old both-directions flag re-used post-filter.

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

saveRDS(agg_user_traj, "data/nigeria/agg_user_traj.rds")
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
  mutate(
    prev_day = lag(impl_day),
    gap      = impl_day - prev_day
  ) %>%
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

saveRDS(agg_activation, "data/nigeria/agg_activation.rds")
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
  "data/nigeria/dashboard_scalars.rds"
)


# ── 7. Course engagement ──────────────────────────────────────

course_starts <- active_messages %>%
  filter(!is.na(impl_week), !is.na(group)) %>%
  filter(reading_mod1_start == 1 | maths_mod1_start == 1 | classroom_mod1_start == 1) %>%
  pivot_longer(
    cols      = c(reading_mod1_start, maths_mod1_start, classroom_mod1_start),
    names_to  = "course",
    values_to = "started"
  ) %>%
  filter(started == 1) %>%
  mutate(course = recode(course,
    reading_mod1_start   = "Reading",
    maths_mod1_start     = "Maths",
    classroom_mod1_start = "Classroom"
  )) %>%
  count(impl_week, course, group, cluster_label) %>%
  complete(
    impl_week = 1:complete_weeks,
    course    = c("Reading", "Maths", "Classroom"),
    nesting(group, cluster_label),
    fill = list(n = 0L)
  ) %>%
  mutate(week_date = first_message_date + weeks(impl_week - 1) + days(3))

module_progression <- active_sessions %>%
  filter(session_type == "Module progression", !is.na(subtype), !is.na(impl_week), !is.na(group)) %>%
  count(impl_week, subtype, group, cluster_label) %>%
  complete(
    impl_week = 1:complete_weeks,
    subtype   = c("Reading", "Maths", "Classroom"),
    nesting(group, cluster_label),
    fill = list(n = 0L)
  ) %>%
  mutate(week_date = first_message_date + weeks(impl_week - 1) + days(3))

saveRDS(
  list(course_starts = course_starts, module_progression = module_progression),
  "data/nigeria/agg_course_engagement.rds"
)
message("✓  agg_course_engagement.rds — ", nrow(course_starts), " course-start rows, ", nrow(module_progression), " module rows")


# ── 8. Dashboard v2 data model (Nigeria only) ──────────────────
# Row 1-3 aggregates for the redesigned dashboard (the dashboard prototype). "Active" = sent aprendIA a message -- built fresh
# against Incoming-only messages and real calendar-complete weeks rather
# than reusing agg_weekly_users (session-qualifying, both directions) or
# agg_activation (different churn/cohort logic), since those answer a
# related but different question. Survival and trajectory ARE reused from
# sections 2 and 4 above -- both were fixed in this same pass to already
# use the Incoming-only, message-level population v2 needs, so recomputing
# them a second time here would risk the two dashboards silently
# disagreeing on the same underlying fact.

incoming_v2 <- clean_message_data %>%
  filter(direction == "Incoming") %>%
  mutate(date = as.Date(date))

max_date_v2 <- max(incoming_v2$date, na.rm = TRUE)

# A week only counts once it's genuinely complete (start + 6 days has
# passed) -- otherwise the most recent bar/box reads as a real decline
# when it's really just a partial week. Matches the analysis repo's
# prepare_real_data.R, ported here so the pipeline regenerates it.
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

active_users_weekly_by_cluster <- incoming_v2 %>%
  filter(!is.na(cluster_group_label)) %>%
  mutate(cluster = as.character(cluster_group_label)) %>%
  group_by(impl_week, cluster) %>%
  summarise(active = n_distinct(contact_id), .groups = "drop") %>%
  inner_join(complete_weeks_v2, by = "impl_week") %>%
  rename(week = impl_week) %>%
  arrange(week, cluster)

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
# match returns a zero-length vector rather than 0. Nigeria's scale has never
# hit an all-zero week in practice (caught this via Niger/Ecuador crashing on
# it first, at their much smaller scale), but the same bare-[] pattern here
# carries the identical latent risk, so it's fixed here too.
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
  # NA, not Inf/NaN, when the prior-4-week average is itself 0. app.R's
  # delta_label() renders NA as "n/a" rather than crashing on it.
  active_delta_pct    = if (active_prior_avg_v2 == 0) NA_real_ else round((active_7d_v2 - active_prior_avg_v2) / active_prior_avg_v2 * 100, 1),
  new_users_7d        = new_users_7d_v2,
  new_users_prior_avg = round(new_users_prior_avg_v2),
  new_users_delta_pct = if (new_users_prior_avg_v2 == 0) NA_real_ else round((new_users_7d_v2 - new_users_prior_avg_v2) / new_users_prior_avg_v2 * 100, 1),
  incoming_msgs_7d    = msgs_7d_v2,
  max_date            = max_date_v2
)


# ── Row 2: retention cohort boxes ──────────────────────────────
# Reporting cohort: 29+ days' tenure, so every member has had the full
# Weeks-3-4 window to be observed. Week 1 starts at 6 hours (not day_lapse
# >= 1) to exclude the trivial "still replying in the opening exchange"
# case without excluding genuine same-calendar-day returns.

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

# Churned box: a trailing FLOW ("went quiet this period"), not a lifetime
# stock -- a contact churns 14 days after their last active day; counted
# here if that churn MOMENT falls in the trailing 7 days, matching the New
# Users box's own window so the two are directly comparable.
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

survival_curve <- agg_survival %>%
  filter(view %in% c("total", "cluster")) %>%
  transmute(view, cluster = cluster_label, time, estimate, conf.low, conf.high)

trajectory_data <- agg_user_traj %>%
  filter(!is.na(cluster_group_label)) %>%
  transmute(
    contact_id,
    day_lapse = round(week_lapse * 7),
    cum_msgs  = message_num,
    cluster   = as.character(cluster_group_label)
  )


# ── Row 3: onboarding completion funnel ─────────────────────────
# From the onboarding_schema long tables -- copied into data/nigeria/ from
# the analysis repository's onboarding schema tables (2026-09-21, straight
# copy, not yet a live pipeline step -- the backlog is a running audit, so
# this copy WILL drift stale; re-copying needs to become part of the
# pipeline run before this is relied on past the current session).

onb <- read_csv(
  "data/nigeria/onboarding_attempts.csv",
  col_select = c(contact_id, episode_number, source, completeness,
                  genuinely_never_onboarded, never_onboarded_category,
                  possible_bot_bug, furthest_question_reached,
                  prompt_version, extracted_date, is_audit_pass),
  col_types = cols(episode_number = col_character()),
  show_col_types = FALSE
)

# onboarding_attempts.csv is deliberately full history, per
# build_long_dataset.R's own header: every prompt_version ever run, PLUS
# audit-pass re-extractions kept for reliability checking rather than
# collapsed away -- "current" is meant to be resolved at query time, not
# stored. Audit passes exist to measure agreement against the real
# production call, so they must never compete with it here -- excluded
# up front, before any of the funnel logic below, rather than left to
# accidentally outvote a production row in a set-membership check.
onb <- onb %>% filter(!is_audit_pass)

known_rows   <- onb %>% filter(source == "known_episode")
nostart_rows <- onb %>% filter(source == "no_start_found")

known_contacts <- unique(known_rows$contact_id)

# The two populations are defined to be disjoint (known-episode = a detected
# episode boundary; no_start_found = none found) -- any contact that slips
# into both is counted as "started", since a real episode existing anywhere
# takes priority over a "never started" tag.
completed_contacts <- known_rows %>%
  filter(completeness %in% c("completed", "complete")) %>%
  pull(contact_id) %>%
  unique()

started_not_completed_contacts <- setdiff(known_contacts, completed_contacts)

never_started_contacts <- setdiff(
  nostart_rows %>% filter(genuinely_never_onboarded %in% c("TRUE", "yes")) %>% pull(contact_id) %>% unique(),
  known_contacts
)

n_completed  <- length(completed_contacts)
n_started_nc <- length(started_not_completed_contacts)
n_never      <- length(never_started_contacts)
n_row3_total <- n_completed + n_started_nc + n_never

# Bot-bug floor within "started, didn't complete": checks whether the FIELD
# AT THE POINT OF STALL (furthest_question_reached) has a structured,
# per-field missing_reason indicating a bot-caused block, rather than a
# free-text mention anywhere in the episode (which overstates the floor).
answers <- read_csv(
  "data/nigeria/onboarding_answers.csv",
  col_select = c(contact_id, episode_number, field, missing_reason,
                  prompt_version, extracted_date, is_audit_pass),
  col_types = cols(episode_number = col_character()),
  show_col_types = FALSE
)

# Same full-history-plus-audit-passes design as onboarding_attempts.csv above
# -- audit rows excluded first (213 of the 638 duplicate-key rows found at
# last check were audit passes, which must never outrank a production row),
# then the REMAINING duplication -- genuine reprocessing under more than one
# prompt_version, the older pass left in place rather than retired -- is
# resolved by keeping the latest extraction per key. This also resolves the
# join fanning out below, as a side effect rather than the goal.
answers <- answers %>%
  filter(!is_audit_pass) %>%
  group_by(contact_id, episode_number, field) %>%
  arrange(desc(extracted_date), desc(prompt_version), .by_group = TRUE) %>%
  slice_head(n = 1) %>%
  ungroup()

known_fields <- c("gender", "students_grade_level", "class_size", "instructional_materials_tier",
                   "materials_freetext", "learner_level_descriptor", "student_ages", "main_challenge",
                   "priority_outcome", "main_subject_taught")

# Audit passes already excluded (from onb, above). What's left is genuine
# reprocessing under more than one prompt_version -- 94 duplicate
# (contact_id, episode_number) groups found in known_episode rows at last
# check, 13 disagreeing on `completeness` itself between passes. Doesn't
# affect n_completed/n_started_nc/n_never above (those are built from set
# membership over contact_id, not row counts, so they're already robust to
# duplicates), but it does feed this join row-for-row -- keep the latest
# extraction per key so it doesn't fan out.
started_nc_rows <- known_rows %>%
  filter(contact_id %in% started_not_completed_contacts) %>%
  group_by(contact_id, episode_number) %>%
  arrange(desc(extracted_date), desc(prompt_version), .by_group = TRUE) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  mutate(
    fq_norm = sub(" [(].*$", "", furthest_question_reached),
    fq_norm = if_else(fq_norm %in% known_fields, fq_norm, NA_character_)
  )

stall_joined <- started_nc_rows %>%
  left_join(answers, by = c("contact_id", "episode_number", "fq_norm" = "field"))

bot_caused_reasons <- c("answered_but_rejected_by_bot", "skipped_by_bot_error", "derailed_by_bot_bug")

stall_joined <- stall_joined %>%
  mutate(bot_caused_at_stall = missing_reason %in% bot_caused_reasons)

n_bot_bug_floor <- stall_joined %>%
  filter(bot_caused_at_stall) %>%
  pull(contact_id) %>%
  n_distinct()

n_stall_unresolved <- length(started_not_completed_contacts) -
  (stall_joined %>% filter(!is.na(fq_norm)) %>% pull(contact_id) %>% n_distinct())

row3_scalars <- list(
  n_total            = n_row3_total,
  n_completed        = n_completed,
  n_started_nc       = n_started_nc,
  n_never            = n_never,
  n_bot_bug_floor    = n_bot_bug_floor,
  n_started_nc_denom = n_started_nc,
  n_stall_unresolved = n_stall_unresolved
)

# Breakdown chart: why onboarding never happened, among never-started
# contacts. never_onboarded_category has some free-text contamination --
# normalize to the leading category token, bucket anything unrecognized as
# "other / uncategorized" rather than letting it skew a real category's count.
known_categories <- c("consent_gate_bypassed", "too_few_messages", "bypassed_via_adhoc_qa",
                        "stalled_at_consent", "used_confound_feature", "went_straight_to_course",
                        "affirmed_no_access_granted", "genuine_trigger_boilerplate_reuse")

row3_breakdown <- nostart_rows %>%
  filter(contact_id %in% never_started_contacts) %>%
  mutate(
    category = sub(" \\(.*$", "", never_onboarded_category),
    category = if_else(category %in% known_categories, category, "other / uncategorized")
  ) %>%
  count(category, name = "n") %>%
  arrange(desc(n))


saveRDS(
  list(
    scalars                        = scalars,
    active_users_weekly            = active_users_weekly,
    active_users_weekly_by_cluster = active_users_weekly_by_cluster,
    new_users_weekly                = new_users_weekly,
    row2_scalars                   = row2_scalars,
    survival_curve                 = survival_curve,
    trajectory_data                = trajectory_data,
    row3_scalars                   = row3_scalars,
    row3_breakdown                 = row3_breakdown
  ),
  "data/nigeria/dashboard_v2_data.rds"
)
message("✓  dashboard_v2_data.rds — Nigeria only, dashboard v2 data model")

message("\n✓  All done. data/nigeria/ ready for app.R.")
