# ============================================================
# dash_visualisations.R
# Five chart functions for the aprendIA usage dashboard.
#
# Usage:
#   source("functions/dash_visualisations.R")
#   plot_dash_weekly(agg_weekly_users)
#   plot_dash_sessions(agg_avg_sessions)
#   plot_dash_activation(agg_activation)
#   plot_dash_persistence(agg_survival)
#   plot_dash_trajectories(agg_user_traj)
#
# Each function takes a pre-aggregated data frame as its first
# argument and returns a ggplot object. Pass directly to
# renderPlot() in the Shiny app.
# ============================================================

library(tidyverse)
library(scales)
library(showtext)
library(ggiraph)

font_add_google("Overpass",    "Overpass")
font_add_google("Inter",       "Inter")
font_add_google("Roboto Mono", "Roboto Mono")
showtext_auto()
showtext_opts(dpi = 150)


# ── Palette ───────────────────────────────────────────────────
palette_default <- "#3CC98A"

palette_course <- c("Reading" = "#3CC98A", "Maths" = "#17B8CC", "Classroom" = "#6A5CE8")

palette_group <- c(
  "Pilot"    = "#17B8CC",
  "Scale-up" = "#3CC98A"
)

palette_cluster <- c(
  "Power users"      = "#6A5CE8",
  "Occasional users" = "#17B8CC"
)

palette_strata <- c(
  "Pilot · Power users"         = "#6A5CE8",
  "Pilot · Occasional users"    = "#17B8CC",
  "Scale-up · Power users"      = "#3CC98A",
  "Scale-up · Occasional users" = "#F5A623"
)

build_strata_pal <- function(strata_labels) {
  s <- sort(unique(strata_labels))
  if (length(s) == 1 && !any(str_detect(s, "·"))) {
    if (s %in% names(palette_group))   return(setNames(palette_group[s],   s))
    if (s %in% names(palette_cluster)) return(setNames(palette_cluster[s], s))
    return(setNames(palette_default, s))
  }
  if (all(s %in% names(palette_strata))) return(palette_strata[s])
  if (!any(str_detect(s, "·"))) {
    if (all(s %in% names(palette_group)))   return(palette_group[s])
    if (all(s %in% names(palette_cluster))) return(palette_cluster[s])
  }
  fallback <- colorRampPalette(c("#17B8CC", "#3CC98A", "#6A5CE8", "#F5A623"))
  setNames(fallback(length(s)), s)
}

col_fill_helper <- function(facet_rows, facet_cols = NULL) {
  if (is.null(facet_rows) && is.null(facet_cols)) return(palette_default)
  return(NULL)
}


# ── Shared theme ──────────────────────────────────────────────
dash_theme <- function(base_size = 18) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.background  = element_rect(fill = "#F3F5F7", colour = NA),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = "#D9E2EA", linewidth = 0.3),
      axis.title.y     = element_text(family = "Inter",       size = base_size - 2, margin = margin(r = 12)),
      axis.title.x     = element_text(family = "Inter",       size = base_size - 2, margin = margin(t = 12)),
      axis.text.y      = element_text(family = "Roboto Mono", size = base_size - 4),
      axis.text.x      = element_text(family = "Roboto Mono", size = base_size - 4),
      strip.text       = element_text(family = "Inter",       size = base_size,     face = "bold"),
      legend.title     = element_blank(),
      legend.text      = element_text(family = "Inter",       size = base_size - 2),
      legend.position  = "right",
      legend.key.size  = unit(0.75, "lines")
    )
}


# ── Internal helper: smart bar labels ─────────────────────────
# Adds label_text column — only labels bars above threshold_high
# or below threshold_low, relative to the max within each facet group.
add_bar_labels <- function(pd, value_col, facet_by,
                           threshold_high = 0.8,
                           threshold_low  = 0.1) {
  
  grouping_vars <- if (!is.null(facet_by)) facet_by else character(0)
  
  if (length(grouping_vars) > 0) {
    pd %>%
      group_by(across(all_of(grouping_vars))) %>%
      mutate(
        max_val    = max(.data[[value_col]], na.rm = TRUE),
        show_label = .data[[value_col]] > max_val * threshold_high |
          .data[[value_col]] < max_val * threshold_low,
        label_text = if_else(show_label, scales::comma(round(.data[[value_col]])), "")
      ) %>%
      ungroup()
  } else {
    pd %>%
      mutate(
        max_val    = max(.data[[value_col]], na.rm = TRUE),
        show_label = .data[[value_col]] > max_val * threshold_high |
          .data[[value_col]] < max_val * threshold_low,
        label_text = if_else(show_label, scales::comma(round(.data[[value_col]])), "")
      )
  }
}


