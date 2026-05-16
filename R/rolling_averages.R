# Convert match-level rows into per-player trailing form averages.
#
# At prediction time we never have a match's own stats -- only how each
# player has performed recently. So we reshape wide -> long (one row per
# player per match), take a 30-match trailing mean per player with
# lag = 1 (the current match is excluded from its own features -- this
# is the leakage guard), then pivot back wide for modelling.
#
# Returns a list with both frames the original kept:
#   $long  -- data7: long, rolled, NOT pivoted (downstream `data_long`)
#   $wide  -- data8: wide, one row per match (downstream modelling frame)
#
# Usage:
#   m  <- assign_player_slots(add_match_stats(add_set_winners(
#           add_set_features(clean_matches(load_atp_matches(2020:2026))))))
#   m  <- add_elo_features(m, compute_player_elos(clean))
#   rr <- add_rolling_averages(m)
#   rr$wide   # -> column pruning (2k); rr$long -> data_long
#
# Behaviour is preserved verbatim from Tennis_Data_Prep.Rmd:1176-1292.
# Two pure diagnostics with no effect on the outputs are intentionally
# dropped (same policy as the dropped View()/dead code earlier): the
# unused `duplicates` group-by summary (Rmd:1214) and the names(data7)
# print (Rmd:1220).
#
# KNOWN-FRAGILE, preserved deliberately (flagged for the retrain phase,
# NOT fixed here): the nrow/2 top/bottom split + `player` reassignment
# (Rmd:1198-1204). The long frame interleaves p1-row/p2-row, so "first
# half" is not "all P_1 rows" and the ifelse(p1_won==1,...) labeling is
# logically suspect. Reproduced exactly. Also: gameswon_perc inherits
# the dataset-wide-scalar bug from match_stats.R and is rolled as-is.
add_rolling_averages <- function(data6) {
  data6 <- data6 %>% dplyr::rename(
    p1_latest_elo = latest_elo_p1,
    p2_latest_elo = latest_elo_p2
  )

  p1 <- names(data6)[grepl("p1_", names(data6)) & names(data6) != "p1_won"]
  p2 <- names(data6)[grepl("p2_", names(data6))]
  info <- names(data6)[!grepl("p1_", names(data6)) & !grepl("p2_", names(data6))]

  new_cols <- c("Win", info, substr(p1, 4, nchar(p1)), "player")

  l <- list()
  # Two rows per match: the p1-slot player (label = p1_won) and the
  # p2-slot player (label = 1 - p1_won).
  for (i in 1:nrow(data6)) {
    l <- c(l, list(c(data6[i, "p1_won"], data6[i, c(info, p1)])))
    l <- c(l, list(c(abs(1 - data6[i, "p1_won"]), data6[i, c(info, p2)])))
  }

  data7 <- as.data.frame(do.call(rbind, l))
  rows_split <- nrow(data7) / 2

  data7_tophalf <- data7[1:(rows_split - 1), ]
  data7_bottomhalf <- data7[rows_split:nrow(data7), ]

  data7_tophalf$player <- ifelse(data7_tophalf$p1_won == 1, "P_1", "P_2")
  data7_bottomhalf$player <- ifelse(data7_bottomhalf$p1_won == 1, "P_2", "P_1")

  data7_tophalf <- as.data.frame(lapply(data7_tophalf, unlist, use.names = TRUE))
  data7_bottomhalf <- as.data.frame(lapply(data7_bottomhalf, unlist, use.names = TRUE))

  data7 <- rbind(data7_tophalf, data7_bottomhalf)

  colnames(data7) <- new_cols

  data7$Win_percent <- data7$Win
  data7 <- as.data.frame(lapply(data7, unlist, use.names = TRUE))
  colnames(data7) <- gsub("^X", "", colnames(data7))

  nums_to_avg <- c(
    "minutes", "set_tot", "ace", "df", "svpt", "1stIn", "1stWon",
    "2ndWon", "SvGms", "bpSaved", "bpFaced", "1st_made", "2ndIn",
    "2nd_made", "1st_serve_perc_win", "2nd_serve_perc_win",
    "1st_serve_rating", "2nd_serve_rating", "1st_effect",
    "return_perc_win", "servewon_perc_total", "returnwon_perc_total",
    "point_dom", "win_bp_perc", "bp_convert_perc", "bp_ratio",
    "setwon_perc", "ptswon_perc", "pts2sets_op_ratio", "gameswon_perc",
    "gmstosets_op_ratio", "ptstogame_op_ratio", "bpwon_perc",
    "bp_op_ratio", "bp_saved_perc", "bp_saved_op_ratio",
    "bp_convert_op_ratio", "ace_perc", "df_perc", "latest_elo",
    "delta_elo", "bof3_odds", "bo5_odds", "upset_scored",
    "upset_against", "Win_percent"
  )

  data7 <- data7 %>% dplyr::mutate_at(nums_to_avg, as.numeric)

  # 30-match trailing mean per player; lag = 1 keeps the current match
  # out of its own features.
  data7 <- data7 %>%
    dplyr::group_by(name) %>%
    dplyr::mutate(dplyr::across(
      .cols = nums_to_avg,
      ~ runner::mean_run(x = ., k = 30, lag = 1),
      .names = "{.col}_av"
    ))

  rolled_up <- c()
  for (i in 1:length(nums_to_avg)) {
    new_value <- paste(nums_to_avg[i], "_av", sep = "")
    rolled_up <- c(rolled_up, new_value)
  }
  rolled_up <- c(nums_to_avg, rolled_up)

  data8 <- data7 %>% tidyr::pivot_wider(
    id_cols = c("tourney_id", "match_num"),
    names_from = "player",
    values_from = c(
      "id", "name", "Win", "tourney_date", "tourney_name",
      "tourney_level", "draw_size", "surface", "score", "best_of",
      "round", "year", "ret", "rank", "rank_points", "set_1", "TB_1",
      "set_2", "TB_2", "set_3", "TB_3", "set_4", "TB_4", "set_5",
      "TB_5", "rank_diff", "seed", "hand", "ht", "age", rolled_up
    )
  )

  list(long = data7, wide = data8)
}
