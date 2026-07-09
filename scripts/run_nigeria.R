# aprendIA Nigeria — pipeline runner
# Universal data prep runs across all countries, then the Nigeria-specific steps.
# Run interactively: clustering stops for review if any group resolves to k > 2
# (see nigeria/04_cluster.R), after which update cluster_lookup in config/nigeria_config.R.

source("scripts/00_load_raw_data.R")
source("scripts/01_clean.R")
source("scripts/02_aggregate.R")
source("scripts/nigeria/03_classify.R")
source("scripts/nigeria/04_cluster.R")
source("scripts/nigeria/05_dashboard.R")