# ══════════════════════════════════════════════════════════════
# 1. Weekly active users
# ══════════════════════════════════════════════════════════════
#
# Arguments:
#   data                 agg_weekly_users — cols: impl_week,
#                        week_date, group, cluster_label, n_users
#   facet_by             NULL, "group", or "cluster_label"
#   free_scales          use free y-scales when faceting (default TRUE)
#   week_range           integer vector e.g. 1:24, or NULL for all
#   use_dates            if TRUE, use week_date on x-axis instead of
#                        impl_week (default FALSE)
#   add_labels           show bar-top labels (default TRUE)
#   label_threshold_high only label bars above this % of facet max
#   label_threshold_low  only label bars below this % of facet max
#
# Returns: ggplot object

plot_dash_weekly <- function(
    data,
    time_var             = "impl_week",
    facet_var            = NULL,
    facet_rows           = NULL,
    facet_cols           = NULL,
    free_scales          = TRUE,
    week_range           = NULL,
    as_percentage        = FALSE,
    add_labels           = TRUE,
    use_dates            = FALSE,
    label_threshold_high = 0.8,
    label_threshold_low  = 0.1,
    fill_colour          = NULL,
    x_label              = NULL,
    y_label              = NULL,
    base_size  = 11,   
    label_size = 2.6
) {
  
  data <- data %>% filter(time_type == time_var)
  
  if (is.null(y_label)) {
    y_label <- if_else(as_percentage, "% of week-1 users", "Unique users")
  }
  if (is.null(x_label)) {
    x_label <- case_when(
      use_dates & time_var == "impl_week" ~ "Date",
      time_var == "message_week" ~ "Week since joining",
      TRUE ~ "Programme week"
    )
  }
  
  if (as_percentage && time_var == "impl_week") {
    warning("as_percentage is most meaningful with message_week.")
  }
  
  if (!is.null(facet_var)) {
    facet_rows <- facet_var
    facet_cols <- NULL
  }
  
  if (!is.null(week_range)) {
    data <- data %>% filter(week %in% week_range)
  }
  
  # Build grouping vars
  # Always use "week" as the time column — time_var is just the filter
  group_vars <- "week"
  if (use_dates && time_var == "impl_week") group_vars <- c(group_vars, "week_date")
  if (!is.null(facet_rows)) group_vars <- c(group_vars, facet_rows)
  if (!is.null(facet_cols)) group_vars <- c(group_vars, facet_cols)
  
  plot_data <- data %>%
    filter(if (!is.null(facet_rows)) !is.na(.data[[facet_rows]]) else TRUE) %>%
    filter(if (!is.null(facet_cols)) !is.na(.data[[facet_cols]]) else TRUE) %>%
    group_by(across(all_of(group_vars))) %>%
    summarise(total_users = sum(n_users), .groups = "drop")
  
  grouping_vars <- setdiff(group_vars, c("week", "week_date"))
  
  # Convert to percentage
  if (as_percentage) {
    if (length(grouping_vars) > 0) {
      plot_data <- plot_data %>%
        group_by(across(all_of(grouping_vars))) %>%
        arrange(week) %>%
        mutate(
          week_one_users = as.numeric(first(total_users)),
          total_users    = as.numeric(total_users) / week_one_users
        ) %>%
        ungroup()
    } else {
      plot_data <- plot_data %>%
        arrange(week) %>%
        mutate(
          week_one_users = as.numeric(first(total_users)),
          total_users    = as.numeric(total_users) / week_one_users
        )
    }
  }
  
  x_var_use <- if (use_dates && time_var == "impl_week") "week_date" else "week"

  facet_active <- if (!is.null(facet_rows)) facet_rows else facet_cols

  # Tooltip: week/date label + exact value. Each bar covers a full week, so a
  # single date would misread as a point in time — "week commencing" makes the
  # span explicit. week_date is the week's midpoint (offset by 3 days, so the
  # bar centres on the date axis) — subtract 3 days back to the actual start.
  format_no_pad <- function(date) trimws(format(date, "%e %b %Y"))
  week_label <- if (use_dates && time_var == "impl_week") {
    paste("w/c", format_no_pad(plot_data$week_date - days(3)))
  } else {
    paste("Week", plot_data$week)
  }
  value_label <- if (as_percentage) {
    paste0(percent(plot_data$total_users, accuracy = 1), " of week 1")
  } else {
    paste(scales::comma(round(plot_data$total_users)), "unique users")
  }

  if (is.null(facet_active)) {
    plot_data <- plot_data %>%
      mutate(tooltip = paste0("<b>", week_label, "</b><br>", value_label))
    p <- plot_data %>%
      ggplot(aes(x = .data[[x_var_use]], y = total_users)) +
      geom_col_interactive(
        aes(tooltip = tooltip, data_id = .data[[x_var_use]]),
        fill = palette_default, alpha = 0.85
      )
  } else {
    pal_use <- if (facet_active == "group") palette_group else palette_cluster
    plot_data <- plot_data %>%
      mutate(tooltip = paste0("<b>", week_label, "</b><br>", .data[[facet_active]], "<br>", value_label))
    p <- plot_data %>%
      ggplot(aes(x = .data[[x_var_use]], y = total_users,
                 fill = .data[[facet_active]])) +
      geom_col_interactive(
        aes(tooltip = tooltip, data_id = paste(.data[[x_var_use]], .data[[facet_active]])),
        alpha = 0.9
      ) +
      scale_fill_manual(values = pal_use)
  }
  
#  if (!is.null(fill_colour)) {
#    p <- plot_data %>%
#      ggplot(aes(x = .data[[x_var_use]], y = total_users)) +
#      geom_col(fill = fill_colour, alpha = 0.85)
#  } else {
#    n_weeks  <- n_distinct(plot_data$week)
#    pal_week <- green_ramp(n_weeks)
#    p <- plot_data %>%
#      ggplot(aes(x = .data[[x_var_use]], y = total_users, fill = factor(week))) +
#      geom_col(alpha = 0.9) +
#      scale_fill_manual(values = pal_week)
#  }
  
  p <- p +
    labs(x = x_label, y = y_label) +
    dash_theme(base_size = base_size) +
    theme(legend.position = "none")
  
  if (as_percentage) {
    p <- p + scale_y_continuous(
      labels = percent,
      breaks = c(0, 0.25, 0.5, 0.75, 1),
      limits = c(0, 1.05),
      expand = expansion(mult = c(0, 0.05))
    )
  } else {
    p <- p + scale_y_continuous(labels = scales::comma, expand = expansion(mult = c(0, 0.12)))
  }

  if (use_dates) {
    p <- p + scale_x_date(date_breaks = "4 weeks", date_labels = "%e %b", expand = expansion(mult = c(0.02, 0.03)))
  } else {
    p <- p + scale_x_continuous(breaks = scales::breaks_width(5), expand = expansion(mult = c(0.02, 0)))
  }

  if (!is.null(facet_rows) && !is.null(facet_cols)) {
    scales_type <- if_else(free_scales, "free_y", "fixed")
    p <- p + facet_grid(rows = vars(.data[[facet_rows]]),
                        cols = vars(.data[[facet_cols]]),
                        scales = scales_type)
  } else if (!is.null(facet_rows)) {
    scales_type <- if_else(free_scales, "free_y", "fixed")
    p <- p + facet_grid(rows = vars(.data[[facet_rows]]), scales = scales_type)
  } else if (!is.null(facet_cols)) {
    scales_type <- if_else(free_scales, "free_y", "fixed")
    p <- p + facet_grid(cols = vars(.data[[facet_cols]]), scales = scales_type)
  }
  
  p
}


