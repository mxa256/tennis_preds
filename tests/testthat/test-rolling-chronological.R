# Regression guard for THE dominant leak (commit 90b6289):
# add_rolling_averages must roll over each player's matches in
# chronological order. Pre-fix it rolled over rows in whatever
# (shuffled) order they arrived -> "trailing form" mixed in future
# matches. The decisive property: the result must be identical whether
# the input rows are pre-sorted or shuffled, and must equal the true
# past-only trailing mean.

build_data6 <- function() {
  stats <- c("minutes","set_tot","ace","df","svpt","1stIn","1stWon",
    "2ndWon","SvGms","bpSaved","bpFaced","1st_made","2ndIn","2nd_made",
    "1st_serve_perc_win","2nd_serve_perc_win","1st_serve_rating",
    "2nd_serve_rating","1st_effect","return_perc_win",
    "servewon_perc_total","returnwon_perc_total","point_dom",
    "win_bp_perc","bp_convert_perc","bp_ratio","setwon_perc",
    "ptswon_perc","pts2sets_op_ratio","gameswon_perc",
    "gmstosets_op_ratio","ptstogame_op_ratio","bpwon_perc",
    "bp_op_ratio","bp_saved_perc","bp_saved_op_ratio",
    "bp_convert_op_ratio","ace_perc","df_perc","delta_elo",
    "bof3_odds","bo5_odds","upset_scored","upset_against")
  pcols <- c("id","name","rank","rank_points","set_1","TB_1","set_2",
    "TB_2","set_3","TB_3","set_4","TB_4","set_5","TB_5","rank_diff",
    "seed","hand","ht","age")
  n <- 6
  d <- data.frame(
    tourney_id = sprintf("T%d", 1:n), match_num = 1:n,
    tourney_date = 20240100 + (1:n), tourney_name = "X",
    tourney_level = "A", draw_size = 32, surface = "Hard",
    score = "6-4 6-4", best_of = 3, round = "R32", year = 2024,
    ret = "No", p1_won = rep(c(1, 0), length.out = n),
    stringsAsFactors = FALSE)
  for (s in stats) {
    # A is always in the p1 slot; A's "ace" rises with match order so
    # the trailing mean is exactly predictable.
    d[[paste0("p1_", s)]] <- if (s == "ace") as.numeric(1:n) else 1
    d[[paste0("p2_", s)]] <- 100 + (1:n)
  }
  for (cc in pcols) {
    d[[paste0("p1_", cc)]] <- if (cc == "name") "A" else 1
    d[[paste0("p2_", cc)]] <- if (cc == "name") "B" else 2
  }
  d$latest_elo_p1 <- 1500 + (1:n)
  d$latest_elo_p2 <- 1600 + (1:n)
  tibble::as_tibble(d)
}

test_that("rolling average is the true past-only trailing mean", {
  rr <- suppressWarnings(add_rolling_averages(build_data6()))
  a <- rr$long[rr$long$name == "A", c("match_num", "ace", "ace_av")]
  a <- a[order(a$match_num), ]
  # lag=1, k=30: match k's value = mean(ace of matches 1..k-1).
  expect_true(is.na(a$ace_av[1]))                 # no prior match
  expect_equal(a$ace_av[2], 1)                    # mean(1)
  expect_equal(a$ace_av[4], 2)                    # mean(1,2,3) -- NOT 2.5
  expect_equal(a$ace_av[6], 3)                    # mean(1..5)
})

test_that("result is independent of input row order (the leak's tell)", {
  d <- build_data6()
  ordered  <- suppressWarnings(add_rolling_averages(d))
  set.seed(99)
  shuffled <- suppressWarnings(add_rolling_averages(d[sample(nrow(d)), ]))

  pick <- function(rr) {
    x <- rr$long[rr$long$name == "A", c("match_num", "ace_av")]
    x[order(x$match_num), "ace_av"]
  }
  # Pre-fix this FAILED: shuffled input produced a different,
  # future-contaminated "trailing" average.
  expect_equal(pick(ordered), pick(shuffled))
})
