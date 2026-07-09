# Shiny module for per-country dashboard panels.

txt <- list(chart_base_size = 13, chart_label_size = 3.5, chart_res = 150)

# Shared ggiraph hover/tooltip styling for girafe() calls below
girafe_opts <- list(
  opts_hover(css = "opacity:1;"),
  opts_hover_inv(css = "opacity:0.6;"),
  opts_tooltip(css = "background:white;border:1px solid #ccc;border-radius:4px;padding:8px 10px;font-family:Inter,sans-serif;font-size:13px;line-height:1.5;"),
  opts_sizing(rescale = TRUE)
)
# dashboard_ui()     — builds the tab content (sidebar + charts)
# dashboard_server() — reactive logic and renderPlot calls
#
# config list fields:
#   display_name, data_path, has_groups, has_clusters,
#   group_labels (character vector), cluster_labels (character vector)
#
# data list fields:
#   weekly_users, avg_sessions, activation, survival, user_traj, scalars


dashboard_ui <- function(id, config, data) {
  ns <- NS(id)

  # Slider ranges derived from data
  max_impl_week <- max(data$weekly_users$week[data$weekly_users$time_type == "impl_week"])
  min_act_day   <- min(data$activation$day)
  max_act_day   <- max(data$activation$day)
  scalars       <- data$scalars

  # Sidebar: split choices
  split_choices <- c("None" = "none")
  if (config$has_groups)   split_choices <- c(split_choices, "Group"   = "group")
  if (config$has_clusters) split_choices <- c(split_choices, "Cluster" = "cluster_label")
  default_split <- if (config$has_groups) "group" else "none"

  # Chart 3: cohort filter
  cohort_choices <- "All"
  if (config$has_groups)   cohort_choices <- c(cohort_choices, config$group_labels)
  if (config$has_clusters) cohort_choices <- c(cohort_choices, config$cluster_labels)

  # Chart 4: survival view
  survival_choices <- c("Total" = "total")
  if (config$has_groups)   survival_choices <- c(survival_choices, "By group"   = "group")
  if (config$has_clusters) survival_choices <- c(survival_choices, "By cluster" = "cluster")
  if (config$has_groups && config$has_clusters)
    survival_choices <- c("All strata" = "4strata", survival_choices)
  default_survival <- if (config$has_groups) "group" else "total"

  # Chart 5: trajectory facet
  traj_choices <- c("None" = "none")
  if (config$has_groups)   traj_choices <- c(traj_choices, "By group"   = "group")
  if (config$has_clusters) traj_choices <- c(traj_choices, "By cluster" = "cluster")
  if (config$has_groups && config$has_clusters)
    traj_choices <- c(traj_choices, "Four-way" = "4way")
  default_traj <- if (config$has_groups) "group" else "none"

  layout_sidebar(

    sidebar = sidebar(
      width = 240,
      open  = TRUE,
      bg    = "#efefef",

      p(class = "sidebar-title", "Weekly charts"),

      selectInput(ns("time_var"), "Time axis",
                  choices  = c("Programme week"     = "impl_week",
                               "Week since joining" = "message_week"),
                  selected = "impl_week"),

      conditionalPanel(
        condition = sprintf("input['%s'] == 'impl_week'", ns("time_var")),
        checkboxInput(ns("use_dates"), "Show dates", value = TRUE)
      ),

      if (length(split_choices) > 1)
        selectInput(ns("facet_rows"), "Split by",
                    choices  = split_choices,
                    selected = default_split),

      if (length(split_choices) > 1)
        conditionalPanel(
          condition = sprintf("input['%s'] != 'none'", ns("facet_rows")),
          checkboxInput(ns("free_scales"), "Free y-axis scales", value = TRUE)
        ),

      conditionalPanel(
        condition = sprintf("input['%s'] == 'message_week'", ns("time_var")),
        checkboxInput(ns("as_percentage"), "Show as % of week 1", value = FALSE)
      ),

      sliderInput(ns("week_range"), "Week range",
                  min = 1, max = max_impl_week,
                  value = c(1, max_impl_week),
                  step = 1, ticks = FALSE)
    ),

    div(
      style = "max-width: 1000px; margin: 0 auto; padding-bottom: 40px;",

      p(
        style = "font-family: 'Inter', sans-serif; font-size: 1rem; color: #1a1a1a; text-align: right; margin-bottom: 8px;",
        paste("Last updated:", format(scalars$last_updated, "%d %b %Y"))
      ),

      layout_columns(
        col_widths = c(4, 4, 4), gap = "12px",
        value_box(
          title    = "Total users",
          value    = format(scalars$total_users, big.mark = ","),
          showcase = bsicons::bs_icon("people-fill"),
          theme    = value_box_theme(bg = "#f7f7f7", fg = "#1a1a1a")
        ),
        value_box(
          title    = "Avg active users (past 4 weeks)",
          value    = format(scalars$avg_weekly_users_4wk, big.mark = ","),
          p(scalars$avg_weekly_users_delta,
            style = "font-family: 'Inter', sans-serif; font-size: 0.8rem; color: #1a1a1a; margin: 0;"),
          showcase = bsicons::bs_icon("person-check-fill"),
          theme    = value_box_theme(bg = "#f7f7f7", fg = "#0D2B1C")
        ),
        value_box(
          title    = "Avg sessions per user (past 4 weeks)",
          value    = scalars$avg_sessions_4wk,
          p(scalars$avg_sessions_delta,
            style = "font-family: 'Inter', sans-serif; font-size: 0.8rem; color: #1a1a1a; margin: 0;"),
          showcase = bsicons::bs_icon("chat-fill"),
          theme    = value_box_theme(bg = "#f7f7f7", fg = "#0D2B1C")
        )
      ),

      layout_columns(
        col_widths = 12, gap = "16px",

        # ── Chart 1: Weekly users ──────────────────────────────
        card(full_screen = TRUE,
          card_header(div(
            div(style = "font-family: 'Overpass', sans-serif; font-weight: 700; font-size: 1.2rem;",
                "How many teachers are using aprendIA?"),
            div(style = "font-family: 'Inter', sans-serif; font-weight: 400; font-size: 1rem; color: #888; margin-top: 2px;",
                "Column chart · unique active users per week")
          )),
          card_body(padding = "12px",
            p(class = "chart-desc",
              "This chart shows how many active users of aprendIA there are per week. An active user is someone who sends at least one message. Split by group to compare pilot and scale-up directly, or by cluster to see whether power users and occasional users follow different trajectories. Switch to \"week since joining\" to align all teachers to their own week 1, regardless of when they joined, to see how users are retained over time."
            ),
            girafeOutput(ns("plot_weekly"), height = "480px")
          )
        ),

        # ── Chart 2: Sessions ──────────────────────────────────
        card(full_screen = TRUE,
          card_header(div(
            div(style = "font-family: 'Overpass', sans-serif; font-weight: 700; font-size: 1.2rem;",
                "How deeply are active teachers engaging?"),
            div(style = "font-family: 'Inter', sans-serif; font-weight: 400; font-size: 1rem; color: #888; margin-top: 2px;",
                "Column chart · average sessions per active user per week")
          )),
          card_body(padding = "12px",
            p(class = "chart-desc",
              "Among teachers who were active in a given week, how many sessions did they have on average? Where the active users chart tells you how many teachers showed up, this one tells you how hard they worked once they did. A gradual decline in sessions per user is normal as novelty wears off — a sharp drop is worth investigating."
            ),
            girafeOutput(ns("plot_sessions"), height = "480px")
          )
        ),

        # ── Chart CE: Course engagement (Nigeria only) ────────
        if (!is.null(data$course_engagement))
          card(full_screen = TRUE,
            card_header(div(
              div(style = "font-family: 'Overpass', sans-serif; font-weight: 700; font-size: 1.2rem;",
                  "What are teachers learning about?"),
              div(style = "font-family: 'Inter', sans-serif; font-weight: 400; font-size: 1rem; color: #888; margin-top: 2px;",
                  "Module 1 starts & module progression · sessions by topic per week")
            )),
            card_body(padding = "12px",
              p(class = "chart-desc",
                "Module 1 starts are detected automatically from message text — when the bot sends a teacher the Module 1 introduction, that event is recorded by topic. Sessions are classified by topic using the same text-based approach; the lower panel counts sessions where a teacher was actively working through course content."
              ),
              if (length(cohort_choices) > 1)
                div(class = "card-controls",
                  fluidRow(
                    column(4, selectInput(ns("ce_cohort"), "Cohort",
                                          choices  = cohort_choices,
                                          selected = "All"))
                  )
                ),
              girafeOutput(ns("plot_course_starts"), height = "264px"),
              girafeOutput(ns("plot_module_time"),   height = "342px")
            )
          ),

        # ── Chart 3: Activation & churn ────────────────────────
        card(full_screen = TRUE,
          card_header(div(
            div(style = "font-family: 'Overpass', sans-serif; font-weight: 700; font-size: 1.2rem;",
                "Is aprendIA gaining more teachers than it's losing?"),
            div(style = "font-family: 'Inter', sans-serif; font-weight: 400; font-size: 1rem; color: #888; margin-top: 2px;",
                "Activation & churn · daily entries, exits, and active users")
          )),
          card_body(padding = "12px",
            p(class = "chart-desc", HTML(
              "In the upper panel, each bar shows how many teachers crossed a threshold that day: <span style='color:#3CC98A;font-weight:600;'>green</span> for first-time activation, <span style='color:#6A5CE8;font-weight:600;'>violet</span> for return after 14 or more days away, <span style='color:#E03A3A;font-weight:600;'>red</span> (below zero) for churn. The lower panel tracks how many distinct teachers were active each day."
            )),
            div(class = "card-controls",
              fluidRow(
                if (length(cohort_choices) > 1)
                  column(4, selectInput(ns("activation_cohort"), "Cohort",
                                        choices = cohort_choices, selected = "All")),
                column(if (length(cohort_choices) > 1) 8 else 12,
                  sliderInput(ns("activation_days"), "Day range",
                              min = min_act_day, max = max_act_day,
                              value = c(min_act_day, max_act_day),
                              step = 1, ticks = FALSE))
              )
            ),
            girafeOutput(ns("plot_activation"), height = "580px")
          )
        ),

        # ── Chart 4: Survival ──────────────────────────────────
        card(full_screen = TRUE,
          card_header(div(
            div(style = "font-family: 'Overpass', sans-serif; font-weight: 700; font-size: 1.2rem;",
                "How long do teachers stick around?"),
            div(style = "font-family: 'Inter', sans-serif; font-weight: 400; font-size: 1rem; color: #888; margin-top: 2px;",
                "Survival curve · probability of still engaging after n active days, fitted with a Kaplan-Meier model")
          )),
          card_body(padding = "12px",
            p(class = "chart-desc",
              "Of all the teachers who started using aprendIA, what percentage are still engaging after 7, 14, or 30 active days? A steep early drop means many teachers try the bot a few times and leave."
            ),
            div(class = "card-controls",
              fluidRow(
                if (length(survival_choices) > 1)
                  column(6, selectInput(ns("persistence_view"), "View",
                                        choices = survival_choices, selected = default_survival)),
                column(if (length(survival_choices) > 1) 6 else 12,
                  checkboxInput(ns("show_ribbon"), "Show Confidence Interval?", value = TRUE))
              )
            ),
            girafeOutput(ns("plot_persistence"), height = "480px")
          )
        ),

        # ── Chart 5: Trajectories ──────────────────────────────
        card(full_screen = TRUE,
          card_header(div(
            div(style = "font-family: 'Overpass', sans-serif; font-weight: 700; font-size: 1.2rem;",
                "What does a user journey look like?"),
            div(style = "font-family: 'Inter', sans-serif; font-weight: 400; font-size: 1rem; color: #888; margin-top: 2px;",
                "Spaghetti chart · individual user engagement trajectories")
          )),
          card_body(padding = "12px",
            p(class = "chart-desc",
              "Each line is one teacher. The dot marks where they stopped. A cluster of short lines means many teachers drop off early; a spread of long lines means a core of sustained users."
            ),
            div(class = "card-controls",
              fluidRow(
                if (length(traj_choices) > 1)
                  column(3, selectInput(ns("traj_facet"), "Split",
                                        choices = traj_choices, selected = default_traj)),
                column(if (length(traj_choices) > 1) 3 else 6,
                  sliderInput(ns("traj_n"), "Sample per group",
                              min = 10, max = 100, value = 50, step = 10, ticks = FALSE))
              )
            ),
            girafeOutput(ns("plot_trajectories"), height = "600px")
          )
        )
      )
    )
  )
}


