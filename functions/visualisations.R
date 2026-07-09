# Visualisation functions for aprendIA

# Standard theme for all charts
aprendia_theme <- function() {
  theme_minimal() +
    theme(
      plot.background = element_rect(fill = "grey97"),
      axis.title.y = element_text(family = "Inter", size = 12, margin = margin(r = 15)),
      axis.title.x = element_text(family = "Inter", size = 12, margin = margin(t = 15)),
      axis.text.y = element_text(family = "Roboto Mono", size = 8),
      axis.text.x = element_text(family = "Roboto Mono", size = 8),
      strip.text = element_text(family = "Inter", size = 10),
      legend.title = element_text(family = "Inter", size = 10),
      legend.text = element_text(family = "Inter", size = 8)
    )
}

# Working version not in use
aprendia_palette <- colorRampPalette(c(
  "#1A1A1A",
  "#0D2B1C",   # deep forest (dark end)
  "#2D6B3C",   # mid forest green
  "#7DB87A",
  "#3CC98A",   # bright emerald (the hero green)
  "#A8E8CC",   # light mint tint
  "#8B2020",
  "#C46B2A",
  "#D4A829",
  "#F2EDE4"    # warm cream (light end)
))

#"#0D2B1C"
#"#3CC98A"
#"#F2EDE4"
#"#1A1A1A"
#"#8B2020" → burnt orange "#C46B2A" → golden yellow "#D4A829" → light green "#7DB87A" → forest green "#2D6B3C"


