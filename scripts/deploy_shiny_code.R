# Deploy both live dashboards to shinyapps.io.
#
# Two separate apps, two separate directories -- each self-contained (own
# copies of app.R/functions/data) since shinyapps.io only bundles files
# inside the directory you deploy from:
#
#   deploy_v1_archive/  -> "aprendia-dashboard-archive" (frozen multi-country
#                           v1, kept live for reference -- see
#                           the project working log)
#   dashboard_v2/        -> "aprendia-dashboard" (the current, actively
#                           maintained Nigeria-only dashboard; this is the
#                           address product/leadership actually use)
#
# Run with the repo root as the working directory (true when sourced from
# run_all.R or run directly via `Rscript scripts/deploy_shiny_code.R` from
# the repo root) -- deployApp()'s own appDir argument handles bundling from
# each subdirectory without needing setwd().
#
# Neither directory's copied files sync themselves. If dashboard_v2/'s
# functions/dash_visualisations.R or data/nigeria/dashboard_v2_data.rds
# (or deploy_v1_archive's equivalents) have drifted from the shared
# pipeline versions, re-copy before deploying -- this script deploys
# whatever is currently sitting in each folder, as-is.

library(rsconnect)

# ── v1 (archive) ──────────────────────────────────────────────
deployApp(
  appDir   = "deploy_v1_archive",
  appName  = "aprendia-dashboard-archive",
  appFiles = c(
    "app.R",
    "functions/dash_visualisations.R",
    "functions/dashboard_module.R",
    "data/nigeria/agg_weekly_users.rds",
    "data/nigeria/agg_avg_sessions.rds",
    "data/nigeria/agg_activation.rds",
    "data/nigeria/agg_survival.rds",
    "data/nigeria/agg_user_traj.rds",
    "data/nigeria/dashboard_scalars.rds",
    "data/nigeria/agg_course_engagement.rds",
    "data/ecuador/agg_weekly_users.rds",
    "data/ecuador/agg_avg_sessions.rds",
    "data/ecuador/agg_activation.rds",
    "data/ecuador/agg_survival.rds",
    "data/ecuador/agg_user_traj.rds",
    "data/ecuador/dashboard_scalars.rds",
    "data/niger/agg_weekly_users.rds",
    "data/niger/agg_avg_sessions.rds",
    "data/niger/agg_activation.rds",
    "data/niger/agg_survival.rds",
    "data/niger/agg_user_traj.rds",
    "data/niger/dashboard_scalars.rds"
  )
)

# ── v2 (current, Nigeria only) ───────────────────────────────
deployApp(
  appDir   = "dashboard_v2",
  appName  = "aprendia-dashboard",
  appFiles = c(
    "app.R",
    "functions/dash_visualisations.R",
    "data/nigeria/dashboard_v2_data.rds",
    "www/aprendia_logo.png"
  )
)
