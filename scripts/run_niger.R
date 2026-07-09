# aprendIA Niger — pipeline runner
# Universal data prep runs across all countries, then the Niger dashboard.

source("scripts/00_load_raw_data.R")
source("scripts/01_clean.R")
source("scripts/02_aggregate.R")
source("scripts/niger/05_dashboard.R")
