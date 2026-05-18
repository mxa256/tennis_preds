# testthat auto-sources helper*.R before the test files. This project
# is not an R package -- the R/ files are plain sourced scripts -- so
# the helper loads the runtime libraries and sources R/ in dependency
# order, making every pure function available to the tests.

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(naniar)
  library(stringr)
  library(lubridate)
  library(runner)
  library(fastDummies)
  library(here)
})

for (f in c(
  "impute_heights.R",
  "load_matches.R",
  "parse_score.R",
  "set_winners.R",
  "match_stats.R",
  "assign_player_slots.R",
  "elo.R",
  "rolling_averages.R",
  "prune_columns.R",
  "dummify.R",
  "split_train_ids.R",
  "predict.R"
)) {
  source(here::here("R", f))
}
