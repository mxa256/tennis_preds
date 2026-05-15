# Fill in missing winner/loser heights from a curated lookup CSV.
#
# Sackmann's atp_players.csv has heights missing for many lower-ranked or
# new players. R/data/player_heights.csv is a hand-compiled patch (heights
# looked up from the ATP website or Google) layered on top via coalesce.
#
# Usage:
#   source("R/impute_heights.R")
#   matches <- impute_heights(matches)

impute_heights <- function(
  matches,
  heights_path = here::here("R", "data", "player_heights.csv")
) {
  heights <- read.csv(heights_path, stringsAsFactors = FALSE)

  matches <- dplyr::left_join(matches, heights, by = c("winner_name" = "Name"))
  matches$winner_ht <- dplyr::coalesce(matches$winner_ht, matches$Height)
  matches$Height <- NULL

  matches <- dplyr::left_join(matches, heights, by = c("loser_name" = "Name"))
  matches$loser_ht <- dplyr::coalesce(matches$loser_ht, matches$Height)
  matches$Height <- NULL

  matches
}
