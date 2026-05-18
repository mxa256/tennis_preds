# Step 4b/4c: time-based holdout split + baseline XGBoost refit.
#
# Reads the regenerated data/ CSVs, joins the label, splits by
# CALENDAR DATE (train <= 2024, holdout 2025-2026 YTD -- NOT a random
# split: the rolling-average features make a random split leak future
# form into training), fits a sensible-default XGBoost via parsnip,
# and reports honest holdout metrics.
#
# Run from project root:  Rscript analysis/train_model.R
#
# Deliberately does NOT touch models/model.rds (the live app's model).
# The baseline is written to models/model_baseline.rds; promoting it
# to the served model is a separate, post-evaluation (4d) decision.

suppressMessages({
  library(dplyr)
  library(parsnip)
  library(yardstick)
  library(here)
})

set.seed(4242)

train_csv <- read.csv(here::here("data", "data_train.csv"), check.names = FALSE)
ids       <- read.csv(here::here("data", "data_ids.csv"),   check.names = FALSE)
stopifnot(nrow(train_csv) == nrow(ids))

# Label lives in data_ids (Win_P_1 = did the player in slot p1 win).
df <- train_csv
df$.label <- factor(ids$Win_P_1, levels = c(0, 1))

# Calendar split on the identifier date (YYYYMMDD integer).
yr <- as.integer(substr(as.character(ids$tourney_date_P_1), 1, 4))
is_train <- yr <= 2024
is_test  <- yr >= 2025

# Non-finite handling. The pipeline's ratio features can divide by
# zero on real data (faithful to the original formulas). Observed:
# bp_ratio_av_P_1/P_2 are +Inf in ~83% of rows -- a degenerate
# feature, not a few bad cells. Rule: drop any feature that is
# non-finite in > 5% of rows (no usable signal), and convert the
# remaining sporadic non-finite cells to NA, which XGBoost handles
# natively as missing. This is a modelling-prep decision; the
# bp_ratio root-cause formula fix in match_stats.R is flagged as a
# follow-up (it changes feature definitions -> a deliberate choice,
# not a silent carve mutation).
feat <- setdiff(names(df), ".label")
nonfin_frac <- sapply(df[feat], function(c) mean(!is.finite(c)))
degenerate <- names(nonfin_frac[nonfin_frac > 0.05])
if (length(degenerate)) {
  cat("dropping degenerate (>5% non-finite) features:",
      paste(degenerate, collapse = ", "), "\n")
  df <- df[, setdiff(names(df), degenerate)]
  feat <- setdiff(names(df), ".label")
}
sporadic <- sum(sapply(df[feat], function(c) sum(!is.finite(c))))
if (sporadic > 0) {
  cat("converting", sporadic, "sporadic non-finite cells to NA\n")
  df[feat] <- lapply(df[feat], function(c) {
    c[!is.finite(c)] <- NA
    c
  })
}

# XGBoost needs syntactic predictor names; keep a stable mapping.
names(df)[match(feat, names(df))] <- make.names(feat, unique = TRUE)

train_df <- df[is_train, ]
test_df  <- df[is_test, ]
cat(sprintf("train: %d rows (<=2024)   holdout: %d rows (2025-2026)\n",
            nrow(train_df), nrow(test_df)))
cat(sprintf("label balance  train=%.3f  holdout=%.3f\n",
            mean(train_df$.label == 1), mean(test_df$.label == 1)))

# Baseline params -- deliberately fixed sensible defaults, NOT tuned
# (tuning is a later step, by the user's "baseline first" choice).
spec <- boost_tree(
  mode = "classification",
  trees = 500,
  tree_depth = 6,
  learn_rate = 0.05
) %>% set_engine("xgboost")

t0 <- Sys.time()
fit <- spec %>% fit(.label ~ ., data = train_df)
cat(sprintf("trained in %.1fs\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

prob <- predict(fit, test_df, type = "prob")$.pred_1
pred <- factor(as.integer(prob >= 0.5), levels = c(0, 1))
truth <- test_df$.label

ev <- data.frame(truth = truth, pred = pred, prob = prob)
acc  <- accuracy_vec(ev$truth, ev$pred)
auc  <- roc_auc_vec(ev$truth, ev$prob, event_level = "second")
brier <- mean((as.integer(as.character(ev$truth)) - ev$prob)^2)
cm <- table(truth = ev$truth, pred = ev$pred)

cat("\n=== Baseline XGBoost -- 2025-2026 holdout ===\n")
cat(sprintf("accuracy : %.4f\n", acc))
cat(sprintf("roc_auc  : %.4f\n", auc))
cat(sprintf("brier    : %.4f  (lower=better; 0.25 = no-skill coin flip)\n", brier))
cat("confusion (rows=truth, cols=pred):\n"); print(cm)

saveRDS(fit, here::here("models", "model_baseline.rds"))
cat("\nSaved models/model_baseline.rds (NOT promoted to model.rds)\n")
