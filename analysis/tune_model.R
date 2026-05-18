# Step 4d (experiment): XGBoost hyperparameter tuning with TIME-AWARE
# resampling, evaluated once on the untouched 2025-2026 holdout.
#
# Same leakage discipline as the pipeline fixes: cross-validation
# folds are expanding-window-by-year inside the <=2024 training
# period (train past years -> assess the next), NEVER random k-fold,
# which would reintroduce the future-into-past leak we just removed.
#
# Run from project root:  Rscript analysis/tune_model.R
#
# Writes models/model_tuned.rds (gitignored, NOT promoted). The live
# app's models/model.rds is untouched.

suppressMessages({
  library(dplyr)
  library(parsnip); library(workflows); library(tune)
  library(dials);   library(rsample);   library(yardstick)
  library(here)
})
set.seed(4242)

# --- data prep: identical to analysis/train_model.R --------------------
tr  <- read.csv(here::here("data", "data_train.csv"), check.names = FALSE)
ids <- read.csv(here::here("data", "data_ids.csv"),   check.names = FALSE)
stopifnot(nrow(tr) == nrow(ids))

df <- tr
df$.label <- factor(ids$Win_P_1, levels = c(0, 1))
yr <- as.integer(substr(as.character(ids$tourney_date_P_1), 1, 4))

feat <- setdiff(names(df), ".label")
nonfin_frac <- sapply(df[feat], function(c) mean(!is.finite(c)))
degenerate <- names(nonfin_frac[nonfin_frac > 0.05])
if (length(degenerate)) df <- df[, setdiff(names(df), degenerate)]
feat <- setdiff(names(df), ".label")
df[feat] <- lapply(df[feat], function(c) { c[!is.finite(c)] <- NA; c })
names(df)[match(feat, names(df))] <- make.names(feat, unique = TRUE)

train_df <- df[yr <= 2024, ]
test_df  <- df[yr >= 2025, ]
train_yr <- yr[yr <= 2024]

# --- time-aware resampling: expanding window by year -------------------
# fold k: analysis = years <= Y, assessment = year Y+1.
mk <- function(cut) {
  a <- which(train_yr <= cut)
  b <- which(train_yr == cut + 1)
  rsample::make_splits(list(analysis = a, assessment = b), data = train_df)
}
folds <- rsample::manual_rset(
  list(mk(2021), mk(2022), mk(2023)),
  c("<=2021_assess2022", "<=2022_assess2023", "<=2023_assess2024")
)
cat("time-aware folds (expanding window):\n")
for (i in seq_along(folds$splits)) {
  s <- folds$splits[[i]]
  cat(sprintf("  %-22s analysis=%d  assess=%d\n",
              folds$id[i], length(s$in_id), length(s$out_id)))
}

# --- tunable XGBoost ---------------------------------------------------
spec <- boost_tree(
  mode = "classification",
  trees = tune(), tree_depth = tune(),
  learn_rate = tune(), min_n = tune(),
  loss_reduction = tune()
) %>% set_engine("xgboost")

wf <- workflow() %>% add_model(spec) %>% add_formula(.label ~ .)

grid <- dials::grid_latin_hypercube(
  trees(range = c(300L, 1200L)),
  tree_depth(range = c(3L, 8L)),
  learn_rate(range = c(-2.5, -1)),   # log10 => ~0.003 .. 0.1
  min_n(range = c(5L, 40L)),
  loss_reduction(),
  size = 15
)

cat(sprintf("\ntuning %d candidates x %d folds = %d fits ...\n",
            nrow(grid), nrow(folds), nrow(grid) * nrow(folds)))
t0 <- Sys.time()
res <- tune::tune_grid(
  wf, resamples = folds, grid = grid,
  metrics = metric_set(roc_auc, accuracy),
  control = control_grid(save_pred = FALSE, verbose = FALSE)
)
cat(sprintf("tuned in %.0fs\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))

best <- tune::select_best(res, metric = "roc_auc")
cat("\nbest params (by time-aware CV roc_auc):\n"); print(as.data.frame(best))
cv <- tune::show_best(res, metric = "roc_auc", n = 1)
cat(sprintf("CV roc_auc (mean over folds): %.4f\n", cv$mean))

# --- refit best on FULL <=2024, evaluate ONCE on 2025-26 holdout ------
final_fit <- finalize_workflow(wf, best) %>% fit(data = train_df)
prob <- predict(final_fit, test_df, type = "prob")$.pred_1
pred <- factor(as.integer(prob >= 0.5), levels = c(0, 1))
truth <- test_df$.label
acc   <- accuracy_vec(truth, pred)
auc   <- roc_auc_vec(truth, prob, event_level = "second")
brier <- mean((as.integer(as.character(truth)) - prob)^2)

cat("\n=== Tuned XGBoost -- 2025-2026 holdout ===\n")
cat(sprintf("            tuned      baseline    delta\n"))
cat(sprintf("accuracy :  %.4f     0.8560     %+.4f\n", acc,   acc   - 0.8560))
cat(sprintf("roc_auc  :  %.4f     0.9405     %+.4f\n", auc,   auc   - 0.9405))
cat(sprintf("brier    :  %.4f     0.0998     %+.4f  (lower better)\n", brier, brier - 0.0998))

saveRDS(final_fit, here::here("models", "model_tuned.rds"))
cat("\nSaved models/model_tuned.rds (NOT promoted)\n")
