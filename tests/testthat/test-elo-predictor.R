# Guards the calibrated Elo interactive predictor (R/predict_elo.R).
#
# Unit tests run on a small synthetic predictor (deterministic, no
# artifacts needed); integration tests run against the real
# models/elo_predictor.rds and skip cleanly if it hasn't been built
# (fresh clone: run analysis/build_training_data.R +
# analysis/train_elo_predictor.R).

make_synthetic_predictor <- function() {
  set.seed(99)
  n <- 600
  frame <- data.frame(
    d_all    = rnorm(n, 0, 200),
    d_surf   = rnorm(n, 0, 150),
    log_rank = rnorm(n, 0, 1.5),
    is_bo5   = rep(c(0L, 1L), length.out = n)
  )
  lin <- 0.005 * frame$d_all + 0.003 * frame$d_surf + 0.4 * frame$log_rank
  lin <- lin * ifelse(frame$is_bo5 == 1, 1.4, 1)   # Bo5 favours favourites
  frame$y <- rbinom(n, 1, 1 / (1 + exp(-lin)))
  model <- fit_elo_predictor(frame)

  ratings <- data.frame(
    name     = c("Strong", "Weak", "ClaySpecialist", "Unranked"),
    elo_all  = c(2000, 1500, 1800, 1700),
    elo_Hard = c(2000, 1500, 1600, 1700),
    elo_Clay = c(2000, 1500, 1950, 1700),
    elo_Grass = c(2000, 1500, 1500, 1700),
    rank     = c(1, 300, 20, NA),
    stringsAsFactors = FALSE
  )
  list(model = model, ratings = ratings, meta = list())
}

test_that("predictor is exactly antisymmetric and favours the stronger player", {
  pr <- make_synthetic_predictor()
  p_ab <- predict_winner_elo("Strong", "Weak", "Hard", 3, pr)
  p_ba <- predict_winner_elo("Weak", "Strong", "Hard", 3, pr)
  expect_equal(p_ab + p_ba, 1, tolerance = 1e-12)  # by construction
  expect_gt(p_ab, 0.5)
  expect_lt(p_ba, 0.5)
})

test_that("surface-specific rating changes the answer", {
  pr <- make_synthetic_predictor()
  p_hard <- predict_winner_elo("ClaySpecialist", "Weak", "Hard", 3, pr)
  p_clay <- predict_winner_elo("ClaySpecialist", "Weak", "Clay", 3, pr)
  # same players, but the specialist's Clay rating is 350 higher than
  # their Hard rating -> the Clay probability must be higher
  expect_gt(p_clay, p_hard)
})

test_that("invalid inputs fail cleanly", {
  pr <- make_synthetic_predictor()
  expect_error(predict_winner_elo("Nobody XYZ", "Weak", "Hard", 3, pr),
               "Unknown player")
  expect_error(predict_winner_elo("Strong", "Strong", "Hard", 3, pr),
               "must be different")
  expect_error(predict_winner_elo("Strong", "Weak", "Carpet", 3, pr))
  expect_error(predict_winner_elo("Strong", "Weak", "Hard", 4, pr),
               "best_of")
  expect_error(predict_winner_elo("Strong", "Unranked", "Hard", 3, pr),
               "rank")
})

test_that("compute_player_elos exposes current ratings via final_elos", {
  m <- data.frame(
    winner_name   = c("A", "A"),
    loser_name    = c("B", "B"),
    tourney_level = "A",
    tourney_date  = c(20200110, 20200117),
    match_num     = 1:2,
    tourney_id    = "t1",
    stringsAsFactors = FALSE
  )
  e <- compute_player_elos(m)
  fin <- attr(e, "final_elos")
  expect_setequal(fin$name, c("A", "B"))
  # A won both matches: current rating must exceed the last as-of value
  # (as-of stops one result short of current -- the attribute's job)
  expect_gt(fin$elo_final[fin$name == "A"],
            max(e$elo_asof[e$name == "A"]))
  expect_lt(fin$elo_final[fin$name == "B"],
            min(e$elo_asof[e$name == "B"]))
})

test_that("build_ratings_table fills never-played surfaces with 1500", {
  m <- function(w, l) data.frame(
    winner_name = w, loser_name = l, tourney_level = "A",
    tourney_date = 20200110, match_num = 1L, tourney_id = "t1",
    stringsAsFactors = FALSE
  )
  elo_all  <- compute_player_elos(rbind(m("A", "B")))
  elo_surf <- list(Hard = compute_player_elos(m("A", "B")))
  ranks <- data.frame(name = c("A", "B"), rank = c(1, 2))
  tbl <- build_ratings_table(elo_all, elo_surf, ranks)
  expect_setequal(names(tbl), c("name", "elo_all", "elo_Hard", "rank"))
  expect_equal(nrow(tbl), 2)
  # add a Clay walk that only ever saw player C
  elo_surf$Clay <- compute_player_elos(m("C", "A"))
  tbl2 <- build_ratings_table(elo_all, elo_surf, ranks)
  expect_equal(tbl2$elo_Clay[tbl2$name == "B"], 1500)
})

# ---- integration against the real artifact (skips if not built) ----

predictor_path <- here::here("models", "elo_predictor.rds")

test_that("real artifact: sane, antisymmetric, decisive on mismatches", {
  testthat::skip_if_not(file.exists(predictor_path),
                        "models/elo_predictor.rds not built")
  pr <- readRDS(predictor_path)
  expect_true(all(c("model", "ratings", "meta") %in% names(pr)))

  rt <- pr$ratings[!is.na(pr$ratings$rank), ]
  strong <- rt$name[which.max(rt$elo_all)]
  weak   <- rt$name[which.min(rt$elo_all)]
  p_sw <- predict_winner_elo(strong, weak, "Hard", 3, pr)
  p_ws <- predict_winner_elo(weak, strong, "Hard", 3, pr)
  expect_equal(p_sw + p_ws, 1, tolerance = 1e-12)
  expect_gt(p_sw, 0.8)   # biggest possible rating gap: decisive
})
