# Step 7a: train the FINAL production model on ALL leak-free data and
# promote it to models/model.rds.
#
# The time-based holdout (analysis/train_model.R) already produced the
# honest performance estimate (~0.856 / 0.76 competitive). Standard
# practice: once that estimate exists and the model/params are locked,
# retrain the final model on ALL available data so the served model
# benefits from the most recent matches -- important for a temporal
# model that will predict FUTURE seasons. We deliberately do NOT
# re-evaluate or quote metrics here; the holdout estimate stands.
#
# Run from project root:  Rscript analysis/train_production_model.R

suppressMessages({
  library(dplyr)
  library(parsnip)
  library(here)
})
set.seed(4242)

train_csv <- read.csv(here::here("data", "data_train.csv"), check.names = FALSE)
ids       <- read.csv(here::here("data", "data_ids.csv"),   check.names = FALSE)
stopifnot(nrow(train_csv) == nrow(ids))

# --- feature prep: byte-identical to analysis/train_model.R so the
#     served schema matches what was evaluated. ------------------------
df <- train_csv
df$.label <- factor(ids$Win_P_1, levels = c(0, 1))

feat <- setdiff(names(df), ".label")
nonfin_frac <- sapply(df[feat], function(c) mean(!is.finite(c)))
degenerate  <- names(nonfin_frac[nonfin_frac > 0.05])
if (length(degenerate)) {
  cat("dropping degenerate features:", paste(degenerate, collapse = ", "), "\n")
  df <- df[, setdiff(names(df), degenerate)]
  feat <- setdiff(names(df), ".label")
}
df[feat] <- lapply(df[feat], function(c) { c[!is.finite(c)] <- NA; c })
names(df)[match(feat, names(df))] <- make.names(feat, unique = TRUE)

cat(sprintf("training final model on ALL %d rows, %d features\n",
            nrow(df), length(feat)))

# Locked baseline params (tuning showed no gain).
spec <- boost_tree(
  mode = "classification",
  trees = 500, tree_depth = 6, learn_rate = 0.05
) %>% set_engine("xgboost")

t0 <- Sys.time()
fit <- spec %>% fit(.label ~ ., data = df)
cat(sprintf("trained in %.1fs\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

# Persist the exact training feature schema alongside the model so the
# serving path can assert parity (prevents silent train/serve drift).
attr(fit, "feature_schema") <- setdiff(names(df), ".label")

# --- promote: back up the old served model, then replace ------------
model_path  <- here::here("models", "model.rds")
legacy_path <- here::here("models", "model_legacy.rds")
if (file.exists(model_path) && !file.exists(legacy_path)) {
  file.copy(model_path, legacy_path)
  cat("backed up previous model -> models/model_legacy.rds\n")
}
saveRDS(fit, model_path)
cat("promoted -> models/model.rds (production, trained on all data)\n")
cat("NOTE: not re-evaluated by design; honest estimate is the holdout.\n")