# ══════════════════════════════════════════════════════════════
# 2. User persistence (Kaplan-Meier survival curve)
# ══════════════════════════════════════════════════════════════
#
# Arguments:
#   data         agg_survival — cols: view, group,
#                cluster_label, strata_label, time,
#                estimate, conf.low, conf.high
#   view         "4strata", "group", "cluster", or "total"
#   show_ribbon  show confidence interval ribbon (default TRUE)
#   x_max        clip x-axis at this many active days (NULL = auto)
#
# Returns: ggplot object

plot_dash_persistence <- function(
    data,
    view = "4strata",
    show_ribbon = TRUE,
    x_max = NULL,
    base_size = 11
) {

  pd <- data %>% filter(view == !!view)

  if (nrow(pd) == 0) { message("No data."); return(NULL) }
  
  if (is.null(x_max)) {
    x_max <- pd %>%
      filter(estimate >= 0.05) %>%
      pull(time) %>%
      max(na.rm = TRUE)
  }
  pd <- pd %>% filter(time <= x_max)
  
  present <- sort(unique(pd$strata_label))
  pal_use <- build_strata_pal(present)

  # Tooltip: modelled value + CI at the hovered time. geom_ribbon/geom_step
  # only accept one tooltip for the whole path, so an invisible point per
  # time point gives a per-point hover target (same idiom as the daily
  # active-users stock chart). Heading only needed when more than one
  # stratum is on the plot.
  pd <- pd %>%
    mutate(
      tooltip = paste0(
        if (length(present) > 1) paste0("<b>", strata_label, "</b><br>") else "",
        "Day ", time, "<br>",
        percent(estimate, accuracy = 1), " still engaging<br>",
        "95% CI: ", percent(conf.low, accuracy = 1), "–", percent(conf.high, accuracy = 1)
      )
    )

  p <- pd %>%
    ggplot(aes(
      x      = time,
      y      = estimate,
      colour = strata_label,
      fill   = strata_label,
      group  = strata_label
    ))

  if (show_ribbon) {
    p <- p + geom_ribbon(
      aes(ymin = conf.low, ymax = conf.high),
      alpha = 0.15, colour = NA
    )
  }

  p <- p +
    geom_step(linewidth = 0.2) +
    geom_point_interactive(
      aes(tooltip = tooltip, data_id = paste(strata_label, time)),
      alpha = 0.02, size = 2
    ) +
    scale_colour_manual(values = pal_use) +
    scale_fill_manual(  values = pal_use) +
    scale_x_continuous(breaks = scales::breaks_width(7)) +
    scale_y_continuous(
      labels = percent_format(accuracy = 1),
      limits = c(0, 1.05),
      expand = expansion(mult = c(0, 0.03))
    ) +
    labs(x = "Number of active days", y = "% still engaging") +
    dash_theme(base_size = base_size) +
    theme(legend.position = if (length(present) <= 1) "none" else "top")

  p
}


