# Regression guard for the gameswon_perc fix (commit 7e77655).
# Pre-fix it wrapped the games columns in sum(), collapsing every
# match to ONE dataset-wide scalar instead of a per-match share.

test_that("gameswon_perc is per-match, not a dataset-wide constant", {
  m <- data.frame(
    tourney_date = c(20240115, 20240620),
    score = c("6-4 6-3", "7-6(5) 4-6 7-5"),
    ret = "No",
    winner_rank = c(3, 10), loser_rank = c(15, 4),
    w_svpt = c(70, 80),  l_svpt = c(65, 85),
    w_1stIn = c(45, 50), l_1stIn = c(40, 55),
    w_1stWon = c(35, 38), l_1stWon = c(30, 40),
    w_2ndWon = c(12, 15), l_2ndWon = c(10, 18),
    w_df = c(2, 3), l_df = c(4, 2),
    w_ace = c(8, 12), l_ace = c(5, 9),
    w_bpSaved = c(3, 5), l_bpSaved = c(2, 4),
    w_bpFaced = c(4, 7), l_bpFaced = c(6, 5),
    stringsAsFactors = FALSE
  )
  m <- add_match_stats(add_set_winners(add_set_features(m)))

  # Two different matches must get two different values (the bug made
  # them identical).
  expect_false(isTRUE(all.equal(m$w_gameswon_perc[1], m$w_gameswon_perc[2])))
  # Match 1 "6-4 6-3": winner 12 games, loser 7 -> 12/19.
  expect_equal(m$w_gameswon_perc[1], 12 / 19)
  # Winner + loser share sums to 1 within a match.
  expect_equal(m$w_gameswon_perc[1] + m$l_gameswon_perc[1], 1)
})
