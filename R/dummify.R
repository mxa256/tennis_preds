# Rename, one-hot encode categoricals, drop non-model columns.
#
# Consumes prune_columns()$clean and returns the dummified modelling
# frame (the original's post-1486 data_clean), still carrying the
# identifier columns -- the identifier/label split is 2m's job
# (split_train_ids), not this function's.
#
# Usage:
#   pp <- prune_columns(add_rolling_averages(m))
#   dc <- dummify_clean(pp$clean)   # -> split_train_ids (2m)
#
# Behaviour preserved verbatim from Tennis_Data_Prep.Rmd:1413-1486.
# The names(data_clean) diagnostic print (Rmd:1411) is dropped per the
# established policy. The `identifiers` vector (Rmd:1432-1444) is NOT
# here: it is only consumed by the 2m train/ids split, so it lives
# with split_train_ids(). Bare select(!vec) kept as-is (faithful;
# same choice as the other carves).
dummify_clean <- function(data_clean) {
  data_clean <- data_clean %>% dplyr::rename(
    surface = surface_P_1,
    tourney_name = tourney_name_P_1,
    minutes = minutes_P_1,
    rank_diff = rank_diff_P_1,
    best_of = best_of_P_1,
    draw_size = draw_size_P_1
  )

  # Categorical columns to one-hot encode.
  to_dummify <- c("surface", "hand_P_1", "hand_P_2", "best_of")
  data_clean <- fastDummies::dummy_cols(
    data_clean, select_columns = to_dummify
  )

  # Drop: the now-encoded originals, columns unavailable a priori at
  # prediction time (minutes, 1st_made, etc. -- leakage), and
  # non-predictive columns.
  to_drop <- c(
    "tourney_level_P_1", "draw_size", "score_P_1", "round_P_1",
    "year_P_1", "ret_P_1", "ret_P_2", "rank_points_P_1",
    "rank_points_P_2", "seed_P_1", "seed_P_2", "minutes",
    "1st_made_P_1", "1st_made_P_2", "2ndIn_P_1", "2ndIn_P_2",
    "2nd_made_P_1", "2nd_made_P_2", "servewon_perc_total_P_1",
    "servewon_perc_total_P_2", "returnwon_perc_total_P_1",
    "returnwon_perc_total_P_2", "win_bp_perc_P_1", "win_bp_perc_P_2",
    "ptstogame_op_ratio_P_1", "ptstogame_op_ratio_P_2",
    "minutes_av_P_1", "minutes_av_P_2", "surface", "hand_P_1",
    "hand_P_2", "best_of"
  )
  data_clean <- data_clean %>% dplyr::select(!to_drop)

  data_clean
}
