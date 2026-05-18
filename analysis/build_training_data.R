# Orchestration: run the full carved R/ pipeline on real ATP data and
# write the model-ready training/identifier CSVs.
#
# This is the analysis-layer composition of the step-2 pure functions
# (side effects -- reading upstream data, writing CSVs -- live here,
# not in R/). It is the first end-to-end run of the carved pipeline on
# real data.
#
# Run from the project root:
#   Rscript analysis/build_training_data.R
#
# Inputs : ../tennis_atp-master/atp_matches_<year>.csv (2020-2026)
# Outputs: data/data_train.csv, data/data_ids.csv
#
# The 50/50 player-slot assignment is seeded for reproducible training
# data (this is exactly what the seed arg added in step 2i is for).

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

src <- function(f) source(here::here("R", f))
src("impute_heights.R")
src("load_matches.R")
src("parse_score.R")
src("set_winners.R")
src("match_stats.R")
src("assign_player_slots.R")
src("elo.R")
src("rolling_averages.R")
src("prune_columns.R")
src("dummify.R")
src("split_train_ids.R")

SEED <- 1989
YEARS <- 2020:2026

step <- function(label, expr) {
  t0 <- Sys.time()
  out <- force(expr)
  dt <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  msg <- if (is.data.frame(out)) sprintf("%d x %d", nrow(out), ncol(out)) else "ok"
  cat(sprintf("  %-22s %6ss  %s\n", label, dt, msg))
  out
}

cat("Building training data on ATP", min(YEARS), "-", max(YEARS), "\n")

matches <- step("load_atp_matches", load_atp_matches(YEARS))
clean   <- step("clean_matches",    clean_matches(matches))

# Elo is computed from the cleaned winner/loser frame (row order
# matters) BEFORE slot assignment renames those columns away.
latest_elo <- step("compute_player_elos", compute_player_elos(clean))

m <- step("add_set_features",      add_set_features(clean))
m <- step("add_set_winners",       add_set_winners(m))
m <- step("add_match_stats",       add_match_stats(m))
m <- step("assign_player_slots",   assign_player_slots(m, seed = SEED))
m <- step("add_elo_features",      add_elo_features(m, latest_elo))

rolled <- step("add_rolling_averages", add_rolling_averages(m))
pruned <- step("prune_columns",        prune_columns(rolled))
dc     <- step("dummify_clean",        dummify_clean(pruned$clean))
sp     <- step("split_train_ids",      split_train_ids(dc))

write.csv(sp$train, here::here("data", "data_train.csv"), row.names = FALSE)
write.csv(sp$ids,   here::here("data", "data_ids.csv"),   row.names = FALSE)

cat(sprintf("\nWrote data/data_train.csv (%d x %d) and data/data_ids.csv (%d x %d)\n",
            nrow(sp$train), ncol(sp$train), nrow(sp$ids), ncol(sp$ids)))