# ══════════════════════════════════════════════════════════════
# 3. Average sessions per active user per week
# ══════════════════════════════════════════════════════════════
# Takes pre-aggregated agg_avg_sessions (impl_week, message_week,
# group, cluster_group_label, avg_sessions, week_date).
#
# Arguments:
#   data                 agg_avg_sessions
#   time_var             "impl_week" or "message_week"
#   facet_var            NULL, "group", or "cluster_group_label"
#   facet_direction      "rows" or "cols"
#   free_scales          use free y-scales when faceting
#   week_range           integer vector or NULL for all
#   use_dates            use week_date on x-axis (impl_week only)
#   add_labels           show bar-top labels
#   label_decimals       decimal places for labels (default 1)
#   label_threshold_high only label bars above this % of max
#   label_threshold_low  only label bars below this % of max
#   fill_colour          NULL = green gradient, or solid colour
#   x_label              x-axis label
#   y_label              y-axis label
#
# Returns: ggplot object

plot_dash_sessions <- function(
    data,
    time_var             = "impl_week",
    facet_var            = NULL,
    facet_direction      = "rows",
    free_scales          = TRUE,
    week_range           = NULL,
    use_dates            = FALSE,
    add_labels           = TRUE,
    label_decimals       = 1,
    label_threshold_high = 0.8,
    label_threshold_low  = 0.1,
    fill_colour          = NULL,
    x_label              = NULL,
    y_label              = "Avg sessions per active user",
    base_size  = 11,   
    label_size = 2.6
) {
  
  # Filter to correct time type
  data <- data %>% filter(time_type == time_var)
  
  if (!is.null(week_range)) {
    data <- data %>% filter(week %in% week_range)
  }
  
  data <- data %>% filter(!is.na(week))
  
  # Build grouping vars — always use "week" not time_var
  group_vars <- "week"
  if (use_dates && time_var == "impl_week") group_vars <- c(group_vars, "week_date")
  if (!is.null(facet_var)) group_vars <- c(group_vars, facet_var)
  
  plot_data <- data %>%
    filter(if (!is.null(facet_var)) !is.na(.data[[facet_var]]) else TRUE) %>%
    group_by(across(all_of(group_vars))) %>%
    summarise(avg_sessions = mean(avg_sessions), .groups = "drop")

  x_var_use <- if (use_dates && time_var == "impl_week") "week_date" else "week"

  if (is.null(x_label)) {
    x_label <- case_when(
      use_dates & time_var == "impl_week" ~ "Date",
      time_var == "message_week" ~ "Week since joining",
      TRUE ~ "Programme week"
    )
  }

  # Tooltip: week/date label + exact value. week_date is the week's midpoint
  # (offset by 3 days, so the bar centres on the date axis) — subtract 3 days
  # back to the actual start.
  format_no_pad <- function(date) trimws(format(date, "%e %b %Y"))
  week_label <- if (use_dates && time_var == "impl_week") {
    paste("w/c", format_no_pad(plot_data$week_date - days(3)))
  } else {
    paste("Week", plot_data$week)
  }
  value_label <- paste(round(plot_data$avg_sessions, label_decimals), "avg sessions per active user")

  if (is.null(facet_var)) {
    plot_data <- plot_data %>%
      mutate(tooltip = paste0("<b>", week_label, "</b><br>", value_label))
    p <- plot_data %>%
      ggplot(aes(x = .data[[x_var_use]], y = avg_sessions)) +
      geom_col_interactive(
        aes(tooltip = tooltip, data_id = .data[[x_var_use]]),
        fill = palette_default, alpha = 0.85
      ) +
      labs(x = x_label, y = y_label) +
      dash_theme(base_size = base_size) +
      theme(legend.position = "none")
  } else {
    pal_use <- if (facet_var == "group") palette_group else palette_cluster
    plot_data <- plot_data %>%
      mutate(tooltip = paste0("<b>", week_label, "</b><br>", .data[[facet_var]], "<br>", value_label))
    p <- plot_data %>%
      ggplot(aes(x = .data[[x_var_use]], y = avg_sessions,
                 fill = .data[[facet_var]])) +
      geom_col_interactive(
        aes(tooltip = tooltip, data_id = paste(.data[[x_var_use]], .data[[facet_var]])),
        alpha = 0.9
      ) +
      scale_fill_manual(values = pal_use) +
      labs(x = x_label, y = y_label) +
      dash_theme(base_size = base_size) +
      theme(legend.position = "none")
  }

  p <- p + scale_y_continuous(labels = scales::comma, expand = expansion(mult = c(0, 0.12)))

  if (use_dates) {
    p <- p + scale_x_date(date_breaks = "4 weeks", date_labels = "%e %b", expand = expansion(mult = c(0.02, 0.03)))
  } else {
    p <- p + scale_x_continuous(breaks = scales::breaks_width(5), expand = expansion(mult = c(0.02, 0)))
  }

  if (!is.null(facet_var)) {
    scales_type <- if_else(free_scales, "free_y", "fixed")
    if (facet_direction == "rows") {
      p <- p + facet_grid(rows = vars(.data[[facet_var]]), scales = scales_type)
    } else {
      p <- p + facet_grid(cols = vars(.data[[facet_var]]), scales = scales_type)
    }
  }
  
  p
}


