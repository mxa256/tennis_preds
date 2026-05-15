# Parse the raw `score` string into per-set and tiebreak features.
#
# Operates on the cleaned match frame returned by clean_matches()
# (the original's `data3`/`data4`, identical at this point in the
# pipeline). Adds the wide set_1..set_5 columns plus tiebreak
# descriptors; the lean modelling frame keeps `score` untouched
# because separation runs on a copy.
#
# Usage:
#   source("R/load_matches.R")
#   source("R/parse_score.R")
#   matches <- clean_matches(load_atp_matches(2020:2026))
#   matches <- add_set_features(matches)

# Behaviour is preserved verbatim from Tennis_Data_Prep.Rmd:488-528.
# The interactive View() sanity check (Rmd:531) is a side effect and
# stays in the analysis layer, not here.
add_set_features <- function(matches) {
  # Split the score into one column per set, working on a copy so the
  # original `score` string survives for downstream features.
  matches$score_full <- matches$score
  matches <- tidyr::separate(
    matches, score_full,
    into = c("set_1", "set_2", "set_3", "set_4", "set_5"),
    sep = " "
  )

  matches <- matches %>%
    naniar::replace_with_na(replace = list(
      set_1 = c("RET", "W/O"),
      set_2 = "RET",
      set_3 = "RET",
      set_4 = "RET",
      set_5 = "RET"
    ))

  # Tiebreak counts: a "(" marks a recorded tiebreak score; "7-6" is a
  # set the match winner took to a breaker, "6-7" one the loser took.
  matches$num_tbs <- stringr::str_count(matches$score, stringr::fixed("("))
  matches$winner_tb_num <- stringr::str_count(matches$score, stringr::fixed("7-6"))
  matches$loser_tb_num <- stringr::str_count(matches$score, stringr::fixed("6-7"))

  # Per-set tiebreak point score (digits inside the parentheses).
  matches$set_1_tb_score <- as.numeric(regmatches(matches$set_1, gregexpr("(?<=\\().*?(?=\\))", matches$set_1, perl = T)))
  matches$set_2_tb_score <- as.numeric(regmatches(matches$set_2, gregexpr("(?<=\\().*?(?=\\))", matches$set_2, perl = T)))
  matches$set_3_tb_score <- as.numeric(regmatches(matches$set_3, gregexpr("(?<=\\().*?(?=\\))", matches$set_3, perl = T)))
  matches$set_4_tb_score <- as.numeric(regmatches(matches$set_4, gregexpr("(?<=\\().*?(?=\\))", matches$set_4, perl = T)))
  matches$set_5_tb_score <- as.numeric(regmatches(matches$set_5, gregexpr("(?<=\\().*?(?=\\))", matches$set_5, perl = T)))

  # Which side won each set's tiebreak (fifth set has the slam-only
  # 13-12 / 12-13 super-tiebreak scoreline).
  matches$set_1_tb_won <- ifelse(grepl("7-6", matches$set_1), "Winner", ifelse(grepl("6-7", matches$set_1), "Loser", NA))
  matches$set_2_tb_won <- ifelse(grepl("7-6", matches$set_2), "Winner", ifelse(grepl("6-7", matches$set_2), "Loser", NA))
  matches$set_3_tb_won <- ifelse(grepl("7-6", matches$set_3), "Winner", ifelse(grepl("6-7", matches$set_3), "Loser", NA))
  matches$set_4_tb_won <- ifelse(grepl("7-6", matches$set_4), "Winner", ifelse(grepl("6-7", matches$set_4), "Loser", NA))
  matches$set_5_tb_won <- ifelse(grepl("7-6|13-12", matches$set_5), "Winner", ifelse(grepl("6-7|12-13", matches$set_5), "Loser", NA))

  # Whether each set went to a tiebreak at all.
  matches$set_1_had_tb <- ifelse(grepl("7-6", matches$set_1), "Yes", ifelse(grepl("6-7", matches$set_1), "Yes", "No"))
  matches$set_2_had_tb <- ifelse(grepl("7-6", matches$set_2), "Yes", ifelse(grepl("6-7", matches$set_2), "Yes", "No"))
  matches$set_3_had_tb <- ifelse(grepl("7-6", matches$set_3), "Yes", ifelse(grepl("6-7", matches$set_3), "Yes", "No"))
  matches$set_4_had_tb <- ifelse(grepl("7-6", matches$set_4), "Yes", ifelse(grepl("6-7", matches$set_4), "Yes", "No"))
  matches$set_5_had_tb <- ifelse(grepl("7-6|13-12", matches$set_5), "Yes", ifelse(grepl("6-7|12-13", matches$set_5), "Yes", "No"))

  matches
}
