library(plumber)
library(parsnip)
library(workflows)
library(here)

#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
  res$setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$status <- 200
    return(list())
  } else {
    plumber::forward()
  }
}

# Leak-free production model + per-player latest-form snapshot, both
# produced by analysis/build_training_data.R + train_production_model.R.
# R/predict.R assembles the matchup row in the exact training schema
# (with a hard train/serve parity assert) and symmetrizes over the two
# slot orderings so P(A beats B) + P(B beats A) == 1.
#
# KNOWN LIMITATION (see README "Known limitations"): the model was
# trained/validated on historical match rows; the interactive A-vs-B
# task is a different, harder distribution, so probabilities are only
# weakly discriminative on non-lopsided pairs. This endpoint is
# EXPERIMENTAL, not a calibrated betting tool.
source(here::here("R", "predict.R"))
model   <- readRDS(here::here("models", "model.rds"))
serving <- load_serving_features()

#* Predict P(player1 beats player2) in a given match context.
#* @param player1 Character: Name of Player 1
#* @param player2 Character: Name of Player 2
#* @param surface Character: Hard | Clay | Grass (default Hard)
#* @param best_of Integer: 3 or 5 (default 3)
#* @post /predict
function(player1, player2, surface = "Hard", best_of = 3) {
  tryCatch({
    p <- predict_winner(player1, player2, surface, as.integer(best_of),
                         model, serving)
    list(
      player1 = player1,
      player2 = player2,
      surface = surface,
      best_of = as.integer(best_of),
      p1_win_probability = round(as.numeric(p), 4),
      disclaimer = paste(
        "Experimental. Leak-free model, but trained on historical",
        "match rows; weak discrimination on non-lopsided matchups.",
        "Not a calibrated betting tool."
      )
    )
  }, error = function(e) {
    list(error = e$message)
  })
}
