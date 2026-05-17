# Trim the rolled frames down to model-ready shape.
#
# Consumes the list returned by add_rolling_averages() and returns:
#   $clean -- wide modelling frame (the original's data_clean): P_2
#             duplicates of shared match info removed, raw (non-_av)
#             stat columns removed, P_1 set-score columns removed,
#             complete cases only.
#   $long  -- compact long frame (the original's data_long).
#
# Usage:
#   rr <- add_rolling_averages(m)
#   pp <- prune_columns(rr)
#   pp$clean   # -> dummify (2l) -> export (2m)
#
# Behaviour preserved verbatim from Tennis_Data_Prep.Rmd:1303-1369.
# Two pure diagnostics with no effect on the outputs are dropped (same
# policy as earlier carves): the dput(names(data8)) print (Rmd:1305)
# and the missingdf %>% View() block (Rmd:1340-1344) -- the latter is
# why this function does not need the monolith's missingfxn.
#
# The bare `select(!vec)` form is kept as-is (faithful; same choice as
# rolling_averages.R). It emits a tidyselect deprecation warning;
# moving to !all_of(vec) is a separate cosmetic cleanup, not a
# behaviour change.
prune_columns <- function(rolled) {
  data8 <- rolled$wide
  data7 <- rolled$long

  # P_2 copies of match-level info that pivot_wider duplicated into
  # both slots (identical to the P_1 copy).
  to_drop <- c(
    "Win_P_2", "tourney_date_P_2", "tourney_name_P_2",
    "tourney_level_P_2", "draw_size_P_2", "surface_P_2", "score_P_2",
    "best_of_P_2", "round_P_2", "year_P_2", "set_1_P_2", "TB_1_P_2",
    "set_2_P_2", "TB_2_P_2", "set_3_P_2", "TB_3_P_2", "set_4_P_2",
    "TB_4_P_2", "set_5_P_2", "TB_5_P_2", "rank_diff_P_2", "minutes_P_2"
  )
  data9 <- data8 %>% dplyr::select(!to_drop)

  # Raw per-match stats: drop, keep only their _av rolling versions
  # (the model trains on form, never the match's own stats).
  to_drop_not_avg <- c(
    "set_tot_P_1", "set_tot_P_2", "ace_P_1", "ace_P_2", "df_P_1",
    "df_P_2", "svpt_P_1", "svpt_P_2", "1stIn_P_1", "1stIn_P_2",
    "1stWon_P_1", "1stWon_P_2", "2ndWon_P_1", "2ndWon_P_2",
    "SvGms_P_1", "SvGms_P_2", "bpSaved_P_1", "bpSaved_P_2",
    "bpFaced_P_1", "bpFaced_P_2", "1st_serve_perc_win_P_1",
    "1st_serve_perc_win_P_2", "2nd_serve_perc_win_P_1",
    "2nd_serve_perc_win_P_2", "1st_serve_rating_P_1",
    "1st_serve_rating_P_2", "2nd_serve_rating_P_1",
    "2nd_serve_rating_P_2", "1st_effect_P_1", "1st_effect_P_2",
    "return_perc_win_P_1", "return_perc_win_P_2", "point_dom_P_1",
    "point_dom_P_2", "bp_convert_perc_P_1", "bp_convert_perc_P_2",
    "bp_ratio_P_1", "bp_ratio_P_2", "setwon_perc_P_1",
    "setwon_perc_P_2", "ptswon_perc_P_1", "ptswon_perc_P_2",
    "pts2sets_op_ratio_P_1", "pts2sets_op_ratio_P_2",
    "gameswon_perc_P_1", "gameswon_perc_P_2", "gmstosets_op_ratio_P_1",
    "gmstosets_op_ratio_P_2", "bpwon_perc_P_1", "bpwon_perc_P_2",
    "bp_op_ratio_P_1", "bp_op_ratio_P_2", "bp_saved_perc_P_1",
    "bp_saved_perc_P_2", "bp_saved_op_ratio_P_1",
    "bp_saved_op_ratio_P_2", "bp_convert_op_ratio_P_1",
    "bp_convert_op_ratio_P_2", "ace_perc_P_1", "ace_perc_P_2",
    "df_perc_P_1", "df_perc_P_2", "latest_elo_P_1", "latest_elo_P_2",
    "delta_elo_P_1", "delta_elo_P_2", "bof3_odds_P_1",
    "bof3_odds_P_2", "bo5_odds_P_1", "bo5_odds_P_2", "upset_scored_P_1",
    "upset_scored_P_2", "upset_against_P_1", "upset_against_P_2",
    "Win_percent_P_1", "Win_percent_P_2"
  )
  data10 <- data9 %>% dplyr::select(!to_drop_not_avg)

  # P_1 set-score columns carry the missing data; drop them.
  to_remove <- c(
    "set_1_P_1", "TB_1_P_1", "set_2_P_1", "TB_2_P_1", "set_3_P_1",
    "TB_3_P_1", "set_4_P_1", "TB_4_P_1", "set_5_P_1", "TB_5_P_1"
  )
  data10 <- data10 %>% dplyr::select(!to_remove)

  data11 <- data10[complete.cases(data10), ]
  data_clean <- data11

  # Compact the long frame for analysis use.
  remove_data7 <- c(
    "ret", "tourney_date", "tourney_id", "tourney_name", "match_num",
    "minutes", "set_1", "TB_1", "set_2", "TB_2", "set_3", "TB_3",
    "set_4", "TB_4", "set_5", "TB_5", "id", "seed", "ioc", "score",
    "ace", "df", "svpt", "1stIn", "1stWon", "2ndWon", "SvGms",
    "bpSaved", "bpFaced", "rank", "rank_points", "1", "2", "3", "4",
    "5", "set1", "set2", "set3", "set4", "set5", "set_tot",
    "1st_made", "2ndIn", "2nd_made", "1st_serve_perc_win",
    "2nd_serve_perc_win", "1st_serve_rating", "2nd_serve_rating",
    "1st_effect", "return_perc_win", "point_dom", "win_bp_perc",
    "bp_convert_perc", "bp_ratio", "setwon_perc", "ptswon_perc",
    "pts2sets_op_ratio", "gameswon_perc", "gmstosets_op_ratio",
    "bpwon_perc", "bp_op_ratio", "bp_saved_perc", "bp_saved_op_ratio",
    "bp_convert_op_ratio", "ace_perc", "df_perc", "upset_scored",
    "upset_against", "latest_elo", "delta_elo", "bof3_odds", "bo5_odds"
  )
  data_long <- data7 %>% dplyr::select(!remove_data7)

  list(clean = data_clean, long = data_long)
}
