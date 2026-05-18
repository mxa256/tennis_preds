# Inference for the production model (step 7b rewrite).
#
# The old 22-feature/scaled path was for the retired leaky-era model.
# The current model is a tidymodels (parsnip) XGBoost workflow on ~102
# leak-free features. At predict time the API only has two player
# names + match context (surface, best_of) -- no match to roll from --
# so each player's MOST RECENT as-of form is read from
# data/serving_features.csv (written by analysis/build_training_data.R)
# and assembled into one matchup row in the EXACT training schema.
#
# A train/serve parity assertion (against the schema attrs the trainer
# stamped on the model) makes a column mismatch fail loudly rather
# than silently produce garbage probabilities.
#
# Usage:
#   model   <- readRDS(here::here("models", "model.rds"))
#   serving <- load_serving_features()
#   predict_winner("Jannik Sinner", "Carlos Alcaraz", "Hard", 3, model, serving)

load_serving_features <- function(
  path = here::here("data", "serving_features.csv")
) {
  read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
}

.player_row <- function(name, serving) {
  r <- serving[serving$name == name, , drop = FALSE]
  if (nrow(r) == 0) {
    stop(sprintf("Unknown player: '%s' (no recent form on record).", name))
  }
  r[1, , drop = FALSE]
}

# Build the single-row model matrix for a p1-vs-p2 matchup on a given
# surface / best_of. Returns a data.frame whose columns are exactly
# the model's training schema, in order.
prepare_features <- function(player1, player2, surface, best_of,
                              serving, model) {
  if (identical(player1, player2)) {
    stop("Player 1 and Player 2 must be different.")
  }
  natural  <- attr(model, "feature_schema_natural")
  modelled <- attr(model, "feature_schema")
  if (is.null(natural) || is.null(modelled)) {
    stop("Model is missing feature_schema attrs; retrain via ",
         "analysis/train_production_model.R")
  }
  surface <- match.arg(as.character(surface), c("Hard", "Clay", "Grass"))
  best_of <- as.integer(best_of)
  if (!best_of %in% c(3L, 5L)) stop("best_of must be 3 or 5.")

  p1 <- .player_row(player1, serving)
  p2 <- .player_row(player2, serving)

  row <- as.data.frame(
    matrix(0, nrow = 1, ncol = length(natural),
           dimnames = list(NULL, natural)),
    check.names = FALSE
  )

  slot_val <- function(snap, base) {
    if (!base %in% names(snap)) {
      stop(sprintf("serving_features lacks column '%s' -- regenerate ",
                   base), "via analysis/build_training_data.R")
    }
    snap[[base]]
  }

  for (f in natural) {
    if (f == "rank_diff") {
      row[[f]] <- p1$rank - p2$rank
    } else if (grepl("^hand_P_1_", f)) {
      row[[f]] <- as.integer(p1$hand == sub("^hand_P_1_", "", f))
    } else if (grepl("^hand_P_2_", f)) {
      row[[f]] <- as.integer(p2$hand == sub("^hand_P_2_", "", f))
    } else if (grepl("^surface_", f)) {
      row[[f]] <- as.integer(sub("^surface_", "", f) == surface)
    } else if (grepl("^best_of_", f)) {
      row[[f]] <- as.integer(sub("^best_of_", "", f) == as.character(best_of))
    } else if (grepl("_P_1$", f)) {
      row[[f]] <- slot_val(p1, sub("_P_1$", "", f))
    } else if (grepl("_P_2$", f)) {
      row[[f]] <- slot_val(p2, sub("_P_2$", "", f))
    } else {
      stop(sprintf("Unmapped serving feature '%s' -- inference/training ",
                   f), "schema drift; reconcile R/predict.R.")
    }
  }

  # Apply the SAME name transform training used, then assert exact
  # parity with the model's expected schema (order included).
  names(row) <- make.names(names(row), unique = TRUE)
  if (!identical(names(row), modelled)) {
    miss <- setdiff(modelled, names(row))
    extra <- setdiff(names(row), modelled)
    stop("train/serve feature parity check FAILED. missing: ",
         paste(miss, collapse = ","), " | extra: ",
         paste(extra, collapse = ","))
  }
  row[, modelled, drop = FALSE]
}

# Probability that player1 beats player2 in the given context.
#
# The model is trained on randomly-slotted (p1/p2) pairs, so XGBoost
# is only approximately symmetric -- feeding the same matchup in the
# two slot orders does not give complementary probabilities (observed
# sums 1.2-1.9). For a coherent head-to-head probability we symmetrize:
# predict BOTH orderings and average player1's win probability across
# them. This is the standard remedy for a pairwise classifier on
# randomized slots; it guarantees predict_winner(A,B)+predict_winner(B,A)
# == 1 and cancels the slot bias.
#
# Note: post-symmetrization, confidence on close matchups is modest by
# design -- that is the honest (leak-free) difficulty of tennis
# prediction (~0.76 on competitive matches). The old model's apparent
# certainty was leakage.
.predict_one <- function(player1, player2, surface, best_of, model, serving) {
  row <- prepare_features(player1, player2, surface, best_of, serving, model)
  as.numeric(predict(model, new_data = row, type = "prob")$.pred_1)
}

predict_winner <- function(player1, player2, surface, best_of,
                           model, serving) {
  fwd <- .predict_one(player1, player2, surface, best_of, model, serving)
  rev <- .predict_one(player2, player1, surface, best_of, model, serving)
  # fwd = P(p1 wins | player1 in slot1); (1 - rev) = P(player1 wins |
  # player1 in slot2). Their mean is the slot-bias-free estimate.
  (fwd + (1 - rev)) / 2
}