# ══════════════════════════════════════════════════════════════
# 4. Engagement trajectories (spaghetti plot)
# ══════════════════════════════════════════════════════════════
#
# Arguments:
#   data          agg_user_traj — cols: contact_id, week_lapse,
#                 group, cluster_group_label, message_num,
#                 last_message
#   n_sample      number of users to sample per stratum (default 50)
#   show_dots     show last-message dots (default TRUE)
#   seed          random seed for reproducible sampling (default 42)
#
# Returns: ggplot object

plot_dash_trajectories <- function(
    data,
    n_sample = 50,
    show_dots = TRUE,
    seed = 42,
    facet = "group",     # "group", "4way", "cluster" or "none"
    base_size = 11,
    label_size = 2.6
) {

  pd <- data %>%
    mutate(strata_label = paste0(group, " · ", cluster_label))

  if (nrow(pd) == 0) { message("No data."); return(NULL) }
  
  # Sample n_sample users per stratum for legibility
  set.seed(seed)
  sampled_users <- pd %>%
    distinct(contact_id, strata_label) %>%
    group_by(strata_label) %>%
    slice_sample(n = n_sample, replace = FALSE) %>%
    ungroup()
  
  pd <- pd %>% filter(contact_id %in% sampled_users$contact_id)
  
  # Build palette from present strata
  present  <- sort(unique(pd$strata_label))
  pal_use  <- build_strata_pal(present)
  
  # Tooltip: journey summary for the endpoint dot only — the lines themselves
  # stay static (hundreds of overlapping lines make hover a poor target).
  # week_lapse is a fractional week count — split into whole weeks + days
  # rather than showing a decimal.
  last_pts <- pd %>%
    filter(last_message == TRUE) %>%
    mutate(
      total_days_lapse = round(week_lapse * 7),
      whole_weeks      = total_days_lapse %/% 7,
      remaining_days   = total_days_lapse %% 7,
      duration_label   = paste0(
        whole_weeks, " ", if_else(whole_weeks == 1, "wk", "wks"),
        " and ", remaining_days, " ", if_else(remaining_days == 1, "day", "days")
      ),
      tooltip = paste0(
        if (length(present) > 1) paste0("<b>", strata_label, "</b><br>") else "",
        scales::comma(message_num), " msgs over ", duration_label
      )
    )

  p <- pd %>%
    ggplot(aes(
      x      = week_lapse,
      y      = message_num,
      group  = contact_id,
      colour = strata_label
    )) +
    geom_line(alpha = 0.25, linewidth = 0.45) +
    scale_colour_manual(values = pal_use, name = NULL)

  if (show_dots) {
    p <- p + geom_point_interactive(
      data = last_pts,
      aes(colour = strata_label, tooltip = tooltip, data_id = contact_id),
      alpha = 0.6,
      size  = 1.5
    )
  }
  
  p <- p +
    scale_x_continuous(
#      breaks = scales::breaks_width(14),
      expand = expansion(mult = c(0.01, 0.02))
    ) +
    scale_y_continuous(labels = scales::comma, expand = expansion(mult = c(0, 0.05))) +
    labs(x = "Weeks since first message", y = "Cumulative messages") +
    dash_theme(base_size = base_size) +
    theme(legend.position = if (length(present) <= 1) "none" else "top")

  if (facet == "group") {
    p <- p + facet_grid(cols = vars(group))
  } else if (facet == "cluster") {
    p <- p + facet_grid(cols = vars(cluster_label))
  } else if (facet == "4way") {
    p <- p + facet_grid(rows = vars(cluster_label), cols = vars(group))
  }

  p
}


