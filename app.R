library(shiny)
library(bslib)
library(bsicons)
library(tidyverse)
library(showtext)
library(survival)
library(broom)
library(ggiraph)

source("functions/dash_visualisations.R")
source("functions/dashboard_module.R")

# ── Country configs ───────────────────────────────────────────
nigeria_config <- list(
  display_name   = "Nigeria",
  data_path      = "data/nigeria/",
  has_groups     = TRUE,
  has_clusters   = TRUE,
  group_labels   = c("Pilot", "Scale-up"),
  cluster_labels = c("Power users", "Occasional users")
)

ecuador_config <- list(
  display_name   = "Ecuador",
  data_path      = "data/ecuador/",
  has_groups     = FALSE,
  has_clusters   = FALSE,
  group_labels   = character(0),
  cluster_labels = character(0)
)

niger_config <- list(
  display_name   = "Niger",
  data_path      = "data/niger/",
  has_groups     = FALSE,
  has_clusters   = FALSE,
  group_labels   = character(0),
  cluster_labels = character(0)
)

# ── Data loading ──────────────────────────────────────────────
load_country_data <- function(path) {
  ce_path <- file.path(path, "agg_course_engagement.rds")
  list(
    weekly_users      = readRDS(file.path(path, "agg_weekly_users.rds")),
    avg_sessions      = readRDS(file.path(path, "agg_avg_sessions.rds")),
    activation        = readRDS(file.path(path, "agg_activation.rds")),
    survival          = readRDS(file.path(path, "agg_survival.rds")),
    user_traj         = readRDS(file.path(path, "agg_user_traj.rds")),
    scalars           = readRDS(file.path(path, "dashboard_scalars.rds")),
    course_engagement = if (file.exists(ce_path)) readRDS(ce_path) else NULL
  )
}

nigeria_data  <- load_country_data(nigeria_config$data_path)
ecuador_data  <- tryCatch(load_country_data(ecuador_config$data_path), error = function(e) NULL)
niger_data    <- tryCatch(load_country_data(niger_config$data_path),   error = function(e) NULL)

# ── Theme ─────────────────────────────────────────────────────
app_theme <- bs_theme(
  version      = 5,
  bootswatch   = "litera",
  base_font    = font_google("Inter"),
  heading_font = font_google("Overpass"),
  navbar_bg    = "#f7f7f7",
  bg           = "#f7f7f7",
  fg           = "#1a1a1a",
  primary      = "#3CC98A"
)

app_css <- tags$head(tags$style(HTML("
  .card-header {
    font-family: 'Overpass', sans-serif;
    font-weight: 600;
    font-size: 2rem;
    letter-spacing: 0.02em;
    background-color: transparent;
    border-bottom: 1px solid #e0e0e0;
    padding: 10px 14px 8px 14px;
  }
  .sidebar-title {
    font-family: 'Overpass', sans-serif;
    font-weight: 600;
    font-size: 1rem;
    margin-bottom: 4px;
  }
  hr.sidebar-divider {
    border-color: #ccc;
    margin: 14px 0;
  }
  .chart-desc {
    font-family: 'Inter', sans-serif;
    font-size: 0.88rem;
    color: #444;
    line-height: 1.6;
    margin-bottom: 12px;
  }
  .card-controls {
    font-family: 'Inter', sans-serif;
    font-size: 0.85rem;
    background-color: #f0f0f0;
    border-radius: 6px;
    padding: 10px 12px;
    margin-bottom: 12px;
  }
  .card-body { overflow: visible !important; }
  .card      { overflow: visible !important; }
  .irs--shiny .irs-bar {
    background: #3CC98A;
    border-top: 1px solid #3CC98A;
    border-bottom: 1px solid #3CC98A;
  }
  .irs--shiny .irs-handle { border: 1px solid #2aa874; }
  .irs--shiny .irs-from,
  .irs--shiny .irs-to,
  .irs--shiny .irs-single { background: #3CC98A; }
  .form-check-input:checked {
    background-color: #3CC98A !important;
    border-color: #3CC98A !important;
  }
  .selectize-input.focus {
    border-color: #3CC98A !important;
    box-shadow: 0 0 0 2px rgba(60, 201, 138, 0.2) !important;
  }
")))

# ── UI ────────────────────────────────────────────────────────
ui <- page_navbar(

  title = tags$span(
    style = "font-family: 'Overpass', sans-serif; font-size: 2rem; font-weight: 700; letter-spacing: 0.04em;",
    HTML("aprendIA &nbsp;·&nbsp;&nbsp; usage dashboard")
  ),

  theme  = app_theme,
  header = app_css,

  nav_panel("\U0001f1f3\U0001f1ec Nigeria",
    dashboard_ui("nigeria", nigeria_config, nigeria_data)
  ),

  nav_panel("\U0001f1ea\U0001f1e8 Ecuador",
    if (!is.null(ecuador_data))
      dashboard_ui("ecuador", ecuador_config, ecuador_data)
    else
      div(style = "padding: 40px; font-family: 'Inter', sans-serif; color: #444;",
          p("Ecuador data not yet available."),
          p("Run ", tags$code("scripts/run_ecuador.R"), " to generate the dashboard files."))
  ),

  nav_panel("\U0001f1f3\U0001f1ea Niger",
    if (!is.null(niger_data))
      dashboard_ui("niger", niger_config, niger_data)
    else
      div(style = "padding: 40px; font-family: 'Inter', sans-serif; color: #444;",
          p("Niger data not yet available."),
          p("Run ", tags$code("scripts/run_niger.R"), " to generate the dashboard files."))
  )
)

# ── Server ────────────────────────────────────────────────────
server <- function(input, output, session) {
  dashboard_server("nigeria", nigeria_data, nigeria_config)
  if (!is.null(ecuador_data)) dashboard_server("ecuador", ecuador_data, ecuador_config)
  if (!is.null(niger_data))   dashboard_server("niger",   niger_data,   niger_config)
}

shinyApp(ui, server)