# Weekly unique users chart with flexible faceting
# Arguments:
#   data: Message-level data
#   time_var: Time variable to use ("impl_week" or "message_week")
#   facet_var: Single variable to facet by ("group", "cluster"), OR
#   facet_rows: Variable for row faceting (use with facet_cols for 2D faceting)
#   facet_cols: Variable for column faceting (use with facet_rows for 2D faceting)
#   free_scales: Use free y-scales for facets (default TRUE)
#   week_range: Vector of weeks to include (e.g., 1:24), or NULL for all
#   as_percentage: Show as percentage rather than absolute numbers (default FALSE)
#   cluster_labels: Named vector to relabel cluster values (optional, from config)
#   add_labels: Whether to add text labels on bars
#   label_threshold_high: Label bars above this % of max (default 0.8)
#   label_threshold_low: Label bars below this % of max (default 0.1)
#   x_label: X-axis label
#   y_label: Y-axis label (auto-set if NULL)
# Returns: ggplot object
plot_weekly_users <- function(
    data, 
    time_var = "impl_week",
    facet_var = NULL,
    facet_rows = NULL,
    facet_cols = NULL,
    fill_var = NULL,
    fill_discrete = FALSE,
    free_scales = TRUE,
    week_range = NULL,
    as_percentage = FALSE,
    cluster_labels = NULL,
    add_labels = TRUE,
    use_dates = FALSE,
    project_start_date = NULL,
    label_threshold_high = 0.8,
    label_threshold_low = 0.1,
    x_label = "Week",
    y_label = NULL
  ) {
  
  library(tidyverse)
  library(scales)
  
  # Auto-set y_label if not provided
  if (is.null(y_label)) {
    y_label <- if_else(as_percentage, "Percentage of users", "Number of unique users")
  }
  
  # Check for potentially confusing parameter combinations
  if (as_percentage && time_var == "impl_week") {
    warning("as_percentage is most meaningful with message_week (user-relative time). ",
            "With impl_week, percentages show 'what % of group was active this week', ",
            "which is less intuitive than retention curves with message_week.")
  }
  
  # Determine faceting variables (allow single facet_var for backwards compatibility)
  if (!is.null(facet_var)) {
    facet_rows <- facet_var
    facet_cols <- NULL
  }
  
  # Apply cluster labels if provided
  if (!is.null(cluster_labels)) {
    if ("cluster" %in% names(data)) {
      data <- data %>% mutate(cluster = recode(as.character(cluster), !!!cluster_labels))
    }
    if ("cluster_group" %in% names(data)) {
      data <- data %>% mutate(cluster_group = recode(as.character(cluster_group), !!!cluster_labels))
    }
  }
  
  # Filter to week range if specified
  if (!is.null(week_range)) {
    data <- data %>% filter(.data[[time_var]] %in% week_range)
  }
  
  # Build grouping variables list
  group_vars <- c(time_var)
  if (!is.null(facet_rows)) group_vars <- c(group_vars, facet_rows)
  if (!is.null(facet_cols)) group_vars <- c(group_vars, facet_cols)
  
  # Build plot data
  plot_data <- data %>%
    filter(if (!is.null(facet_rows)) !is.na(.data[[facet_rows]]) else TRUE) %>%
    filter(if (!is.null(facet_cols)) !is.na(.data[[facet_cols]]) else TRUE) %>%
    group_by(across(all_of(c(group_vars, "contact_id")))) %>%
    summarise(n = n(), .groups = "drop") %>%
    group_by(across(all_of(group_vars))) %>%
    summarise(users = n_distinct(contact_id), .groups = "drop")
  
  # Calculate new users within each facet group
  grouping_vars <- setdiff(group_vars, time_var)
  if (length(grouping_vars) > 0) {
    plot_data <- plot_data %>%
      group_by(across(all_of(grouping_vars))) %>%
      arrange(.data[[time_var]]) %>%
      mutate(
        new_users = users - lag(users, default = 0),
        new_users = if_else(new_users < 0, 0, new_users)
      ) %>%
      ungroup()
  } else {
    plot_data <- plot_data %>%
      arrange(.data[[time_var]]) %>%
      mutate(
        new_users = users - lag(users, default = 0),
        new_users = if_else(new_users < 0, 0, new_users)
      )
  }
  
  plot_data <- plot_data %>%
    mutate(
      users = users - new_users,
      total_users = users + new_users,
      week = .data[[time_var]]
    )
  
  # Calculate actual dates from data if requested
  if (use_dates && time_var == "impl_week") {
    # Get the very first message in the entire dataset
    first_message_date <- as.Date(min(data$time_corrected))
    
    plot_data <- plot_data %>%
      mutate(
        week_date = first_message_date + weeks(week - 1) + days(3)  # Midpoint of each week
      )
  }
  
  # Convert to percentage if requested (retention curve: each week as % of week 1)
  if (as_percentage) {
    if (length(grouping_vars) > 0) {
      plot_data <- plot_data %>%
        group_by(across(all_of(grouping_vars))) %>%
        mutate(
          week_one_users = total_users[week == min(week)],
          total_users = total_users / week_one_users
        ) %>%
        ungroup()
    } else {
      plot_data <- plot_data %>%
        mutate(
          week_one_users = total_users[week == min(week)],
          total_users = total_users / week_one_users
        )
    }
  }
  
  # Calculate labels with thresholds
  if (length(grouping_vars) > 0) {
    plot_data <- plot_data %>%
      group_by(across(all_of(grouping_vars))) %>%
      mutate(
        max_users = max(total_users),
        show_label = total_users > max_users * label_threshold_high | 
          total_users < max_users * label_threshold_low
      ) %>%
      ungroup()
  } else {
    plot_data <- plot_data %>%
      mutate(
        max_users = max(total_users),
        show_label = total_users > max_users * label_threshold_high | 
          total_users < max_users * label_threshold_low
      )
  }
  
  # Format labels based on percentage or absolute
  if (as_percentage) {
    plot_data <- plot_data %>%
      mutate(label_text = if_else(show_label, percent(total_users, accuracy = 1), ""))
  } else {
    plot_data <- plot_data %>%
      mutate(label_text = if_else(show_label, as.character(round(total_users)), ""))
  }
  
  # Create base plot
  # Determine x variable (dates or weeks)
  x_var_use <- if (use_dates && time_var == "impl_week") {
    "week_date"
  } else {
    "week"
  }
  
  # Determine fill variable (defaults to week)
  fill_var_use <- if (!is.null(fill_var)) fill_var else "week"
  
  # Apply fill (continuous or discrete)
  if (fill_discrete) {
    p <- plot_data %>%
      ggplot(aes(x = .data[[x_var_use]])) +
      geom_col(aes(y = total_users, fill = factor(.data[[fill_var_use]]))) +
      labs(x = x_label, y = y_label) +
      aprendia_theme() +
      theme(legend.position = "none")
  } else {
    p <- plot_data %>%
      ggplot(aes(x = .data[[x_var_use]])) +
      geom_col(aes(y = total_users, fill = .data[[fill_var_use]])) +
      labs(x = x_label, y = y_label) +
      aprendia_theme() +
      theme(legend.position = "none")
  }
  
  # Adjust y-scale
  if (as_percentage) {
    p <- p + scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.1)))
  } else {
    p <- p + scale_y_continuous(expand = expansion(mult = c(0, 0.1)))
  }
  
  # Add labels if requested
  if (add_labels) {
    p <- p + geom_text(
      aes(y = total_users, label = label_text),
      vjust = -0.5,
      colour = "black", size = 3, family = "Roboto Mono"
    )
  }
  
  # Add faceting
  if (!is.null(facet_rows) && !is.null(facet_cols)) {
    # Two-way faceting (rows AND columns)
    scales_type <- if_else(free_scales, "free_y", "fixed")
    p <- p + facet_grid(rows = vars(.data[[facet_rows]]), 
                        cols = vars(.data[[facet_cols]]), 
                        scales = scales_type)
  } else if (!is.null(facet_rows)) {
    # Row faceting only
    scales_type <- if_else(free_scales, "free_y", "fixed")
    p <- p + facet_grid(rows = vars(.data[[facet_rows]]), scales = scales_type)
  } else if (!is.null(facet_cols)) {
    # Column faceting only
    scales_type <- if_else(free_scales, "free_y", "fixed")
    p <- p + facet_grid(cols = vars(.data[[facet_cols]]), scales = scales_type)
  }
  
  return(p)
}