# ══════════════════════════════════════════════════════════════
# 6. Course engagement — starts (stacked columns)
# ══════════════════════════════════════════════════════════════
#
# Arguments:
#   data       course_starts df: impl_week, week_date, which_course,
#              group, cluster_label, n
#   cohort     "All", or a group/cluster label to filter to
#   use_dates  use week_date on x-axis instead of impl_week
#
# Returns: ggplot — legend centred at top (intended for top panel)

plot_dash_course_starts <- function(data, cohort = "All", use_dates = FALSE,
                                    x_limits = NULL, base_size = 11) {

  pd <- .filter_course_cohort(data, cohort, group_col = "group", cluster_col = "cluster_label") %>%
    group_by(impl_week, week_date, course) %>%
    summarise(n = sum(n, na.rm = TRUE), .groups = "drop") %>%
    mutate(course = factor(course, levels = c("Reading", "Maths", "Classroom")))

  x_var <- if (use_dates) "week_date" else "impl_week"

  # Tooltip: bar-level breakdown across all three courses, shown regardless of
  # which segment is hovered. week_date is the week's midpoint (offset by 3
  # days, so the bar centres on the date axis) — subtract 3 days for the
  # true week start.
  format_no_pad <- function(date) trimws(format(date, "%e %b %Y"))
  bar_tooltips <- pd %>%
    arrange(course) %>%
    group_by(impl_week, week_date) %>%
    summarise(
      tooltip = paste0(
        "<b>", if (use_dates) paste("w/c", format_no_pad(first(week_date) - days(3))) else paste("Week", first(impl_week)), "</b><br>",
        paste0(
          "<span style='color:", palette_course[as.character(course)], ";font-weight:600;'>",
          course, "</span>: ", scales::comma(n),
          collapse = "<br>"
        )
      ),
      .groups = "drop"
    )

  pd <- pd %>% left_join(bar_tooltips, by = c("impl_week", "week_date"))

  p <- pd %>%
    ggplot(aes(x = .data[[x_var]], y = n, fill = course)) +
    geom_col_interactive(
      aes(tooltip = tooltip, data_id = .data[[x_var]]),
      alpha = 0.85
    ) +
    scale_fill_manual(values = palette_course, name = NULL) +
    scale_y_continuous(labels = scales::comma, expand = expansion(mult = c(0, 0.1))) +
    labs(x = NULL, y = "Module 1 starts") +
    dash_theme(base_size = base_size) +
    theme(
      legend.position  = "top",
      legend.justification = "center",
      axis.text.x      = element_blank(),
      axis.ticks.x     = element_blank()
    )

  # coord_cartesian() clips the *view* to x_limits without dropping rows —
  # scale_..(limits=) sets out-of-range rows to NA and drops them, which
  # breaks ggiraph's tooltip/data-id attribute mapping for the whole layer.
  if (use_dates) {
    p + scale_x_date(date_breaks = "4 weeks", date_labels = "%e %b", expand = expansion(mult = c(0.02, 0))) +
      coord_cartesian(xlim = x_limits)
  } else {
    p + scale_x_continuous(breaks = scales::breaks_width(5), expand = expansion(mult = c(0.02, 0))) +
      coord_cartesian(xlim = x_limits)
  }
}


