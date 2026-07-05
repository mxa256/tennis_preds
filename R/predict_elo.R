# Interactive A-vs-B predictor: calibrated, surface-blended Elo + rank.
#
# Replaces the XGBoost serving path (R/predict.R), which was built for
# historical match rows and whose apparent skill rode on the rank_diff
# leak (see match_stats.R header). This model is designed FOR the
# interactive task: Elo is a player rating, so an arbitrary A-vs-B
# matchup IS its native question -- no train/serve gap is possible.
#
# Model: logistic regression on four antisymmetric match features
#   d_all    -- overall Elo difference (p1 - p2)
#   d_surf   -- surface-specific Elo difference (p1 - p2)
#   log_rank -- log(rank_p2 / rank_p1), >0 when p1 is better-ranked
#   (each delta also interacts with is_bo5: favourites gain in Bo5)
# fitted WITHOUT an intercept and WITHOUT an is_bo5 main effect. On
# randomly-slotted training rows both terms are slot-bias artifacts
# (their true value is 0), and dropping them makes the predictor
# exactly antisymmetric: P(A beats B) + P(B beats A) == 1 by
# construction -- no post-hoc symmetrization needed.
#
# Honest performance (2025-26 time-based holdout, n = 2913):
# accuracy 0.642, AUC 0.701, Brier 0.219, well-calibrated by decile.
# Bars: "better ATP rank wins" 0.640; leak-free XGBoost 0.617.
#
# Usage:
#   predictor <- readRDS(here::here("models", "elo_predictor.rds"))
#   predict_winner_elo("Jannik Sinner", "Carlos Alcaraz",
#                      "Hard", 3, predictor)

# The four model features for one matchup (or a whole frame, vectorised).
build_elo_matchup_features <- function(elo_all_1, elo_all_2,
                                       elo_surf_1, elo_surf_2,
                                       rank1, rank2, best_of) {
  data.frame(
    d_all    = elo_all_1 - elo_all_2,
    d_surf   = elo_surf_1 - elo_surf_2,
    log_rank = log(rank2 / rank1),
    is_bo5   = as.integer(best_of == 5)
  )
}

# Assemble the labelled training frame from the ids identifier frame,
# the overall + per-surface as-of Elo walks, and per-match context
# (surface, best_of). Joins are by match identity, same discipline as
# add_elo_features. Returns y + the four model features.
build_elo_training_frame <- function(ids, elo_all, elo_surf, ctx) {
  join_slot <- function(d, elo, c1, c2) {
    e1 <- elo
    names(e1) <- c("name_P_1", "tourney_id", "match_num", c1)
    e2 <- elo
    names(e2) <- c("name_P_2", "tourney_id", "match_num", c2)
    d <- dplyr::left_join(d, e1, by = c("name_P_1", "tourney_id", "match_num"))
    dplyr::left_join(d, e2, by = c("name_P_2", "tourney_id", "match_num"))
  }
  d <- join_slot(ids, elo_all, "elo_all_p1", "elo_all_p2")
  d <- join_slot(d, dplyr::bind_rows(elo_surf), "elo_s_p1", "elo_s_p2")
  d <- dplyr::left_join(d, ctx, by = c("tourney_id", "match_num"))

  cbind(
    y = d$Win_P_1,
    build_elo_matchup_features(
      d$elo_all_p1, d$elo_all_p2, d$elo_s_p1, d$elo_s_p2,
      d$rank_P_1, d$rank_P_2, d$best_of
    )
  )
}

# Antisymmetric-terms-only logistic fit (see file header for why no
# intercept / no is_bo5 main effect).
fit_elo_predictor <- function(frame) {
  glm(
    y ~ 0 + d_all + d_surf + log_rank + d_all:is_bo5 + d_surf:is_bo5,
    data = frame, family = binomial()
  )
}

# Per-player serving table: current (post-last-match) overall and
# per-surface ratings + latest known ATP rank. A player who never
# appeared on a surface gets 1500 there -- exactly the rating the
# surface walk itself would hand them entering their first match.
build_ratings_table <- function(elo_all, elo_surf, ranks) {
  tbl <- attr(elo_all, "final_elos")
  if (is.null(tbl)) {
    stop("elo_all lacks the final_elos attribute; recompute with the ",
         "current compute_player_elos.")
  }
  names(tbl)[names(tbl) == "elo_final"] <- "elo_all"
  for (s in names(elo_surf)) {
    f <- attr(elo_surf[[s]], "final_elos")
    names(f) <- c("name", paste0("elo_", s))
    tbl <- merge(tbl, f, by = "name", all.x = TRUE)
  }
  tbl <- merge(tbl, ranks, by = "name", all.x = TRUE)
  for (col in grep("^elo_", names(tbl), value = TRUE)) {
    tbl[[col]][is.na(tbl[[col]])] <- 1500
  }
  tbl
}

.elo_player_row <- function(name, ratings) {
  r <- ratings[ratings$name == name, , drop = FALSE]
  if (nrow(r) == 0) {
    stop(sprintf("Unknown player: '%s' (no rating on record).", name))
  }
  r[1, , drop = FALSE]
}

# Probability that player1 beats player2 in the given context.
# predictor = list(model, ratings, meta) saved by
# analysis/train_elo_predictor.R. Exactly antisymmetric (see header).
predict_winner_elo <- function(player1, player2, surface, best_of,
                               predictor) {
  if (identical(player1, player2)) {
    stop("Player 1 and Player 2 must be different.")
  }
  surface <- match.arg(as.character(surface), c("Hard", "Clay", "Grass"))
  best_of <- as.integer(best_of)
  if (!best_of %in% c(3L, 5L)) stop("best_of must be 3 or 5.")

  p1 <- .elo_player_row(player1, predictor$ratings)
  p2 <- .elo_player_row(player2, predictor$ratings)
  if (is.na(p1$rank)) {
    stop(sprintf("No current ATP rank on record for '%s'.", player1))
  }
  if (is.na(p2$rank)) {
    stop(sprintf("No current ATP rank on record for '%s'.", player2))
  }

  scol <- paste0("elo_", surface)
  nd <- build_elo_matchup_features(
    p1$elo_all, p2$elo_all, p1[[scol]], p2[[scol]],
    p1$rank, p2$rank, best_of
  )
  as.numeric(predict(predictor$model, newdata = nd, type = "response"))
}
