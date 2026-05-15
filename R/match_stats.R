# Match-level statistical features: serve/return %, serve ratings,
# point dominance, break-point ratios, over-performance ratios,
# ace/DF rates.
#
# Consumes set_1..set_5 (add_set_features) and w_set_tot/l_set_tot
# (add_set_winners); source those first.
#
# Usage:
#   source("R/load_matches.R"); source("R/parse_score.R")
#   source("R/set_winners.R"); source("R/match_stats.R")
#   matches <- clean_matches(load_atp_matches(2020:2026))
#   matches <- add_match_stats(add_set_winners(add_set_features(matches)))
#
# Behaviour is preserved verbatim from Tennis_Data_Prep.Rmd:813-937.
# Two notes:
#   * The original's set_separator() helper (Rmd:887-889) is dead code
#     -- never called, the score-into-games split uses inline
#     separate() -- so it is intentionally not carried over. No
#     behaviour change.
#   * KNOWN BUG, preserved deliberately: w_gameswon_perc /
#     l_gameswon_perc (Rmd:901-903) wrap the games columns in sum(),
#     collapsing every match to a single dataset-wide scalar instead
#     of a per-match games-won share. That scalar then feeds
#     w/l_gmstosets_op_ratio and w/l_ptstogame_op_ratio. Reproduced
#     exactly here; fixing it is a separate follow-up (it changes
#     model features, so it needs a retrain, not a refactor commit).
add_match_stats <- function(matches) {
  # First/second serve made %.
  matches$w_1st_made <- matches$w_1stIn / matches$w_svpt
  matches$l_1st_made <- matches$l_1stIn / matches$l_svpt

  matches$w_2ndIn <- (matches$w_svpt - matches$w_1stIn - matches$w_df)
  matches$l_2ndIn <- (matches$l_svpt - matches$l_1stIn - matches$l_df)
  matches$w_2nd_made <- matches$w_2ndIn / (matches$w_svpt - matches$w_1stIn)
  matches$l_2nd_made <- matches$l_2ndIn / (matches$l_svpt - matches$l_1stIn)

  # Points won on first / second serve.
  matches$w_1st_serve_perc_win <- matches$w_1stWon / matches$w_svpt
  matches$l_1st_serve_perc_win <- matches$l_1stWon / matches$l_svpt

  matches$w_2nd_serve_perc_win <- matches$w_2ndWon / (matches$w_svpt - matches$w_1stIn)
  matches$l_2nd_serve_perc_win <- matches$l_2ndWon / (matches$l_svpt - matches$l_1stIn)

  # ATP-style serve ratings (>60 great, <30 poor).
  matches$w_1st_serve_rating <- round((matches$w_1st_made * 100) * matches$w_1st_serve_perc_win, 1)
  matches$l_1st_serve_rating <- round((matches$l_1st_made * 100) * matches$l_1st_serve_perc_win, 1)

  matches$w_2nd_serve_rating <- round((matches$w_2nd_made * 100) * matches$w_2nd_serve_perc_win, 1)
  matches$l_2nd_serve_rating <- round((matches$l_2nd_made * 100) * matches$l_2nd_serve_perc_win, 1)

  matches$w_1st_effect <- matches$w_1st_serve_perc_win / matches$w_2nd_serve_perc_win
  matches$l_1st_effect <- matches$l_1st_serve_perc_win / matches$l_2nd_serve_perc_win

  # Return points won %.
  matches$w_return_perc_win <- ((matches$l_1stIn - matches$l_1stWon) + ((matches$l_svpt - matches$l_1stIn) - matches$l_2ndWon - matches$l_df)) / matches$l_svpt
  matches$l_return_perc_win <- ((matches$w_1stIn - matches$w_1stWon) + ((matches$w_svpt - matches$w_1stIn) - matches$w_2ndWon - matches$w_df)) / matches$w_svpt

  # Point dominance ratio.
  matches$w_servewon_perc_total <- (matches$w_1stWon + matches$w_2ndWon) / matches$w_svpt
  matches$w_returnwon_perc_total <- 1 - matches$w_servewon_perc_total

  matches$l_servewon_perc_total <- (matches$l_1stWon + matches$l_2ndWon) / matches$l_svpt
  matches$l_returnwon_perc_total <- 1 - matches$l_servewon_perc_total

  matches$w_point_dom <- matches$w_returnwon_perc_total / matches$l_returnwon_perc_total
  matches$l_point_dom <- matches$l_returnwon_perc_total / matches$w_returnwon_perc_total

  # Break-point win % and conversion ratios.
  matches$w_win_bp_perc <- matches$w_bpSaved / matches$w_bpFaced
  matches$l_win_bp_perc <- matches$l_bpSaved / matches$l_bpFaced

  matches$w_bp_convert_perc <- (matches$l_bpFaced - matches$l_bpSaved) / matches$l_bpFaced
  matches$l_bp_convert_perc <- (matches$w_bpFaced - matches$w_bpSaved) / matches$w_bpFaced

  matches$w_bp_ratio <- matches$w_bp_convert_perc / matches$l_bp_convert_perc
  matches$l_bp_ratio <- matches$l_bp_convert_perc / matches$w_bp_convert_perc

  # Rank difference (winner rank - loser rank).
  matches$rank_diff <- matches$winner_rank - matches$loser_rank

  # Points-to-sets over-performance ratio.
  matches$w_setwon_perc <- matches$w_set_tot / (matches$w_set_tot + matches$l_set_tot)
  matches$w_ptswon_perc <- (matches$w_1stWon + matches$w_2ndWon + matches$l_1stIn - matches$l_2ndWon + (matches$l_svpt - matches$l_1stIn) - matches$l_2ndWon) / (matches$w_svpt + matches$l_svpt)
  matches$w_pts2sets_op_ratio <- matches$w_setwon_perc / matches$w_ptswon_perc

  matches$l_setwon_perc <- matches$l_set_tot / (matches$l_set_tot + matches$w_set_tot)
  matches$l_ptswon_perc <- (matches$l_1stWon + matches$l_2ndWon + matches$w_1stIn - matches$w_2ndWon + (matches$w_svpt - matches$w_1stIn) - matches$w_2ndWon) / (matches$l_svpt + matches$w_svpt)
  matches$l_pts2sets_op_ratio <- matches$l_setwon_perc / matches$l_ptswon_perc

  # Split each set score into games won by each side (TB_n is the
  # leftover tiebreak fragment). set_separator() in the original was
  # dead code; the inline separate() calls are what ran.
  matches <- tidyr::separate(matches, set_1, into = c("w_1", "l_1", "TB_1"), sep = c("-|\\("), remove = FALSE)
  matches <- tidyr::separate(matches, set_2, into = c("w_2", "l_2", "TB_2"), sep = c("-|\\("), remove = FALSE)
  matches <- tidyr::separate(matches, set_3, into = c("w_3", "l_3", "TB_3"), sep = c("-|\\("), remove = FALSE)
  matches <- tidyr::separate(matches, set_4, into = c("w_4", "l_4", "TB_4"), sep = c("-|\\("), remove = FALSE)
  matches <- tidyr::separate(matches, set_5, into = c("w_5", "l_5", "TB_5"), sep = c("-|\\("), remove = FALSE)

  matches <- matches %>%
    dplyr::mutate_at(
      c("w_1", "l_1", "w_2", "l_2", "w_3", "l_3", "w_4", "l_4", "w_5", "l_5"),
      as.numeric
    )

  # Games won % -- see KNOWN BUG note in the file header: sum() makes
  # these dataset-wide scalars, not per-match. Preserved verbatim.
  matches$w_gameswon_perc <- sum(matches$w_1 + matches$w_2 + matches$w_3 + matches$w_4 + matches$w_5, na.rm = T) / sum(matches$w_1 + matches$w_2 + matches$w_3 + matches$w_4 + matches$w_5 + matches$l_1 + matches$l_2 + matches$l_3 + matches$l_4 + matches$l_5, na.rm = T)
  matches$l_gameswon_perc <- sum(matches$l_1 + matches$l_2 + matches$l_3 + matches$l_4 + matches$l_5, na.rm = T) / sum(matches$w_1 + matches$w_2 + matches$w_3 + matches$w_4 + matches$w_5 + matches$l_1 + matches$l_2 + matches$l_3 + matches$l_4 + matches$l_5, na.rm = T)

  # Games-to-sets and points-to-games over-performance ratios.
  matches$w_gmstosets_op_ratio <- matches$w_setwon_perc / matches$w_gameswon_perc
  matches$l_gmstosets_op_ratio <- matches$l_setwon_perc / matches$l_gameswon_perc

  matches$w_ptstogame_op_ratio <- matches$w_gameswon_perc / matches$w_ptswon_perc
  matches$l_ptstogame_op_ratio <- matches$l_gameswon_perc / matches$l_ptswon_perc

  # Break-point over-performance ratios.
  matches$w_bpwon_perc <- (matches$l_bpFaced - matches$l_bpSaved + matches$w_bpSaved) / (matches$w_bpFaced + matches$l_bpFaced)
  matches$w_bp_op_ratio <- matches$w_win_bp_perc / matches$w_ptswon_perc

  matches$l_bpwon_perc <- (matches$w_bpFaced - matches$w_bpSaved + matches$l_bpSaved) / (matches$l_bpFaced + matches$w_bpFaced)
  matches$l_bp_op_ratio <- matches$l_win_bp_perc / matches$l_ptswon_perc

  # Break points saved over-performance ratio.
  matches$w_bp_saved_perc <- matches$w_bpSaved / matches$w_bpFaced
  matches$w_bp_saved_op_ratio <- matches$w_bp_saved_perc / matches$w_servewon_perc_total

  matches$l_bp_saved_perc <- matches$l_bpSaved / matches$l_bpFaced
  matches$l_bp_saved_op_ratio <- matches$l_bp_saved_perc / matches$l_servewon_perc_total

  # Break point converted over-performance ratio.
  matches$w_bp_convert_op_ratio <- matches$w_bp_convert_perc / matches$w_returnwon_perc_total
  matches$l_bp_convert_op_ratio <- matches$l_bp_convert_perc / matches$l_returnwon_perc_total

  # Ace and double-fault rates.
  matches$w_ace_perc <- matches$w_ace / matches$w_svpt
  matches$l_ace_perc <- matches$l_ace / matches$l_svpt

  matches$w_df_perc <- matches$w_df / matches$w_svpt
  matches$l_df_perc <- matches$l_df / matches$l_svpt

  matches
}
