library(plumber)
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

# Calibrated Elo interactive predictor (R/predict_elo.R), produced by
# analysis/build_training_data.R + analysis/train_elo_predictor.R.
# Purpose-built for the A-vs-B task (Elo is a player rating, so the
# matchup question is its native task -- no train/serve gap), exactly
# antisymmetric by construction: P(A beats B) + P(B beats A) == 1.
#
# Honest performance (2025-26 time-based holdout): accuracy 0.642,
# AUC 0.701, Brier 0.219, well-calibrated by decile. Tennis is
# genuinely hard to predict -- ~0.64-0.70 is the realistic ceiling
# (bookmakers sit near 0.70) -- so treat probabilities as informed
# estimates, not betting advice. This replaced the leak-era XGBoost
# serving path (see README "Known limitations" history).
source(here::here("R", "predict_elo.R"))
predictor <- readRDS(here::here("models", "elo_predictor.rds"))

#* Predict P(player1 beats player2) in a given match context.
#* @param player1 Character: Name of Player 1
#* @param player2 Character: Name of Player 2
#* @param surface Character: Hard | Clay | Grass (default Hard)
#* @param best_of Integer: 3 or 5 (default 3)
#* @post /predict
function(player1, player2, surface = "Hard", best_of = 3) {
  tryCatch({
    p <- predict_winner_elo(player1, player2, surface,
                            as.integer(best_of), predictor)
    list(
      player1 = player1,
      player2 = player2,
      surface = surface,
      best_of = as.integer(best_of),
      p1_win_probability = round(as.numeric(p), 4),
      disclaimer = paste(
        "Calibrated Elo + ranking model (holdout: 0.64 accuracy,",
        "AUC 0.70). Tennis is hard to predict; probabilities are",
        "informed estimates, not betting advice."
      )
    )
  }, error = function(e) {
    list(error = e$message)
  })
}
