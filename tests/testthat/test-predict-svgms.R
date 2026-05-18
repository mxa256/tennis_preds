# The SvGms P2-slot regression test CLAUDE.md explicitly defers to
# "Phase 6" (commit dc6616e fixed it in R/predict.R). Pre-fix, the
# P2 SvGms_av feature was sourced from the wrong slot, so a matchup's
# SvGms_av_P_2 did not reflect player 2's actual SvGms form.

make_rolling <- function() {
  # Two recent-form rows. Player A sits in the P_1 slot, B in P_2.
  # A's SvGms form = 10, B's = 20 (distinct so a slot mix-up shows).
  base <- function(p1, p2, svg1, svg2, date, rd) data.frame(
    name_P_1 = p1, name_P_2 = p2,
    rank_P_1 = 5, rank_P_2 = 8,
    ht_P_1 = 185, ht_P_2 = 190,
    age_P_1 = 27, age_P_2 = 24,
    set_tot_av_P_1 = 1.8, set_tot_av_P_2 = 1.6,
    ace_av_P_1 = 7, ace_av_P_2 = 9,
    df_av_P_1 = 2, df_av_P_2 = 3,
    svpt_av_P_1 = 70, svpt_av_P_2 = 75,
    X1stIn_av_P_1 = 42, X1stIn_av_P_2 = 45,
    X1stWon_av_P_1 = 33, X1stWon_av_P_2 = 30,
    X2ndWon_av_P_1 = 12, X2ndWon_av_P_2 = 14,
    SvGms_av_P_1 = svg1, SvGms_av_P_2 = svg2,
    tourney_date_P_1 = date, rank_diff = rd,
    stringsAsFactors = FALSE
  )
  rbind(
    base("A", "B", 10, 20, 20240501, -3),
    base("C", "D", 99, 88, 20240502,  4)  # gives rank_diff sd > 0
  )
}

test_that("prepare_features maps SvGms_av to the correct player slot", {
  f <- prepare_features("A", "B", make_rolling())
  expect_equal(f$SvGms_av_P_1, 10)   # player 1 (A) form
  expect_equal(f$SvGms_av_P_2, 20)   # player 2 (B) form -- the bug slot
  expect_false(isTRUE(all.equal(f$SvGms_av_P_1, f$SvGms_av_P_2)))
})

test_that("swapping the players swaps the SvGms slots", {
  f <- prepare_features("B", "A", make_rolling())
  expect_equal(f$SvGms_av_P_1, 20)   # now B is player 1
  expect_equal(f$SvGms_av_P_2, 10)   # now A is player 2
})