# Average sessions per user per week
# Arguments:
#   data: Session-level data (session_data_long)
#   time_var: Time variable to use ("impl_week" or "message_week")
#   facet_var: Variable to facet by ("group", "cluster", or NULL for no faceting)
#   facet_direction: "rows" or "cols"
#   week_range: Vector of weeks to include, or NULL for all
#   add_labels: Whether to add text labels on bars
#   label_decimals: Number of decimal places for labels (default 1)
#   x_label: X-axis label
#   y_label: Y-axis label
# Returns: ggplot object
plot_avg_sessions <- function(
    data,
    time_var = "impl_week",
    facet_var = "group",
    facet_direction = "rows",
    week_range = NULL,
    add_labels = TRUE,
    label_decimals = 1,
    x_label = "Week",
    y_label = "Average number of sessions"
  ) {
  
  # Filter to week range if specified
  if (!is.null(week_range)) {
    data <- data %>% filter(.data[[time_var]] %in% week_range)
  }
  
  # Filter out NA weeks
  data <- data %>% filter(!is.na(.data[[time_var]]))
  
  # Build plot data with or without faceting
  if (!is.null(facet_var)) {
    # Filter out NAs in facet variable
    data <- data %>% filter(!is.na(.data[[facet_var]]))
    
    plot_data <- data %>%
      group_by(.data[[facet_var]], contact_id, .data[[time_var]]) %>%
      summarise(n = n(), .groups = "drop") %>%
      mutate(week = factor(.data[[time_var]])) %>%
      group_by(.data[[facet_var]], week) %>%
      summarise(avg_sessions = mean(n), .groups = "drop")
  } else {
    plot_data <- data %>%
      group_by(contact_id, .data[[time_var]]) %>%
      summarise(n = n(), .groups = "drop") %>%
      mutate(week = factor(.data[[time_var]])) %>%
      group_by(week) %>%
      summarise(avg_sessions = mean(n), .groups = "drop")
  }
  
  # Create base plot
  p <- plot_data %>%
    ggplot(aes(x = week, y = avg_sessions, fill = week)) +
    geom_col() +
    labs(x = x_label, y = y_label) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
    aprendia_theme() +
    theme(legend.position = "none")
  
  # Add labels if requested
  if (add_labels) {
    p <- p + geom_text(
      aes(y = avg_sessions, label = round(avg_sessions, label_decimals)),
      vjust = -0.5,
      colour = "black", size = 3, family = "Roboto Mono"
    )
  }
  
  # Add faceting if specified
  if (!is.null(facet_var)) {
    if (facet_direction == "rows") {
      p <- p + facet_grid(rows = vars(.data[[facet_var]]))
    } else {
      p <- p + facet_grid(cols = vars(.data[[facet_var]]))
    }
  }
  
  return(p)
}


