# Guards the step-7b inference path. Replaces test-predict-svgms.R
# (which tested the now-removed 22-feature get_recent_averages path);
# the player->slot correctness it protected is re-asserted here via
# symmetry + a known lopsided ordering.
#
# Integration test against the real production artifacts. They are
# gitignored / regenerable, so skip cleanly if absent (fresh clone:
# run analysis/build_training_data.R + train_production_model.R).

model_path   <- here::here("models", "model.rds")
serving_path <- here::here("data", "serving_features.csv")

skip_if_artifacts_missing <- function() {
  testthat::skip_if_not(
    file.exists(model_path) && file.exists(serving_path),
    "production model / serving_features.csv not built"
  )
}

test_that("model carries the train/serve feature schema attrs", {
  skip_if_artifacts_missing()
  m <- readRDS(model_path)
  expect_true(!is.null(attr(m, "feature_schema")))
  expect_true(!is.null(attr(m, "feature_schema_natural")))
  expect_equal(length(attr(m, "feature_schema")),
               length(attr(m, "feature_schema_natural")))
})

test_that("prepare_features builds exactly the model schema", {
  skip_if_artifacts_missing()
  m  <- readRDS(model_path)
  sf <- load_serving_features()
  two <- head(sf$name, 2)
  row <- prepare_features(two[1], two[2], "Hard", 3, sf, m)
  expect_identical(names(row), attr(m, "feature_schema"))
  expect_equal(nrow(row), 1L)
})

test_that("predict_winner is a valid, symmetric probability", {
  skip_if_artifacts_missing()
  m  <- readRDS(model_path)
  sf <- load_serving_features()
  two <- head(sf$name, 2)
  p_ab <- predict_winner(two[1], two[2], "Hard", 3, m, sf)
  p_ba <- predict_winner(two[2], two[1], "Hard", 3, m, sf)
  expect_gte(p_ab, 0); expect_lte(p_ab, 1)
  # symmetrization guarantee: P(A>B) + P(B>A) == 1 (the slot-bias fix)
  expect_equal(p_ab + p_ba, 1, tolerance = 1e-8)
})

test_that("unknown player and self-match fail cleanly", {
  skip_if_artifacts_missing()
  m  <- readRDS(model_path)
  sf <- load_serving_features()
  known <- sf$name[1]
  expect_error(predict_winner("Nobody XYZ", known, "Hard", 3, m, sf),
               "Unknown player")
  expect_error(predict_winner(known, known, "Hard", 3, m, sf),
               "must be different")
})

test_that("player->slot mapping is correct (swap flips the favourite)", {
  skip_if_artifacts_missing()
  m  <- readRDS(model_path)
  sf <- load_serving_features()
  # strongest vs weakest by recent Elo form -> a decisive ordering
  s <- sf[order(-sf$latest_elo_av), ]
  strong <- s$name[1]; weak <- s$name[nrow(s)]
  p_sw <- predict_winner(strong, weak, "Hard", 3, m, sf)
  p_ws <- predict_winner(weak, strong, "Hard", 3, m, sf)
  expect_gt(p_sw, 0.5)          # strong player favoured as player1
  expect_lt(p_ws, 0.5)          # ... and disfavoured as player1
  expect_equal(p_sw + p_ws, 1, tolerance = 1e-8)
})
