# aprendIA — full pipeline runner
# Universal data prep runs once across all countries, then each country's dashboard.
# Nigeria adds classification + clustering before its dashboard. Run interactively:
# clustering stops for manual review if any group resolves to k > 2 (see nigeria/04_cluster.R).

# ── Data prep (universal, all countries) ──
source("scripts/update_repository.R")   # refresh repository CSV + off-machine backup
source("scripts/00_load_raw_data.R")
source("scripts/01_clean.R")
source("scripts/02_aggregate.R")

# ── Ecuador ──
source("scripts/ecuador/05_dashboard.R")

# ── Niger ──
source("scripts/niger/05_dashboard.R")

# ── Nigeria ──
source("scripts/nigeria/03_classify.R")
source("scripts/nigeria/04_cluster.R")
source("scripts/nigeria/05_dashboard.R")

# ── Deploy both live dashboards ──
# Pushes both apps live with no confirmation step in between — ideally run
# this line manually (on its own, after reviewing the pipeline's other
# output) rather than letting it fire as part of an unattended full run.
source("scripts/deploy_shiny_code.R")
