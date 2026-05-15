# Load and clean raw ATP match data.
#
# clean_matches() depends on impute_heights(); source R/impute_heights.R
# before calling it.
#
# Usage:
#   source("R/impute_heights.R")
#   source("R/load_matches.R")
#   matches <- load_atp_matches(2020:2026)
#   matches <- clean_matches(matches)

# Read atp_matches_<year>.csv for each year and row-bind them in
# ascending chronological order. Order matters: the Elo engine consumes
# matches in row order. (The original achieved this ordering via a
# reverse-accumulation loop over a descending year vector; this sorts
# ascending and binds directly for the same result.)
load_atp_matches <- function(
  years,
  data_dir = here::here("..", "tennis_atp-master")
) {
  years <- sort(as.integer(years))
  files <- file.path(data_dir, paste0("atp_matches_", years, ".csv"))
  do.call(rbind, lapply(files, read.csv))
}

# Apply the full cleaning sequence and return the model-ready frame
# (equivalent to the original's `data4`). Steps run in this order
# because impute_heights() must precede the complete-cases filter, or
# rows it would have rescued get dropped first.
clean_matches <- function(matches) {
  # Exhibition events: no ranking points and non-standard scoring.
  matches <- matches %>% dplyr::filter(tourney_name != "NextGen Finals")
  matches <- matches %>% dplyr::filter(tourney_name != "Laver Cup")

  # Seeded players have a missing entry code; mark them "S".
  matches$winner_entry <- ifelse(
    is.na(matches$winner_seed) == FALSE, "S", matches$winner_entry
  )
  matches$loser_entry <- ifelse(
    is.na(matches$loser_seed) == FALSE, "S", matches$loser_entry
  )
  matches <- matches %>%
    naniar::replace_with_na_at(
      .vars = c("winner_entry", "loser_entry"),
      condition = ~ .x == ""
    )

  # Name fixes (trailing space / alternate surname spelling).
  matches$winner_name[matches$winner_name == "Bor Artnak "] <- "Bor Artnak"
  matches$loser_name[matches$loser_name == "Bor Artnak "] <- "Bor Artnak"
  matches$winner_name[matches$winner_name == "Nicolas Alvarez Varona"] <- "Nicolas Alvarez"
  matches$loser_name[matches$loser_name == "Nicolas Alvarez Varona"] <- "Nicolas Alvarez"

  # Most missing seeds are simply unseeded players.
  matches$winner_seed <- replace(
    matches$winner_seed, is.na(matches$winner_seed), 0
  )
  matches$loser_seed <- replace(
    matches$loser_seed, is.na(matches$loser_seed), 0
  )

  matches <- impute_heights(matches)

  matches$ret <- ifelse(
    matches$score == "W/O" | grepl("RET", matches$score), "Yes", "No"
  )

  # Drop near-empty rows, then the unhelpful entry columns, then keep
  # only fully complete rows.
  matches <- matches[rowSums(is.na(matches)) < 20, ]
  matches <- matches %>% dplyr::select(-c("winner_entry", "loser_entry"))
  matches <- matches[complete.cases(matches), ]

  matches
}
