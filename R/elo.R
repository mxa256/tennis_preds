# Elo ratings and Elo-derived match odds.
#
# Adapted from https://github.com/sleepomeno/tennis_atp/blob/master/examples/elo.R
# (Sackmann-style adaptive K-factor) plus the best-of-5 conversion from
# https://github.com/JeffSackmann/tennis_misc/blob/master/fiveSetProb.py
#
# Usage:
#   source("R/elo.R")
#   elo_asof <- compute_player_elos(clean_matches)
#   data     <- add_elo_features(data, elo_asof)
#
# LEAKAGE FIX (deviates from the original Tennis_Data_Prep.Rmd Elo
# block, which the prior carve reproduced faithfully): the original
# compute_player_elos returned only each player's FINAL career Elo and
# add_elo_features joined that single value onto every match by name,
# time-blind. That broadcasts end-of-history strength (computed from
# the very matches being predicted, and the future) onto past rows --
# confirmed target leakage (within-player Elo sd was 0; baseline
# accuracy an implausible 0.92). The Elo update math here is UNCHANGED
# and correct; the fix is to return the per-match *pre-match* rating
# (what each player carried INTO the match -- which updateElo already
# computes internally and the original simply discarded) and to join
# it by match identity. Output column names are unchanged so the rest
# of the pipeline is unaffected. Landed as a standalone fix() commit
# (cf. the gameswon_perc / rolling-split fixes).

# Walk every match in row order, updating a running Elo per player.
# Returns the as-of-match rating each player carried INTO each match:
#   name | tourney_id | match_num | elo_asof
compute_player_elos <- function(matches, first_date = as.Date("2018-01-01")) {
  elo_input <- matches[c(
    "winner_name", "loser_name", "tourney_level",
    "tourney_date", "match_num", "tourney_id"
  )]
  elo_input$tourney_date <- as.Date(
    as.character(elo_input$tourney_date),
    format = "%Y%m%d",
    origin = "1900/01/01"
  )

  playersToElo <- new.env(hash = TRUE)
  matchesCount <- new.env(hash = TRUE)

  # Pre-match rating log: two rows per match (winner, loser). Sized
  # up front and filled positionally for speed.
  n <- nrow(elo_input)
  asof_name <- character(2L * n)
  asof_tid  <- character(2L * n)
  asof_mnum <- character(2L * n)  # apply() delivers row values as chr
  asof_elo  <- numeric(2L * n)    # rA/rB are numeric (read from env)
  asof_i    <- 0L

  updateMatchesCount <- function(playerA, playerB) {
    if (is.null(matchesCount[[playerA]])) matchesCount[[playerA]] <- 0
    if (is.null(matchesCount[[playerB]])) matchesCount[[playerB]] <- 0
    matchesCount[[playerA]] <- matchesCount[[playerA]] + 1
    matchesCount[[playerB]] <- matchesCount[[playerB]] + 1
  }

  updateElo <- function(plToElo, playerA, playerB, winner, level,
                        matchDate, matchNum, tid) {
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

    # rA / rB are the ratings each player carried INTO this match --
    # the leakage-free as-of value. Log them before the post-match
    # update is appended.
    asof_i <<- asof_i + 1L
    asof_name[asof_i] <<- playerA
    asof_tid[asof_i]  <<- tid
    asof_mnum[asof_i] <<- matchNum
    asof_elo[asof_i]  <<- rA
    asof_i <<- asof_i + 1L
    asof_name[asof_i] <<- playerB
    asof_tid[asof_i]  <<- tid
    asof_mnum[asof_i] <<- matchNum
    asof_elo[asof_i]  <<- rB

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
    updateElo(playersToElo, row[1], row[2], row[1], row[3], row[4], row[5], row[6])
    return(0)
  }
  updateMatchesCountByRow <- function(row) {
    updateMatchesCount(row[1], row[2])
    return(0)
  }

  apply(elo_input, 1, updateMatchesCountByRow)
  apply(elo_input, 1, computeEloByRow)

  keep <- seq_len(asof_i)
  out <- data.frame(
    name = asof_name[keep],
    tourney_id = asof_tid[keep],
    match_num = as.integer(asof_mnum[keep]),
    elo_asof = asof_elo[keep],
    stringsAsFactors = FALSE
  )

  # Each player's CURRENT rating (after their final match in the data),
  # attached as an attribute: the as-of values above are pre-match by
  # design, so a player's latest as-of row stops one result short of
  # "current". The interactive predictor's serving table needs current.
  # An attribute keeps the return frame (and all existing consumers)
  # unchanged.
  player_names <- ls(playersToElo)
  attr(out, "final_elos") <- data.frame(
    name = player_names,
    elo_final = vapply(
      player_names,
      function(nm) tail(playersToElo[[nm]]$ranking, n = 1),
      numeric(1),
      USE.NAMES = FALSE
    ),
    stringsAsFactors = FALSE
  )
  out
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

# Join each player's as-of-match Elo onto a P1/P2-shaped match frame
# (by name + match identity, NOT the time-blind name-only join the
# original used) and derive the delta + best-of-3 / best-of-5 odds.
# Output column names are unchanged from the original so downstream
# (rolling_averages etc.) is unaffected.
add_elo_features <- function(data, elo_asof) {
  p1 <- elo_asof
  names(p1)[names(p1) == "name"] <- "p1_name"
  names(p1)[names(p1) == "elo_asof"] <- "latest_elo_p1"
  data <- dplyr::left_join(
    data, p1,
    by = c("p1_name", "tourney_id", "match_num")
  )

  p2 <- elo_asof
  names(p2)[names(p2) == "name"] <- "p2_name"
  names(p2)[names(p2) == "elo_asof"] <- "latest_elo_p2"
  data <- dplyr::left_join(
    data, p2,
    by = c("p2_name", "tourney_id", "match_num")
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
