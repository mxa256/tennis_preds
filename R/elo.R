# Elo ratings and Elo-derived match odds.
#
# Adapted from https://github.com/sleepomeno/tennis_atp/blob/master/examples/elo.R
# (Sackmann-style adaptive K-factor) plus the best-of-5 conversion from
# https://github.com/JeffSackmann/tennis_misc/blob/master/fiveSetProb.py
#
# Usage:
#   source("R/elo.R")
#   latest <- compute_player_elos(clean_matches)
#   data   <- add_elo_features(data, latest)

# Walk every match in row order, updating a running Elo per player.
# Returns a data frame of each player's most recent rating:
#   name | latest_elo
#
# `matches` must have columns: winner_name, loser_name, tourney_level,
# tourney_date, match_num. tourney_date is expected in yyyymmdd form.
compute_player_elos <- function(matches, first_date = as.Date("2018-01-01")) {
  elo_input <- matches[c(
    "winner_name", "loser_name", "tourney_level",
    "tourney_date", "match_num"
  )]
  elo_input$tourney_date <- as.Date(
    as.character(elo_input$tourney_date),
    format = "%Y%m%d",
    origin = "1900/01/01"
  )

  playersToElo <- new.env(hash = TRUE)
  matchesCount <- new.env(hash = TRUE)

  updateMatchesCount <- function(playerA, playerB) {
    if (is.null(matchesCount[[playerA]])) matchesCount[[playerA]] <- 0
    if (is.null(matchesCount[[playerB]])) matchesCount[[playerB]] <- 0
    matchesCount[[playerA]] <- matchesCount[[playerA]] + 1
    matchesCount[[playerB]] <- matchesCount[[playerB]] + 1
  }

  updateElo <- function(plToElo, playerA, playerB, winner, level,
                        matchDate, matchNum) {
    rA <- tail(plToElo[[playerA]]$ranking, n = 1)
    rB <- tail(plToElo[[playerB]]$ranking, n = 1)

    if (is.null(rA)) {
      plToElo[[playerA]] <- data.frame(ranking = 1500, date = first_date, num = 0)
      rA <- 1500
    }
    if (is.null(rB)) {
      plToElo[[playerB]] <- data.frame(ranking = 1500, date = first_date, num = 0)
      rB <- 1500
    }

    eA <- 1 / (1 + 10 ^ ((rB - rA) / 400))
    eB <- 1 / (1 + 10 ^ ((rA - rB) / 400))

    if (winner == playerA) {
      sA <- 1
      sB <- 0
    } else {
      sA <- 0
      sB <- 1
    }

    kA <- 250 / ((matchesCount[[playerA]] + 5) ^ 0.4)
    kB <- 250 / ((matchesCount[[playerB]] + 5) ^ 0.4)
    k <- ifelse(level == "G", 1.1, 1)

    rA_new <- rA + (k * kA) * (sA - eA)
    rB_new <- rB + (k * kB) * (sB - eB)

    plToElo[[playerA]] <- rbind(
      plToElo[[playerA]],
      data.frame(ranking = rA_new, date = matchDate, num = matchNum)
    )
    plToElo[[playerB]] <- rbind(
      plToElo[[playerB]],
      data.frame(ranking = rB_new, date = matchDate, num = matchNum)
    )
  }

  computeEloByRow <- function(row) {
    updateElo(playersToElo, row[1], row[2], row[1], row[3], row[4], row[5])
    return(0)
  }
  updateMatchesCountByRow <- function(row) {
    updateMatchesCount(row[1], row[2])
    return(0)
  }

  apply(elo_input, 1, updateMatchesCountByRow)
  apply(elo_input, 1, computeEloByRow)

  names_list <- names(playersToElo)
  latest_elo_ratings <- data.frame()
  for (name in names_list) {
    last_row <- nrow(playersToElo[[name]])
    latest_elo <- playersToElo[[name]][last_row, 1]
    latest_elo_ratings <- rbind(
      latest_elo_ratings,
      data.frame(name = name, latest_elo = latest_elo)
    )
  }
  latest_elo_ratings
}

# Probability the higher-rated player wins a best-of-3 match given the
# Elo difference (delta). Sackmann's standard logistic formula.
elo_odds_3sets <- function(delta) {
  1 - (1 / (1 + (10 ^ ((delta) / 400))))
}

# Convert a best-of-3 win probability into the equivalent best-of-5
# probability (used for Grand Slam matches).
elo_odds_5sets <- function(p3) {
  p1 <- polyroot(c(-1 * p3, 0, 3, -2))[1]
  p5 <- (p1 ^ 3) * (4 - 3 * p1 + (6 * (1 - p1) * (1 - p1)))
  return(p5)
}

# Join latest Elo ratings onto a P1/P2-shaped match frame and derive the
# delta + best-of-3 / best-of-5 odds columns.
add_elo_features <- function(data, latest_elo_ratings) {
  data <- dplyr::left_join(
    data, latest_elo_ratings,
    by = c("p1_name" = "name")
  )
  data <- dplyr::left_join(
    data, latest_elo_ratings,
    by = c("p2_name" = "name"),
    suffix = c("_p1", "_p2")
  )

  data$p1_delta_elo <- data$latest_elo_p1 - data$latest_elo_p2
  data$p2_delta_elo <- data$latest_elo_p2 - data$latest_elo_p1

  data$p1_bof3_odds <- sapply(data$p1_delta_elo, elo_odds_3sets)
  data$p2_bof3_odds <- sapply(data$p2_delta_elo, elo_odds_3sets)

  data$p1_bo5_odds <- as.numeric(sapply(data$p1_bof3_odds, elo_odds_5sets))
  data$p2_bo5_odds <- as.numeric(sapply(data$p2_bof3_odds, elo_odds_5sets))

  # Odds approaching 1 can come back from polyroot slightly negative.
  data$p1_bo5_odds <- ifelse(data$p1_bo5_odds < 0, 1.0, data$p1_bo5_odds)
  data$p2_bo5_odds <- ifelse(data$p2_bo5_odds < 0, 1.0, data$p2_bo5_odds)

  data
}
