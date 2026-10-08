# aprendIA dashboard v2 (Nigeria only) — deployable copy.
#
# Lives in the pipeline repo as its own self-contained subfolder so it can
# deploy to shinyapps.io independently of the old multi-country app.R at
# the repo root (which stays untouched, archived under a separate app name
# -- see the project working log). shinyapps.io only bundles
# files inside the directory you deploy from, so functions/dash_visualisations.R
# and data/nigeria/dashboard_v2_data.rds below are COPIES, not the shared
# pipeline files -- they will go stale and need re-copying (or a real sync
# step) before each redeploy, same caveat as the onboarding_schema CSV copy
# in scripts/nigeria/05_dashboard.R.
#
# Underlying data: data/nigeria/dashboard_v2_data.rds, computed by
# scripts/nigeria/05_dashboard.R (section 8) from clean_message_data.csv.
# "Active" = sent at least one Incoming message that period. Cluster split
# is REAL (the production pipeline's own k=2 clustering, joined from
# contacts_data.csv) as of 2026-09-18 -- was an illustrative proportional
# split before that.
#
# Back to two separate short charts (not the single faceted chart tried
# previously) specifically so cluster-splitting works cleanly on the active-
# users chart without fighting the metric facet. Both charts are column
# charts, matching the real dashboard's actual convention — the earlier
# line+area treatment is reverted.
#
# Styling sourced directly from functions/dash_visualisations.R (dash_theme(),
# palette constants) and functions/dashboard_module.R (girafe_opts, copied
# since sourcing that whole file would also pull in dashboard_ui()/server()
# this prototype doesn't need). Card markup ported from
# scratch/dashboard_full_mockup.html. Crete Round scoped to the brand
# wordmark only — the real dashboard doesn't use it elsewhere.

library(shiny)
library(bslib)
library(ggiraph)
library(dplyr)
library(ggplot2)
library(scales)

source("functions/dash_visualisations.R")

# rescale = FALSE — chart renders at a fixed native pixel size
# (width_svg/height_svg in inches * 96dpi) instead of shrinking to fit a
# narrower window. Combined with the overflow-x:auto wrapper around each
# girafeOutput below, a narrow window gets a horizontal scrollbar instead of
# a squashed chart.
girafe_opts <- list(
  opts_hover(css = "opacity:1;"),
  opts_hover_inv(css = "opacity:0.6;"),
  opts_tooltip(css = "background:white;border:1px solid #ccc;border-radius:4px;padding:8px 10px;font-family:Inter,sans-serif;font-size:13px;line-height:1.5;"),
  opts_sizing(rescale = FALSE)
)

# width_svg/height_svg (inches) * 96dpi = the fixed pixel size the charts
# render at now that rescale is off. Kept as constants so the CSS wrapper
# height below can match tightly instead of leaving dead space.
CHART_WIDTH_SVG  <- 9.5
CHART_HEIGHT_SVG <- 3.8
CHART_HEIGHT_PX  <- CHART_HEIGHT_SVG * 96

# Trajectory chart: faceted 3-wide inside the same CHART_WIDTH_SVG, so each
# panel's plotting width is roughly CHART_WIDTH_SVG / 3 (a bit less once the
# shared y-axis labels eat into it). For panels to read as ~squares, the
# chart's total height needs panel-width-ish PLUS a fixed allowance for the
# strip label and x-axis title/text, which only exist once (ncol=3, nrow=1)
# and don't shrink when width is divided three ways. This is an estimate,
# not a computed guarantee — eyeball and adjust once rendered.
# Now 2 real clusters, not 3 illustrative ones -- ncol=2, so the
# width/2-plus-overhead target is taller per panel than the old 3-column
# estimate.
TRAJ_HEIGHT_SVG <- 5.2
TRAJ_HEIGHT_PX  <- TRAJ_HEIGHT_SVG * 96

# Row 3's two charts sit side by side (col_widths = c(6,6)) inside the same
# 1000px page wrapper -- CHART_WIDTH_SVG (9.5in) was sized for a full-width
# card and overflows a half-width one. ~4.5in fits a half-column with its
# own padding/gap, no horizontal scroll needed for either chart.
ROW3_CHART_WIDTH_SVG  <- 4.5
ROW3_CHART_HEIGHT_SVG <- 3.8
ROW3_CHART_HEIGHT_PX  <- ROW3_CHART_HEIGHT_SVG * 96

# The bubble chart gets its own SQUARE canvas -- packcircles always packs
# into a roughly circular overall blob, so a rectangular frame (matching the
# waterfall's shape) leaves visible empty corners. A square frame fits the
# blob's own shape much more tightly.
BUBBLE_SIZE_SVG <- 3.8
BUBBLE_SIZE_PX  <- BUBBLE_SIZE_SVG * 96

# ---------------------------------------------------------------------------
# Real data
# ---------------------------------------------------------------------------