# ══════════════════════════════════════════════════════════════
# 7. Course engagement — module progression over time (stacked area)
# ══════════════════════════════════════════════════════════════
#
# Arguments:
#   data       module_progression df: impl_week, week_date, subtype,
#              group, cluster_label, n
#   cohort     "All", or a group/cluster label to filter to
#   use_dates  use week_date on x-axis instead of impl_week
#
# Returns: ggplot — no legend (shared with course starts panel above)

plot_dash_module_time <- function(data, cohort = "All", use_dates = FALSE,
                                  x_limits = NULL, base_size = 11) {

  pd <- .filter_course_cohort(data, cohort, group_col = "group", cluster_col = "cluster_label") %>%
    group_by(impl_week, week_date, subtype) %>%
    summarise(n = sum(n, na.rm = TRUE), .groups = "drop") %>%
    mutate(subtype = factor(subtype, levels = c("Reading", "Maths", "Classroom")))

  x_var <- if (use_dates) "week_date" else "impl_week"
  x_lab <- if (use_dates) "Date" else "Programme week"

  # Tooltip: hover band spanning the full stacked height per week, showing the
  # breakdown across all three subtypes (same pattern as course starts).
  # geom_area only accepts one tooltip for the whole path, so an invisible
  # geom_rect per week gives a per-week hover target. week_date is the week's
  # midpoint (offset by 3 days) — subtract back to the true week start.
  format_no_pad <- function(date) trimws(format(date, "%e %b %Y"))
  half_width <- if (use_dates) 3.15 else 0.45
  band_tooltips <- pd %>%
    arrange(subtype) %>%
    group_by(impl_week, week_date) %>%
    summarise(
      total = sum(n),
      tooltip = paste0(
        "<b>", if (use_dates) paste("w/c", format_no_pad(first(week_date) - days(3))) else paste("Week", first(impl_week)), "</b><br>",
        paste0(
          "<span style='color:", palette_course[as.character(subtype)], ";font-weight:600;'>",
          subtype, "</span>: ", scales::comma(n),
          collapse = "<br>"
        )
      ),
      .groups = "drop"
    )

  p <- pd %>%
    ggplot(aes(x = .data[[x_var]], y = n, fill = subtype, colour = subtype, group = subtype)) +
    geom_area(position = "stack", alpha = 0.5, colour = NA) +
    geom_line(position = "stack", linewidth = 0.2) +
    geom_rect_interactive(
      data        = band_tooltips,
      aes(xmin = .data[[x_var]] - half_width, xmax = .data[[x_var]] + half_width,
          ymin = 0, ymax = total, tooltip = tooltip, data_id = .data[[x_var]]),
      alpha       = 0.02,
      inherit.aes = FALSE
    ) +
    scale_fill_manual(  values = palette_course, name = NULL) +
    scale_colour_manual(values = palette_course, name = NULL) +
    scale_y_continuous(labels = scales::comma, expand = expansion(mult = c(0, 0.08))) +
    labs(x = x_lab, y = "Sessions") +
    dash_theme(base_size = base_size) +
    theme(legend.position = "none")

  # coord_cartesian() clips the *view* to x_limits without dropping rows —
  # scale_..(limits=) sets out-of-range rows to NA and drops them, which
  # breaks ggiraph's tooltip/data-id attribute mapping for the whole layer.
  if (use_dates) {
    p + scale_x_date(date_breaks = "4 weeks", date_labels = "%e %b", expand = expansion(mult = c(0.02, 0))) +
      coord_cartesian(xlim = x_limits)
  } else {
    p + scale_x_continuous(breaks = scales::breaks_width(5), expand = expansion(mult = c(0.02, 0))) +
      coord_cartesian(xlim = x_limits)
  }
}

# Internal: filter course engagement data to a cohort
.filter_course_cohort <- function(data, cohort,
                                  group_col = "group", cluster_col = "cluster_label") {
  if (is.null(cohort) || cohort == "All") return(data)
  group_vals   <- c("Pilot", "Scale-up")
  cluster_vals <- c("Power users", "Occasional users")
  if (cohort %in% group_vals)   return(filter(data, .data[[group_col]]   == cohort))
  if (cohort %in% cluster_vals) return(filter(data, .data[[cluster_col]] == cohort))
  data
}


# ── Chart 5: Activation / churn / reactivation ────────────────
# data: agg_activation — one row per impl_day with columns:
#   day, users, activated, churned, reactivated
# Renders two facet panels:
#   stock — distinct active users per day (area + line)
#   flows — activated (+), reactivated (+), churned (−) bar chart

