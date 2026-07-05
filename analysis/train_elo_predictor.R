# Train, honestly evaluate, and save the calibrated Elo interactive
# predictor (the model behind /predict; see R/predict_elo.R).
#
# Two fits, mirroring the XGBoost scripts' discipline:
#   1. evaluation fit on <=2024 rows -> honest 2025-26 holdout metrics
#      (the bar to beat: 0.640 = "better ATP rank wins")
#   2. production fit on ALL labelled rows -> saved with the current
#      per-player ratings table as models/elo_predictor.rds
#
# Run from project root (needs data/data_ids.csv +
# data/serving_features.csv from analysis/build_training_data.R):
#   Rscript analysis/train_elo_predictor.R

suppressMessages({
  library(dplyr)
  library(here)
  library(yardstick)
})

src <- function(f) source(here::here("R", f))
src("impute_heights.R")
src("load_matches.R")
src("elo.R")
src("predict_elo.R")

YEARS <- 2020:2026

cat("== Elo walks (overall + per surface) on ATP",
    min(YEARS), "-", max(YEARS), "==\n")
clean    <- clean_matches(load_atp_matches(YEARS))
elo_all  <- compute_player_elos(clean)
elo_surf <- lapply(split(clean, clean$surface), compute_player_elos)

ids <- read.csv(here::here("data", "data_ids.csv"), check.names = FALSE)
ctx <- clean %>%
  distinct(tourney_id, match_num, .keep_all = TRUE) %>%
  select(tourney_id, match_num, surface, best_of)

frame <- build_elo_training_frame(ids, elo_all, elo_surf, ctx)
stopifnot(!anyNA(frame))

# --- 1. honest evaluation: time split, same rows as every other bar ---
yr    <- as.integer(substr(as.character(ids$tourney_date_P_1), 1, 4))
train <- frame[yr <= 2024, ]
hold  <- frame[yr >= 2025, ]

eval_fit <- fit_elo_predictor(train)
prob  <- predict(eval_fit, newdata = hold, type = "response")
truth <- factor(hold$y, levels = c(0, 1))
pred  <- factor(as.integer(prob >= 0.5), levels = c(0, 1))
metrics <- c(
  accuracy = accuracy_vec(truth, pred),
  roc_auc  = roc_auc_vec(truth, prob, event_level = "second"),
  brier    = mean((hold$y - prob)^2)
)

cat(sprintf("\n=== Elo predictor -- 2025-26 holdout (n=%d) ===\n", nrow(hold)))
cat(sprintf("accuracy : %.4f  (bar: 0.640 better-rank / 0.617 leak-free xgb)\n",
            metrics["accuracy"]))
cat(sprintf("roc_auc  : %.4f\n", metrics["roc_auc"]))
cat(sprintf("brier    : %.4f  (0.25 = no-skill coin flip)\n", metrics["brier"]))

# --- 2. production fit on ALL labelled rows + serving artifact ---
model <- fit_elo_predictor(frame)
cat("\nproduction coefficients (fit on all rows):\n")
print(round(coef(model), 5))

serving <- read.csv(here::here("data", "serving_features.csv"),
                    check.names = FALSE)
ranks   <- serving[, c("name", "rank")]
ratings <- build_ratings_table(elo_all, elo_surf, ranks)

predictor <- list(
  model   = model,
  ratings = ratings,
  meta    = list(
    trained_at      = Sys.time(),
    years           = range(YEARS),
    trained_through = max(clean$tourney_date),
    n_train_rows    = nrow(frame),
    holdout_metrics = metrics
  )
)
saveRDS(predictor, here::here("models", "elo_predictor.rds"))
cat(sprintf("\nSaved models/elo_predictor.rds (%d players rated, %d with rank)\n",
            nrow(ratings), sum(!is.na(ratings$rank))))

# sanity: a rivalry, a mismatch, and both orderings summing to 1
sane <- function(a, b) {
  p  <- predict_winner_elo(a, b, "Hard", 3, predictor)
  pr <- predict_winner_elo(b, a, "Hard", 3, predictor)
  cat(sprintf("P(%s beats %s | Hard bo3) = %.3f   [sum with reverse: %.6f]\n",
              a, b, p, p + pr))
}
top2 <- ratings %>% filter(!is.na(rank)) %>% arrange(rank) %>% pull(name)
sane(top2[1], top2[2])
low <- ratings %>% filter(!is.na(rank), rank > 300) %>%
  arrange(desc(rank)) %>% pull(name)
if (length(low)) sane(top2[1], low[1])