rd <- readRDS("data/nigeria/dashboard_v2_data.rds")
scalars             <- rd$scalars
active_users_total  <- rd$active_users_weekly %>% mutate(cluster = "All users")
active_users_by_cluster <- rd$active_users_weekly_by_cluster
new_users_weekly    <- rd$new_users_weekly
row2_scalars        <- rd$row2_scalars
survival_curve      <- rd$survival_curve
trajectory_data     <- rd$trajectory_data
row3_scalars        <- rd$row3_scalars
row3_breakdown      <- rd$row3_breakdown

# Bubble canvas dimensions: computed ONCE here (not inside renderGirafe),
# since the UI's girafeOutput() height is a static CSS value declared at
# app start -- if the render function alone decided the aspect ratio, the
# declared container height wouldn't match the actual rendered SVG height,
# the same clipping bug already hit once on Row 1's charts. row3_breakdown
# is static data, so this is safe to compute up front.
bubble_layout_for_sizing <- packcircles::circleProgressiveLayout(row3_breakdown$n, sizetype = "area")
bubble_bbox_w <- max(bubble_layout_for_sizing$x + bubble_layout_for_sizing$radius) - min(bubble_layout_for_sizing$x - bubble_layout_for_sizing$radius)
bubble_bbox_h <- max(bubble_layout_for_sizing$y + bubble_layout_for_sizing$radius) - min(bubble_layout_for_sizing$y - bubble_layout_for_sizing$radius)
bubble_aspect <- bubble_bbox_w / bubble_bbox_h
BUBBLE_WIDTH_SVG  <- BUBBLE_SIZE_SVG * sqrt(bubble_aspect)
BUBBLE_HEIGHT_SVG <- BUBBLE_SIZE_SVG / sqrt(bubble_aspect)
BUBBLE_HEIGHT_PX  <- BUBBLE_HEIGHT_SVG * 96

date_min <- min(active_users_total$week_date, na.rm = TRUE)
date_max <- max(active_users_total$week_date, na.rm = TRUE)

# REAL cluster assignments now (the production pipeline's own k=2
# clustering) -- no longer illustrative. No third "One-time only" bucket,
# since that was never a real cluster to begin with -- see 2026-09-18's
# k=3 exploration.
#
# Colour override 2026-09-21: Sanzo Wada combination 281 (Pale Lemon
# Yellow / Benzol Green / Cobalt Green / Antwarp Blue) -- the two most
# contrasting of the four (Cobalt Green, Antwarp Blue) go to the clusters;
# the other two are reserved for the waterfall only, to avoid the same hex
# meaning "Power users" in one chart and a funnel stage in another. Darker/
# more saturated (Antwarp Blue) to the smaller, more-engaged Power users;
# lighter (Cobalt Green) to the larger Occasional users -- matches the
# existing "darker = more" convention used elsewhere (eg the bubble ramp).
cluster_pal <- c("Power users" = "#007190", "Occasional users" = "#96D1AA")

# Full-sample ("All users") single-series colour, also from Wada 281, but
# NOT one of the two cluster colours above -- Benzol Green, the other of
# the two reserved-for-waterfall colours. Pale Lemon Yellow (the remaining
# one) is too light for good contrast as a solid bar fill against the
# card background.
full_sample_pal <- "#00978D"

delta_label <- function(pct) paste0(if (pct >= 0) "+" else "", pct, "% vs 4-week avg")
pct_of <- function(n, denom) paste0(round(100 * n / denom, 1), "%")

# Plain-English labels for the snake_case never_onboarded_category values --
# used only in the Row 3 breakdown chart's hover tooltip.
category_label <- c(
  consent_gate_bypassed             = "Consent bypassed",
  bypassed_via_adhoc_qa             = "Went straight to Q&A",
  used_confound_feature             = "Used a different feature",
  too_few_messages                  = "Too few messages to tell",
  stalled_at_consent                = "Stalled at consent",
  went_straight_to_course           = "Went straight to a course",
  genuine_trigger_boilerplate_reuse = "Trigger reused as menu text",
  affirmed_no_access_granted        = "Said yes to consent, got stuck",
  "other / uncategorized"           = "Other / unclear"
)

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

app_theme <- bs_theme(base_font = font_google("Inter"))

card_header_block <- function(title, subtitle, control = NULL) {
  card_header(
    div(style = "display:flex; justify-content:space-between; align-items:flex-start; gap:12px;",
      div(
        div(style = "font-family: 'Overpass', sans-serif; font-weight: 700; font-size: 1.1rem;", title),
        div(style = "font-family: 'Inter', sans-serif; font-weight: 400; font-size: 0.85rem; color: #888; margin-top: 2px;", subtitle)
      ),
      control
    )
  )
}