plot_dash_activation <- function(data, base_size = 13, use_dates = FALSE, first_date = NULL) {

  flow_colours <- c(
    "Activated"   = palette_default,
    "Reactivated" = "#6A5CE8",
    "Churned"     = "#E03A3A"
  )

  daily <- data %>%
    group_by(day) %>%
    summarise(
      users       = sum(users,       na.rm = TRUE),
      activated   = sum(activated,   na.rm = TRUE),
      churned     = sum(churned,     na.rm = TRUE),
      reactivated = sum(reactivated, na.rm = TRUE),
      .groups = "drop"
    )

  # Build plot x: either integer day or calendar date
  if (use_dates && !is.null(first_date)) {
    daily <- daily %>% mutate(plot_x = as.Date(first_date) + (day - 1L))
    x_lab <- "Date"
  } else {
    daily <- daily %>% mutate(plot_x = day)
    x_lab <- "Days since programme start"
  }

  # Tooltip: bar-level breakdown across all three flow types, shown regardless
  # of which segment is hovered (same pattern as the course-starts chart).
  format_no_pad <- function(date) trimws(format(date, "%e %b %Y"))
  day_tooltips <- daily %>%
    mutate(
      tooltip = paste0(
        "<b>", if (use_dates && !is.null(first_date)) format_no_pad(plot_x) else paste("Day", day), "</b><br>",
        "<span style='color:", flow_colours[["Activated"]],   ";font-weight:600;'>Activated</span>: ",   scales::comma(activated),   "<br>",
        "<span style='color:", flow_colours[["Reactivated"]], ";font-weight:600;'>Reactivated</span>: ", scales::comma(reactivated), "<br>",
        "<span style='color:", flow_colours[["Churned"]],     ";font-weight:600;'>Churned</span>: ",     scales::comma(churned)
      )
    ) %>%
    select(day, tooltip)

  flows <- daily %>%
    mutate(churned = churned * -1L) %>%
    pivot_longer(
      cols      = c(activated, churned, reactivated),
      names_to  = "type",
      values_to = "value"
    ) %>%
    mutate(
      facet = "Activations & churn",
      type  = factor(str_to_title(type), levels = c("Activated", "Reactivated", "Churned"))
    ) %>%
    left_join(day_tooltips, by = "day")

  # Stock panel tooltip: one hover point per day. geom_area/geom_line only
  # accept a single tooltip for the whole path, so an invisible point per day
  # gives a per-day hover target on top of the visible area + line.
  stock <- daily %>%
    mutate(
      tooltip = paste0(
        "<b>", if (use_dates && !is.null(first_date)) format_no_pad(plot_x) else paste("Day", day), "</b><br>",
        scales::comma(users), " active users"
      )
    ) %>%
    transmute(plot_x, value = users, facet = "Active daily users", tooltip)

  p <- ggplot(flows, aes(x = plot_x, y = value, fill = type)) +
    geom_col_interactive(aes(tooltip = tooltip, data_id = plot_x), alpha = 0.7) +
    geom_area(
      data        = stock,
      aes(x = plot_x, y = value),
      fill        = palette_default,
      alpha       = 0.25,
      inherit.aes = FALSE
    ) +
    geom_line(
      data        = stock,
      aes(x = plot_x, y = value),
      colour      = palette_default,
      linewidth   = 0.2,
      inherit.aes = FALSE
    ) +
    geom_point_interactive(
      data        = stock,
      aes(x = plot_x, y = value, tooltip = tooltip, data_id = plot_x),
      colour      = palette_default,
      alpha       = 0.02,
      size        = 2,
      inherit.aes = FALSE
    ) +
    scale_fill_manual(values = flow_colours) +
    guides(fill = guide_legend(override.aes = list(shape = 21, size = 3, stroke = 0))) +
    scale_y_continuous(labels = scales::comma, expand = expansion(mult = c(0.12, 0.12))) +
    facet_grid(rows = vars(facet), scales = "free_y") +
    labs(x = x_lab, y = NULL, fill = NULL) +
    dash_theme(base_size = base_size) +
    theme(
      legend.position  = "top",
      panel.spacing.y  = unit(1.5, "lines")
    )

  if (use_dates && !is.null(first_date)) {
    p <- p + scale_x_date(
      date_breaks = "4 weeks",
      date_labels = "%e %b",
      expand      = expansion(mult = c(0.01, 0.02))
    )
  } else {
    p <- p + scale_x_continuous(expand = expansion(mult = c(0.01, 0.02)))
  }

  p
}

