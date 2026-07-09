# aprendIA — full pipeline runner
# Universal data prep runs once across all countries, then each country's dashboard.
# Nigeria adds classification + clustering before its dashboard. Run interactively:
# clustering stops for manual review if any group resolves to k > 2 (see nigeria/04_cluster.R).

# ── Data prep (universal, all countries) ──
# (A repository-refresh step runs first in the internal setup, absorbing the latest export
#  and backing it up off-machine. It is omitted here because it depends on private storage.)
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
