# Guards assign_player_slots (step 2i) + the seed arg the tuning/data
# reproducibility relies on, and the winner->slot correctness that the
# rolling-split fix depended on.

make_raw <- function(n = 10) {
  data.frame(
    match_id = 1:n,
    winner_name = paste0("W", 1:n), loser_name = paste0("L", 1:n),
    winner_rank = 1:n, loser_rank = (2 * n):(n + 1),
    w_ace = 11:(10 + n), l_ace = 1:n,
    ret = "No", stringsAsFactors = FALSE
  )
}

test_that("same seed is reproducible; no-seed path still runs", {
  m <- make_raw()
  expect_identical(
    assign_player_slots(m, seed = 42),
    assign_player_slots(m, seed = 42)
  )
  expect_equal(nrow(assign_player_slots(m)), nrow(m))
})

test_that("label is ~50/50 and winner maps to the correct slot", {
  a <- assign_player_slots(make_raw(20), seed = 7)
  expect_true(all(c("p1_won", "p1_ace", "p2_ace") %in% names(a)))
  expect_gt(mean(a$p1_won), 0.25)
  expect_lt(mean(a$p1_won), 0.75)

  # When p1_won == 1, the p1 slot must carry the WINNER's stats
  # (w_ace was 11..30 -> winners; l_ace 1..20 -> losers).
  won <- a[a$p1_won == 1, ]
  lost <- a[a$p1_won == 0, ]
  expect_true(all(won$p1_ace >= 11))   # winner side
  expect_true(all(lost$p1_ace <= 20))  # loser side
})
