# Split the dummified frame into model features vs. identifier columns.
#
# Consumes dummify_clean()'s output and returns:
#   $train -- modelling matrix: identifiers removed (the original's
#             data_train).
#   $ids   -- the identifier columns only (the original's data_ids),
#             mergeable back onto predictions by row.
#
# Usage:
#   dc <- dummify_clean(prune_columns(add_rolling_averages(m))$clean)
#   sp <- split_train_ids(dc)
#   # export is a side effect -> caller/analysis layer, e.g.:
#   #   write.csv(sp$train, here::here("data", "data_train.csv"), row.names = FALSE)
#   #   write.csv(sp$ids,   here::here("data", "data_ids.csv"),   row.names = FALSE)
#
# Behaviour preserved from Tennis_Data_Prep.Rmd:1494-1497. The
# `identifiers` vector is carved here (defined at Rmd:1432-1444; only
# consumed by this split). The original's write.csv() calls to
# hardcoded absolute paths (Rmd:1500-1501) are deliberately NOT in
# this pure function: writing is a side effect that belongs in the
# analysis layer per the repo conventions, and the absolute-path
# removal is tracked separately for step 3 (renv + here::here()).
# Bare select(!vec) kept as-is (faithful; same choice as the other
# carves).
split_train_ids <- function(data_clean) {
  identifiers <- c(
    "tourney_id",
    "rank_P_1",
    "rank_P_2",
    "match_num",
    "tourney_date_P_1", # same for both P1 and P2
    "id_P_1",
    "id_P_2",
    "name_P_1",
    "name_P_2",
    "tourney_name",
    "Win_P_1"
  )

  data_ids <- data_clean[identifiers]
  data_train <- data_clean %>% dplyr::select(!identifiers)

  list(train = data_train, ids = data_ids)
}
