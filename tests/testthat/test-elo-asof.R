# Regression guard for the as-of-match Elo leakage fix (commit ea6acde).
# Pre-fix, compute_player_elos returned each player's FINAL career Elo
# and it was broadcast onto every match -> within-player sd was 0.

make_matches <- function() {
  data.frame(
    winner_name   = c("A", "A", "B", "A"),
    loser_name    = c("B", "B", "A", "B"),
    tourney_level = "A",
    tourney_date  = c(20200110, 20200117, 20200124, 20200131),
    match_num     = c(1L, 2L, 3L, 4L),
    tourney_id    = "t1",
    stringsAsFactors = FALSE
  )
}

test_that("compute_player_elos returns a per-match as-of timeline", {
  e <- compute_player_elos(make_matches())
  expect_setequal(names(e), c("name", "tourney_id", "match_num", "elo_asof"))
  expect_equal(nrow(e), 8) # two rows (winner+loser) per match
})

test_that("within-player Elo varies over time (NOT end-of-history constant)", {
  e <- compute_player_elos(make_matches())
  a <- e$elo_asof[e$name == "A"]
  expect_gt(stats::sd(a), 0)            # the leak's signature was sd == 0
  expect_equal(a[1], 1500)             # first appearance: no prior rating
})

test_that("as-of Elo is strictly pre-match (excludes the current result)", {
  e <- compute_player_elos(make_matches())
  a <- e[e$name == "A", ]
  a <- a[order(a$match_num), ]
  # A wins matches 1,2,4 and loses 3. Rating going INTO match 2 must
  # already reflect the match-1 win (rose above 1500) but the value
  # attached to match 1 must still be the pre-match 1500.
  expect_equal(a$elo_asof[a$match_num == 1], 1500)
  expect_gt(a$elo_asof[a$match_num == 2], 1500)
})

test_that("add_elo_features joins each player's as-of value by match id", {
  e <- compute_player_elos(make_matches())
  slot <- data.frame(
    p1_name = c("A", "B"), p2_name = c("B", "A"),
    tourney_id = "t1", match_num = c(2L, 3L),
    stringsAsFactors = FALSE
  )
  out <- add_elo_features(slot, e)
  expect_true(all(c("latest_elo_p1", "latest_elo_p2",
                     "p1_delta_elo", "p1_bof3_odds", "p1_bo5_odds")
                   %in% names(out)))
  # p1 in row 1 is A at match 2 -> must equal A's as-of for match 2,
  # NOT A's final/any-other-match value.
  expect_equal(
    out$latest_elo_p1[1],
    e$elo_asof[e$name == "A" & e$match_num == 2]
  )
})