dashboard_server <- function(id, data, config) {
  moduleServer(id, function(input, output, session) {

    sync_dpi <- function() {
      pr <- session$clientData$pixelratio
      pr <- if (is.null(pr)) 2 else pr
      showtext_opts(dpi = round(txt$chart_res / 2 * pr))
    }

    first_message_date <- min(
      data$weekly_users$week_date[
        data$weekly_users$week == 1 & data$weekly_users$time_type == "impl_week"
      ], na.rm = TRUE
    ) - 3L

    observeEvent(input$time_var, {
      if (isTRUE(input$time_var == "impl_week")) {
        updateCheckboxInput(session, "as_percentage", value = FALSE)
      }
    }, ignoreNULL = FALSE)

    facet_var <- reactive({
      val <- if (config$has_groups || config$has_clusters) input$facet_rows else "none"
      if (is.null(val) || val == "none") NULL else val
    })

    week_range <- reactive({ input$week_range[1]:input$week_range[2] })

    free_scales <- reactive({
      if (is.null(facet_var())) TRUE else isTRUE(input$free_scales)
    })

    as_percentage <- reactive({
      if (isTRUE(input$time_var == "impl_week")) FALSE else isTRUE(input$as_percentage)
    })

    activation_data <- reactive({
      d <- data$activation
      cohort <- if (is.null(input$activation_cohort)) "All" else input$activation_cohort
      if (cohort != "All") {
        if (config$has_groups   && cohort %in% config$group_labels)   d <- filter(d, group         == cohort)
        else if (config$has_clusters && cohort %in% config$cluster_labels) d <- filter(d, cluster_label == cohort)
      }
      filter(d, day >= input$activation_days[1], day <= input$activation_days[2])
    })

    persistence_view <- reactive({
      if (is.null(input$persistence_view)) "total" else input$persistence_view
    })

    traj_facet <- reactive({
      if (is.null(input$traj_facet)) "none" else input$traj_facet
    })

    output$plot_weekly <- renderGirafe({
      p <- plot_dash_weekly(
        data                 = data$weekly_users,
        time_var             = input$time_var,
        facet_rows           = facet_var(),
        free_scales          = free_scales(),
        use_dates            = isTRUE(input$use_dates) && input$time_var == "impl_week",
        as_percentage        = as_percentage(),
        week_range           = week_range(),
        base_size            = txt$chart_base_size,
        label_size           = txt$chart_label_size
      )
      girafe(ggobj = p, width_svg = 10, height_svg = 4.8, options = girafe_opts)
    })

    output$plot_sessions <- renderGirafe({
      p <- plot_dash_sessions(
        data                 = data$avg_sessions,
        time_var             = input$time_var,
        facet_var            = facet_var(),
        free_scales          = free_scales(),
        use_dates            = isTRUE(input$use_dates) && input$time_var == "impl_week",
        week_range           = week_range(),
        base_size            = txt$chart_base_size,
        label_size           = txt$chart_label_size
      )
      girafe(ggobj = p, width_svg = 10, height_svg = 4.8, options = girafe_opts)
    })

    output$plot_activation <- renderGirafe({
      p <- plot_dash_activation(
        data       = activation_data(),
        base_size  = txt$chart_base_size,
        use_dates  = isTRUE(input$use_dates),
        first_date = first_message_date
      )
      girafe(ggobj = p, width_svg = 10, height_svg = 5.8, options = girafe_opts)
    })

    output$plot_persistence <- renderGirafe({
      p <- plot_dash_persistence(
        data        = data$survival,
        view        = persistence_view(),
        group       = "All",
        cluster     = "All",
        show_ribbon = isTRUE(input$show_ribbon),
        base_size   = txt$chart_base_size
      )
      girafe(ggobj = p, width_svg = 10, height_svg = 4.8, options = girafe_opts)
    })

    output$plot_trajectories <- renderGirafe({
      p <- plot_dash_trajectories(
        data       = data$user_traj,
        group      = "All",
        cluster    = "All",
        facet      = traj_facet(),
        n_sample   = input$traj_n,
        base_size  = txt$chart_base_size,
        label_size = txt$chart_label_size
      )
      girafe(ggobj = p, width_svg = 10, height_svg = 6, options = girafe_opts)
    })

    if (!is.null(data$course_engagement)) {
      ce_use_dates <- reactive({ isTRUE(input$use_dates) && input$time_var == "impl_week" })
      ce_cohort    <- reactive({ if (is.null(input$ce_cohort)) "All" else input$ce_cohort })

      ce_x_limits <- reactive({
        wr <- input$week_range
        if (is.null(wr)) return(NULL)
        if (ce_use_dates()) {
          c(first_message_date + weeks(wr[1] - 1),
            first_message_date + weeks(wr[2] - 1) + days(6))
        } else {
          c(wr[1], wr[2])
        }
      })

      output$plot_course_starts <- renderGirafe({
        p <- plot_dash_course_starts(
          data      = data$course_engagement$course_starts,
          cohort    = ce_cohort(),
          use_dates = ce_use_dates(),
          x_limits  = ce_x_limits(),
          base_size = txt$chart_base_size
        )
        girafe(ggobj = p, width_svg = 10, height_svg = 2.64, options = girafe_opts)
      })

      output$plot_module_time <- renderGirafe({
        p <- plot_dash_module_time(
          data      = data$course_engagement$module_progression,
          cohort    = ce_cohort(),
          use_dates = ce_use_dates(),
          x_limits  = ce_x_limits(),
          base_size = txt$chart_base_size
        )
        girafe(ggobj = p, width_svg = 10, height_svg = 3.42, options = girafe_opts)
      })
    }

  })
}
