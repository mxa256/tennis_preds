# Per-set winner/loser flags and total sets won, plus match year.
#
# Consumes the set_1..set_5 columns produced by add_set_features() and
# the `ret` column produced by clean_matches(); source those first.
#
# Usage:
#   source("R/load_matches.R")
#   source("R/parse_score.R")
#   source("R/set_winners.R")
#   matches <- clean_matches(load_atp_matches(2020:2026))
#   matches <- add_set_features(matches)
#   matches <- add_set_winners(matches)
#
# Behaviour is preserved from Tennis_Data_Prep.Rmd:753-807. The
# original recomputed set_1..set_5 here via its own separate(); we
# reuse add_set_features()'s columns instead. This is equivalent:
# winner_set/loser_set integer-parse the leading digits, so the
# original's literal "RET"/"W/O" cells and add_set_features()'s NA
# cells both collapse to NA, and the only is.na()-sensitive column
# (set_5) is non-NA only when ret == "No", which the original's
# branch already gates on.
#
# One intentional deviation: we ungroup() after the rowwise sum. The
# original left data4 as a lingering rowwise_df; returning a clean
# frame is the correct pure-function boundary and changes no feature
# values (only the result's grouping class).

# 1 if the match winner took the set, 0 if the loser did, NA
# otherwise. Only valid for non-tiebreak-decided sets 1-4 (the
# original's documented limitation; behaviour preserved).
set_winner_flag <- function(set_col) {
  dplyr::case_when(
    as.integer(substr(set_col, 1, 1)) > as.integer(substr(set_col, 3, 3)) ~ 1,
    as.integer(substr(set_col, 1, 1)) < as.integer(substr(set_col, 3, 3)) ~ 0
  )
}

set_loser_flag <- function(set_col) {
  dplyr::case_when(
    as.integer(substr(set_col, 1, 1)) < as.integer(substr(set_col, 3, 3)) ~ 1,
    as.integer(substr(set_col, 1, 1)) > as.integer(substr(set_col, 3, 3)) ~ 0
  )
}

add_set_winners <- function(matches) {
  # Extract the match year from tourney_date (YYYYMMDD integer).
  matches$year <- as.Date(
    as.character(matches$tourney_date),
    format = "%Y%m%d", origin = "1964-10-22"
  )
  matches$year <- lubridate::year(matches$year)

  matches <- matches %>%
    dplyr::mutate(
      w_set1 = set_winner_flag(set_1),
      w_set2 = set_winner_flag(set_2),
      w_set3 = set_winner_flag(set_3),
      w_set4 = set_winner_flag(set_4),
      l_set1 = set_loser_flag(set_1),
      l_set2 = set_loser_flag(set_2),
      l_set3 = set_loser_flag(set_3),
      l_set4 = set_loser_flag(set_4)
    )

  # Fifth set has slam-only win-by-two scoring; the match winner by
  # definition took it whenever a fifth set was played to a finish.
  matches$w_set5 <- ifelse(is.na(matches$set_5) == F & matches$ret == "No", 1, NA)
  matches$l_set5 <- ifelse(is.na(matches$set_5) == F & matches$ret == "No", 0, NA)

  # Unplayed sets impute to 0.
  matches <- matches %>%
    dplyr::mutate(
      w_set1 = ifelse(is.na(w_set1), 0, w_set1),
      w_set2 = ifelse(is.na(w_set2), 0, w_set2),
      w_set3 = ifelse(is.na(w_set3), 0, w_set3),
      w_set4 = ifelse(is.na(w_set4), 0, w_set4),
      w_set5 = ifelse(is.na(w_set5), 0, w_set5),
      l_set1 = ifelse(is.na(l_set1), 0, l_set1),
      l_set2 = ifelse(is.na(l_set2), 0, l_set2),
      l_set3 = ifelse(is.na(l_set3), 0, l_set3),
      l_set4 = ifelse(is.na(l_set4), 0, l_set4),
      l_set5 = ifelse(is.na(l_set5), 0, l_set5)
    )

  # Total sets won by each side.
  matches <- matches %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      w_set_tot = sum(w_set1, w_set2, w_set3, w_set4, w_set5, na.rm = T),
      l_set_tot = sum(l_set1, l_set2, l_set3, l_set4, l_set5, na.rm = T)
    ) %>%
    dplyr::ungroup()

  matches
}