stat_card <- function(icon_path_d, label, value, descriptor) {
  div(class = "stat-card",
    div(class = "stat-icon-row",
      div(class = "stat-icon-disc", tags$svg(viewBox = "0 0 24 24", tags$path(d = icon_path_d))),
      span(class = "stat-label", label)
    ),
    div(class = "stat-numeral-block",
      div(class = "stat-numeral", value),
      div(class = "stat-descriptor", descriptor)
    )
  )
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

ui <- page_sidebar(
  theme = app_theme,
  title = NULL,
  sidebar = sidebar(
    width = 260,
    # bslib's own sidebar(title=...) always renders above the body content
    # no matter where it's placed in the argument list -- to get the logo
    # ABOVE "Filters", "Filters" has to move into the body as plain text
    # instead of using the title slot.
    div(style = "text-align: center; margin-bottom: 12px;",
      img(src = "aprendia_logo.png", alt = "aprendIA icon", style = "height: 40px;")
    ),
    div(style = "font-weight: 600; font-size: 1.1rem; margin-bottom: 12px;", "Filters"),
    dateRangeInput("date_range", "Date range",
                    start = date_min, end = date_max,
                    min = date_min, max = date_max,
                    startview = "year"),
    # Permanent cluster legend, not tied to any one chart's cluster toggle --
    # previously each chart grew/shrank its own bottom legend only when its
    # own "By cluster" option was picked, which visibly resized the chart
    # every time. One fixed reference here means every chart's cluster
    # colours stay legible without ever changing that chart's own layout.
    tags$div(style = "margin-top: 20px;",
      tags$div(style = "font-size: 0.8rem; font-weight: 600; color: #495057; margin-bottom: 8px;", "Cluster colours"),
      lapply(names(cluster_pal), function(nm) {
        tags$div(style = "display:flex; align-items:center; gap:8px; margin-bottom:6px;",
          tags$span(style = paste0("width:12px; height:12px; border-radius:3px; background:", cluster_pal[[nm]], "; flex-shrink:0;")),
          tags$span(style = "font-size: 0.8rem; color: #333;", nm)
        )
      })
    )
  ),
  tags$head(
    tags$link(rel = "stylesheet",
      href = "https://fonts.googleapis.com/css2?family=Crete+Round:ital@0;1&display=swap"),
    tags$style(HTML("
      .brand-header {
        display: flex; align-items: center; justify-content: center;
        gap: 16px; padding: 20px 0 36px 0;
      }
      .brand-header img { height: 64px; }
      .brand-header .brand-word {
        font-family: 'Crete Round', Georgia, serif;
        font-style: italic;
        font-weight: 700;
        font-size: 2rem;
        color: #1F303F;
        line-height: 1;
      }
      .section-heading {
        font-family: 'Overpass', sans-serif;
        font-weight: 700;
        font-size: 1.35rem;
        color: #1F303F;
        margin: 8px 0 12px 0;
      }
      .last-updated { text-align: left; font-size: 0.8rem; color: #7C8894; margin-bottom: 14px; }
      .intro-columns {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 36px;
        margin: 0 0 28px 0;
      }
      .intro-columns p {
        font-family: 'Inter', sans-serif;
        font-size: 0.9rem;
        color: #333;
        line-height: 1.6;
        margin: 0;
      }
      .intro-columns a { color: #17B8CC; text-decoration: underline; }
      @media (max-width: 700px) {
        .intro-columns { grid-template-columns: 1fr; }
      }
      .section-intro {
        font-family: 'Inter', sans-serif;
        font-size: 0.85rem;
        color: #555;
        line-height: 1.5;
        margin: 0 0 14px 0;
      }
      .chart-desc { font-family: 'Inter', sans-serif; font-size: 0.78rem; color: #555; margin: 6px 0 8px 0; }
      .cluster-note { font-size: 0.72rem; color: #B0473F; margin-top: 4px; }

      .card-row { display: flex; gap: 20px; margin-bottom: 16px; }
      .stat-card {
        /* Benzol Green (#00978D) at 85% opacity, not the flat #96D1AA
           (which is also Cobalt Green, now used for the Occasional-users
           cluster colour -- this also resolves that overlap). */
        background: rgba(0, 151, 141, 0.3);
        color: #1F303F;
        padding: 22px 20px;
        border-radius: 16px;
        flex: 1 1 0;
        height: 140px;
        box-sizing: border-box;
        box-shadow: 0 4px 14px rgba(0,0,0,0.10);
        display: flex;
        flex-direction: column;
        justify-content: flex-start;
      }
      /* Numeral gets a FIXED top margin instead of the whole numeral+
         descriptor block being bottom-anchored (justify-content:
         space-between) -- that made a card's numeral sit at a different
         height depending on how many lines its OWN descriptor wrapped to,
         so numerals across the row didn't line up. Fixed-position top
         instead: every numeral starts at the same distance below the icon
         row regardless of the descriptor beneath it. */
      .stat-numeral-block { margin-top: 20px; }
      .stat-icon-row { display: flex; align-items: center; gap: 9px; }
      .stat-icon-disc {
        width: 26px; height: 26px; border-radius: 50%;
        background: #1F303F; display: flex; align-items: center; justify-content: center; flex-shrink: 0;
      }
      .stat-icon-disc svg { width: 14px; height: 14px; fill: none; stroke: #96D1AA; stroke-width: 2.2; }
      .stat-label { font-size: 11px; font-weight: 700; color: #14524B; }
      .stat-numeral { font-size: 20px; font-weight: 700; line-height: 1.25; }
      .stat-descriptor { font-size: 11px; color: #2E4A3D; }
    "))
  ),

  # Same max-width: 1000px wrapper the original dashboard uses for its tab
  # content (functions/dashboard_module.R) — dropped when this prototype
  # switched to page_sidebar(), restored now on request. The sidebar itself
  # sits outside this constraint, matching the original's own layout.
  div(style = "max-width: 1000px; margin: 0 auto; padding-bottom: 40px;",

    div(class = "brand-header",
      img(src = "aprendia_logo.png", alt = "aprendIA icon"),
      span(class = "brand-word", "the aprendIA dashboard")
    ),

    div(class = "intro-columns",
      p(
        "This dashboard reads usage the way the product team needs to see it: real conversations, not a summary of them, and an onboarding backlog treated as a running audit rather than a finished dataset. Row one covers overall reach, row two covers retention, row three covers the onboarding funnel — each headline sits above the chart or breakdown that explains it."
      ),
      p(
        "Use the sidebar to change the date range. Where a chart splits by cluster, hover any bar, point, or bubble for the number behind it. Cluster labels are real assignments, but they shift between model refits. The onboarding figures further down are read against a backlog currently a little over half complete, and every provisional number is flagged as provisional. Code and data pipeline: ",
        tags$a(href = "https://github.com/ircaprendia/data_pipeline", target = "_blank", "github.com/ircaprendia/data_pipeline"),
        ". aprendIA itself: ",
        tags$a(href = "https://aprendia.io/", target = "_blank", "aprendia.io"),
        "."
      )
    ),

    div(class = "section-heading", "Signs of life — who's still texting back?"),
    p(class = "section-intro",
      "A chatbot's health is measured in whether anyone still reaches for it. The four figures below are the plainest evidence available — how many teachers actually came back this week, and whether that's more of them or fewer than the week before. The charts beneath ask the same question over a longer stretch: is the total climbing, holding its ground, or going quiet."
    ),
    div(class = "last-updated", paste("Figures below as of", format(scalars$max_date, "%d %b %Y"))),

    div(class = "card-row",
      stat_card("M12 2a5 5 0 100 10 5 5 0 000-10zM4 21c0-4 3.5-7 8-7s8 3 8 7",
                "Total users", paste(comma(scalars$total_users), "teachers"),
                "have used aprendIA since launch"),
      stat_card("M4 12l5 5L20 6",
                "Active teachers", paste(comma(scalars$active_7d), "active users"),
                paste0("in the past 7 days (", delta_label(scalars$active_delta_pct), ")")),
      stat_card("M13 2L4 14h6l-1 8 9-12h-6l1-8z",
                "New users", paste(comma(scalars$new_users_7d), "new users"),
                paste0("in the past 7 days (", delta_label(scalars$new_users_delta_pct), ")")),
      stat_card("M3 12h4l3 8 4-16 3 8h4",
                "Messages sent", paste(comma(scalars$incoming_msgs_7d), "messages"),
                "sent to aprendIA in the past 7 days")
    ),

    layout_columns(
      col_widths = 12, gap = "16px",

      card(
        full_screen = TRUE,
        card_header_block(
          "Is aprendIA growing?",
          "Column chart · active users per week",
          control = selectInput("split_by", NULL, choices = c("All users" = "none", "By cluster" = "cluster"),
                                 selected = "none", width = "190px")
        ),
        card_body(padding = "10px", style = "background: #F8F9FA;",
          p(class = "chart-desc",
            "How many active users of aprendIA there are per week — an active user is someone who sends at least one message. Switch to \"by cluster\" to see whether power users and occasional users follow different trajectories. Cluster labels are less stable than the raw total (see note below when selected)."
          ),
          # Fixed native size now (rescale = FALSE) — height set to match
          # CHART_HEIGHT_PX tightly so there's no dead space below the chart,
          # width left unconstrained inside a horizontally-scrolling wrapper
          # rather than shrinking the chart to fit a narrow window.
          div(style = "overflow-x: auto; overflow-y: hidden;",
            girafeOutput("active_users_chart", height = paste0(CHART_HEIGHT_PX, "px"))
          )
        )
      ),

      card(
        full_screen = TRUE,
        card_header_block("How many teachers are arriving?", "Column chart · new users per week"),
        card_body(padding = "10px", style = "background: #F8F9FA;",
          p(class = "chart-desc",
            "Teachers sending their first-ever message that week. This can only rise or hold — it won't show anyone leaving, which is what the retention section (Row 2) is for."
          ),
          div(style = "overflow-x: auto; overflow-y: hidden;",
            girafeOutput("new_users_chart", height = paste0(CHART_HEIGHT_PX, "px"))
          )
        )
      )
    ),

    div(class = "section-heading", "The long silence — who stays, and who goes quiet?"),
    p(class = "section-intro",
      "Everyone who arrives does, eventually, one of two things: keeps texting, or stops. This section follows the quieter of those two facts. A teacher who goes fourteen days without a message is counted as gone, silent long enough that we stop counting on them. The curve below shows how many are still there at each day since they first got in touch; the trajectories beside it show one teacher's actual use, message by message, an individual case rather than an average."
    ),
    div(class = "last-updated", "Cohort boxes use teachers with 29+ days' tenure, so every member has had the full window to be observed."),

    div(class = "card-row",
      stat_card("M4 12l5 5L20 6",
                "Week 1 users", paste(comma(row2_scalars$week1_active), "users"),
                "active 6+ hours after joining, within their first week"),
      stat_card("M4 12l5 5L20 6",
                "Week 2 users", paste(comma(row2_scalars$week2_active), "users"),
                "active in days 8–14"),
      stat_card("M4 12l5 5L20 6",
                "Weeks 3–4 users", paste(comma(row2_scalars$weeks3_4_active), "users"),
                "active in days 15–28"),
      stat_card("M3 12h4l3 8 4-16 3 8h4",
                "Churned", paste(comma(row2_scalars$n_churned_7d), "churned users"),
                "14+ days quiet in the past 7 days")
    ),

    layout_columns(
      col_widths = 12, gap = "16px",

      card(
        full_screen = TRUE,
        card_header_block(
          "How long do teachers stick around?",
          "Survival curve · probability of still engaging after n active days, fitted with a Kaplan-Meier model",
          control = selectInput("survival_split", NULL,
                                 choices = c("Total" = "total", "By cluster" = "cluster"),
                                 selected = "total", width = "190px")
        ),
        card_body(padding = "10px", style = "background: #F8F9FA;",
          p(class = "chart-desc",
            "Of all the teachers who started using aprendIA, what percentage are still engaging after 7, 14, or 30 active days? A steep early drop means many teachers try the bot a few times and leave. \"Active days\" counts days with a message, not calendar days since joining; a teacher is treated as churned once 14 days pass with no message."
          ),
          div(style = "overflow-x: auto; overflow-y: hidden;",
            girafeOutput("survival_chart", height = paste0(CHART_HEIGHT_PX, "px"))
          )
        )
      ),

      card(
        full_screen = TRUE,
        card_header_block(
          "What does a user journey look like?",
          "Trajectory chart · cumulative messages sent, by cluster",
          control = sliderInput("traj_n", "Sample per group",
                                 min = 10, max = 100, value = 50, step = 10, ticks = FALSE, width = "190px")
        ),
        card_body(padding = "10px", style = "background: #F8F9FA;",
          p(class = "chart-desc",
            "Each faint line is one teacher's cumulative count of messages sent TO aprendIA since their first message — fixed here to exclude the bot's own replies, unlike the real dashboard's current version. Split by real cluster."
          ),
          div(style = "overflow-x: auto; overflow-y: hidden;",
            girafeOutput("trajectory_chart", height = paste0(TRAJ_HEIGHT_PX, "px"))
          )
        )
      )
    ),

    div(class = "section-heading", "The narrow door — how far do teachers get?"),
    p(class = "section-intro",
      "Every onboarding attempt behind these numbers has been read in full, start to finish, by an extraction agent working the same transcript a human coder would. A sample of that work is read a second time, independently, to check agreement between the two reads — about 84 times in 100 at last count. The backlog is a little over half complete, and the categories below, the reasons an onboarding attempt stalled or never began at all, have already been rewritten four times as new, stranger cases turned up in the transcripts. This row will keep shifting as the backlog closes — treat it as a running account."
    ),
    div(class = "last-updated", "Recomputed fresh against the current onboarding_schema ledger — not the redesign plan's earlier placeholder snapshot."),

    div(class = "card-row",
      stat_card("M4 12l5 5L20 6",
                "Onboarded successfully", paste(pct_of(row3_scalars$n_completed, row3_scalars$n_total), "of users"),
                paste0("(", comma(row3_scalars$n_completed), " of ", comma(row3_scalars$n_total), " teachers)")),
      stat_card("M13 2L4 14h6l-1 8 9-12h-6l1-8z",
                "Started, didn't complete", paste(pct_of(row3_scalars$n_started_nc, row3_scalars$n_total), "of users"),
                paste0("(", comma(row3_scalars$n_started_nc), " of ", comma(row3_scalars$n_total), " teachers)")),
      stat_card("M3 12h4l3 8 4-16 3 8h4",
                "Never started", paste(pct_of(row3_scalars$n_never, row3_scalars$n_total), "of users"),
                paste0("(", comma(row3_scalars$n_never), " of ", comma(row3_scalars$n_total), " teachers)")),
      stat_card("M12 2a5 5 0 100 10 5 5 0 000-10zM4 21c0-4 3.5-7 8-7s8 3 8 7",
                "Blocked by a bug \U0001F41B", paste(pct_of(row3_scalars$n_bot_bug_floor, row3_scalars$n_started_nc_denom), "of users"),
                "who started but didn't finish were blocked by a bug")
    ),

    layout_columns(
      col_widths = c(6, 6), gap = "16px",

      card(
        full_screen = TRUE,
        card_header_block("Where do teachers drop out of onboarding?", "Waterfall · all contacts to completed"),
        card_body(padding = "10px", style = "background: #F8F9FA;",
          p(class = "chart-desc",
            "Bridges from all contacts down to those who completed onboarding, via the two ways of not finishing. No target exists for any stage."
          ),
          div(style = "overflow-x: auto; overflow-y: hidden;",
            girafeOutput("row3_waterfall", height = paste0(ROW3_CHART_HEIGHT_PX, "px"))
          )
        )
      ),

      card(
        full_screen = TRUE,
        card_header_block("Why did onboarding never happen?", "Bubble chart · reason, among teachers who never started"),
        card_body(padding = "10px", style = "background: #F8F9FA;",
          p(class = "chart-desc",
            "Categories from the zero-match extraction — not mutually exclusive in the underlying conversations, but each contact is assigned its single highest-priority reason. Hover a bubble for its label and count."
          ),
          div(style = "overflow-x: auto; overflow-y: hidden;",
            girafeOutput("row3_breakdown_chart", height = paste0(BUBBLE_HEIGHT_PX, "px"))
          )
        )
      )
    )
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {

  active_filtered <- reactive({
    req(input$date_range)
    data <- if (input$split_by == "cluster") active_users_by_cluster else active_users_total
    data %>% filter(week_date >= input$date_range[1], week_date <= input$date_range[2])
  })

  new_filtered <- reactive({
    req(input$date_range)
    new_users_weekly %>% filter(week_date >= input$date_range[1], week_date <= input$date_range[2])
  })

  output$active_users_chart <- renderGirafe({
    plot_data <- active_filtered()
    pal <- if (input$split_by == "cluster") cluster_pal else c("All users" = full_sample_pal)

    plot_data <- plot_data %>%
      mutate(tooltip = paste0("<b>w/c ", format(week_date, "%e %b"), "</b><br>", cluster, "<br>", comma(active), " active users"))

    p <- ggplot(plot_data, aes(x = week_date, y = active)) +
      geom_col_interactive(aes(tooltip = tooltip, data_id = paste(week, cluster), fill = cluster),
                            alpha = 0.9, position = if (input$split_by == "cluster") "stack" else "identity") +
      scale_fill_manual(values = pal) +
      scale_y_continuous(labels = comma, expand = expansion(mult = c(0, 0.12))) +
      scale_x_date(date_breaks = "8 weeks", date_labels = "%e %b %y", expand = expansion(mult = c(0.02, 0.02))) +
      labs(x = NULL, y = "Active users") +
      dash_theme(base_size = 13) +
      # Override just plot.background from the sourced theme (#F3F5F7) to
      # match the lighter #F8F9FA now used on the surrounding card_body —
      # otherwise the chart still shows a visible seam against its own box.
      theme(plot.background = element_rect(fill = "#F8F9FA", colour = NA),
            # Never a per-chart legend now -- the sidebar's permanent
            # cluster-colour key covers it, so toggling "By cluster" no
            # longer resizes this chart's own plotting area.
            legend.position = "none")

    girafe(ggobj = p, width_svg = CHART_WIDTH_SVG, height_svg = CHART_HEIGHT_SVG, options = girafe_opts)
  })

  output$new_users_chart <- renderGirafe({
    plot_data <- new_filtered() %>%
      mutate(tooltip = paste0("<b>w/c ", format(week_date, "%e %b"), "</b><br>", comma(new_users), " new users"))

    p <- ggplot(plot_data, aes(x = week_date, y = new_users)) +
      geom_col_interactive(aes(tooltip = tooltip, data_id = week),
                            fill = full_sample_pal, alpha = 0.85) +
      scale_y_continuous(labels = comma, expand = expansion(mult = c(0, 0.12))) +
      scale_x_date(date_breaks = "8 weeks", date_labels = "%e %b %y", expand = expansion(mult = c(0.02, 0.02))) +
      labs(x = NULL, y = "New users") +
      dash_theme(base_size = 13) +
      theme(plot.background = element_rect(fill = "#F8F9FA", colour = NA),
            legend.position = "none")

    girafe(ggobj = p, width_svg = CHART_WIDTH_SVG, height_svg = CHART_HEIGHT_SVG, options = girafe_opts)
  })

  output$survival_chart <- renderGirafe({
    by_cluster <- input$survival_split == "cluster"
    plot_data <- survival_curve %>%
      filter(view == if (by_cluster) "cluster" else "total") %>%
      mutate(
        pct = estimate * 100,
        group_label = if (by_cluster) cluster else "All users",
        tooltip = paste0("<b>Active day ", time, "</b><br>", if (by_cluster) paste0(cluster, "<br>") else "", round(pct, 1), "% still engaging")
      )
    pal <- if (by_cluster) cluster_pal else c("All users" = full_sample_pal)

    p <- ggplot(plot_data, aes(x = time, y = pct, colour = group_label, fill = group_label)) +
      geom_ribbon(aes(ymin = conf.low * 100, ymax = conf.high * 100), alpha = 0.15, colour = NA) +
      geom_step(linewidth = 0.7) +
      geom_point_interactive(aes(tooltip = tooltip, data_id = paste(group_label, time)), size = 1.4, alpha = 0) +
      scale_colour_manual(values = pal) +
      scale_fill_manual(values = pal) +
      scale_y_continuous(labels = function(x) paste0(x, "%"), limits = c(0, 100), expand = expansion(mult = c(0, 0.05))) +
      scale_x_continuous(expand = expansion(mult = c(0.01, 0.02))) +
      coord_cartesian(xlim = c(0, 100)) +
      labs(x = "Active days", y = "Still engaging") +
      dash_theme(base_size = 13) +
      theme(plot.background = element_rect(fill = "#F8F9FA", colour = NA),
            legend.position = "none")

    girafe(ggobj = p, width_svg = CHART_WIDTH_SVG, height_svg = CHART_HEIGHT_SVG, options = girafe_opts)
  })

  output$trajectory_chart <- renderGirafe({
    # Sample per cluster for legibility, matching the real dashboard's own
    # plot_dash_trajectories() convention exactly (functions/dash_visualisations.R):
    # slice_sample() without replacement, fixed seed = 42, n controlled by the
    # same "Sample per group" slider (10-100, default 50, step 10). Tried
    # force-including each cluster's heaviest user plus a bold highlight
    # line for it (2026-09-19) -- reverted, didn't look good in practice.
    set.seed(42)
    sampled_contacts <- trajectory_data %>%
      distinct(contact_id, cluster) %>%
      group_by(cluster) %>%
      slice_sample(n = input$traj_n, replace = FALSE) %>%
      ungroup()
    plot_data <- trajectory_data %>% filter(contact_id %in% sampled_contacts$contact_id)

    # Endpoint dots — same convention as the real dashboard: the lines stay
    # static (too many overlapping lines for hover to be a good target), but
    # each contact's LAST point gets a tooltip with a plain-English summary.
    last_pts <- plot_data %>%
      group_by(contact_id) %>%
      filter(day_lapse == max(day_lapse)) %>%
      ungroup() %>%
      mutate(
        whole_weeks    = day_lapse %/% 7,
        remaining_days = day_lapse %% 7,
        duration_label = paste0(
          whole_weeks, " ", if_else(whole_weeks == 1, "wk", "wks"),
          " and ", remaining_days, " ", if_else(remaining_days == 1, "day", "days")
        ),
        tooltip = paste0(comma(cum_msgs), " msgs over ", duration_label)
      )

    p <- ggplot(plot_data, aes(x = day_lapse, y = cum_msgs, group = contact_id, colour = cluster)) +
      geom_line(alpha = 0.45, linewidth = 0.35) +
      geom_point_interactive(data = last_pts, aes(tooltip = tooltip, data_id = contact_id),
                             alpha = 0.6, size = 1.5) +
      scale_colour_manual(values = cluster_pal) +
      scale_y_continuous(labels = comma) +
      facet_wrap(~ cluster, ncol = 2) +
      labs(x = "Days since first message", y = "Cumulative messages sent to aprendIA") +
      dash_theme(base_size = 13) +
      theme(plot.background = element_rect(fill = "#F8F9FA", colour = NA),
            legend.position = "none",
            strip.background = element_rect(fill = "#F8F9FA", colour = NA))

    girafe(ggobj = p, width_svg = CHART_WIDTH_SVG, height_svg = TRAJ_HEIGHT_SVG, options = girafe_opts)
  })

  output$row3_waterfall <- renderGirafe({
    n_total <- row3_scalars$n_total
    n_never <- row3_scalars$n_never
    n_started_nc <- row3_scalars$n_started_nc
    n_completed <- row3_scalars$n_completed

    # Four bars: two grounded (start/end), two floating "drop" bars in
    # between — geom_rect(), no polygon/tapering math needed.
    wf <- tibble(
      # ggiraph's data_id becomes a literal SVG attribute value -- a plain
      # apostrophe in "didn't" breaks its attribute quoting ("Attribute
      # values cannot contain single quote"). stage_id is apostrophe-free
      # and used ONLY for data_id; stage keeps the readable punctuation for
      # everything else (axis labels, tooltip text).
      # Wrapped onto 2 lines each (not just the longest one) so all four fit
      # side by side at this chart's narrower half-column width without
      # overlapping -- a single-line "All contacts"/"Never started" was
      # wider than the ~1.1in each category actually gets.
      stage_id = c("all", "never_started", "started_nc", "completed"),
      stage = factor(c("All\ncontacts", "Never\nstarted", "Started,\ndidn't\ncomplete", "Completed"),
                      levels = c("All\ncontacts", "Never\nstarted", "Started,\ndidn't\ncomplete", "Completed")),
      xmin = 1:4 - 0.35, xmax = 1:4 + 0.35,
      # Percentage scale, not raw contact counts -- bar heights are now
      # shares of n_total (0-100), matching the labels which were already
      # percentages.
      ymin = c(0, 100 * (n_total - n_never) / n_total, 100 * n_completed / n_total, 0),
      ymax = c(100, 100, 100 * (n_total - n_never) / n_total, 100 * n_completed / n_total),
      # Colour override 2026-09-21: all 4 colours of Sanzo Wada combination
      # 281, alternating dark/light for adjacent-bar contrast, ending on
      # the sage green for "Completed" (an intuitive positive-feeling tone
      # even without a strict red/green loss-gain scheme, which this
      # palette doesn't have).
      fill_col = c("#00978D", "#FFEFAE", "#007190", "#96D1AA"),
      label = c("100%", paste0("−", pct_of(n_never, n_total)), paste0("−", pct_of(n_started_nc, n_total)), pct_of(n_completed, n_total)),
      tooltip = c(
        paste0("<b>All contacts</b><br>", comma(n_total)),
        paste0("<b>Never started</b><br>", comma(n_never), " (", pct_of(n_never, n_total), ")"),
        paste0("<b>Started, didn't complete</b><br>", comma(n_started_nc), " (", pct_of(n_started_nc, n_total), ")"),
        paste0("<b>Completed</b><br>", comma(n_completed), " (", pct_of(n_completed, n_total), ")")
      )
    )

    p <- ggplot(wf) +
      geom_rect_interactive(aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
                                 fill = stage, tooltip = tooltip, data_id = stage_id)) +
      geom_text(aes(x = (xmin + xmax) / 2, y = ymax, label = label), vjust = -0.6, size = 3.3, colour = "#1F303F") +
      scale_fill_manual(values = setNames(wf$fill_col, wf$stage)) +
      scale_x_continuous(breaks = 1:4, labels = levels(wf$stage), expand = expansion(mult = c(0.08, 0.08))) +
      scale_y_continuous(labels = function(x) paste0(x, "%"), limits = c(0, 110), expand = expansion(mult = c(0, 0))) +
      labs(x = NULL, y = "Share of all contacts") +
      dash_theme(base_size = 13) +
      theme(plot.background = element_rect(fill = "#F8F9FA", colour = NA),
            legend.position = "none",
            axis.text.x = element_text(size = 8, lineheight = 0.85))

    girafe(ggobj = p, width_svg = ROW3_CHART_WIDTH_SVG, height_svg = ROW3_CHART_HEIGHT_SVG, options = girafe_opts)
  })

  output$row3_breakdown_chart <- renderGirafe({
    # Packed bubble chart (packcircles) -- no axes, no legend, hover-only
    # labels, per request. sizetype="area" so bubble AREA (not diameter) is
    # proportional to count -- the perceptually-correct convention, since
    # diameter-proportional sizing visually exaggerates small values and
    # flattens large ones.
    #
    # Percentages, not raw counts (The project lead: "it's not from the full dataset
    # yet") -- denominator is the never-started total, matching the "Never
    # started" box above. Colour is a sequential ramp keyed to size, not
    # arbitrary categorical hues -- with no legend, a qualitative colour per
    # bubble would carry no decodable meaning; "darker = more contacts" is
    # readable without one.
    plot_data <- row3_breakdown %>%
      arrange(desc(n)) %>%
      mutate(
        label = ifelse(category %in% names(category_label), category_label[category], category),
        pct = 100 * n / row3_scalars$n_never
      )
    layout <- packcircles::circleProgressiveLayout(plot_data$n, sizetype = "area")
    layout$label <- plot_data$label
    layout$pct   <- plot_data$pct
    layout$tooltip <- paste0("<b>", plot_data$label, "</b><br>", round(plot_data$pct, 1), "%")
    layout$id <- seq_len(nrow(layout))

    verts <- packcircles::circleLayoutVertices(layout, npoints = 60)
    verts <- merge(verts, layout[, c("id", "label", "pct", "tooltip")], by = "id")

    p <- ggplot(verts, aes(x = x, y = y, group = id)) +
      geom_polygon_interactive(aes(tooltip = tooltip, data_id = label, fill = pct),
                                alpha = 0.9, colour = "white", linewidth = 0.8) +
      # Colour override 2026-09-21: a true 2-point gradient (not walking
      # through all 4 Wada hues, which would muddy in the middle) using
      # the two Wada 281 colours NOT already used for clusters -- Pale
      # Lemon Yellow (lightest) to Benzol Green (darkest of the pair),
      # so this chart doesn't reuse either cluster colour either.
      scale_fill_gradient(low = "#FFEFAE", high = "#00978D") +
      scale_x_continuous(expand = expansion(mult = 0.02)) +
      scale_y_continuous(expand = expansion(mult = 0.02)) +
      coord_equal() +
      theme_void() +
      theme(plot.background = element_rect(fill = "#F8F9FA", colour = NA),
            legend.position = "none")

    # Canvas aspect ratio (BUBBLE_WIDTH_SVG/BUBBLE_HEIGHT_SVG) is precomputed
    # once at app start from this same data, matching the packed blob's own
    # width:height rather than forcing a square -- see the comment where
    # those constants are defined. A fixed square canvas left visible white
    # bands on the sides (a reviewer's screenshot): coord_equal() forces 1:1
    # DATA-unit scaling, and a square panel around a non-square blob gets
    # letterboxed to preserve that ratio.
    girafe(ggobj = p, width_svg = BUBBLE_WIDTH_SVG, height_svg = BUBBLE_HEIGHT_SVG, options = girafe_opts)
  })
}

shinyApp(ui, server)
