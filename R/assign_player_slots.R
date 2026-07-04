# Reshape winner/loser rows into neutral player-1 / player-2 slots and
# build the model target `p1_won`.
#
# The raw data labels every row by outcome (winner_*/w_* vs loser_*/l_*).
# Training on that directly would just learn "the winner column wins".
# This randomly assigns the true winner to the p1 slot in half the rows
# and the p2 slot in the other half, so p1_won is a real prediction
# target rather than a lookup.
#
# Usage:
#   matches <- add_match_stats(add_set_winners(add_set_features(
#                clean_matches(load_atp_matches(2020:2026)))))
#   matches <- assign_player_slots(matches)            # original behaviour
#   matches <- assign_player_slots(matches, seed = 42) # reproducible
#
# Behaviour is preserved from Tennis_Data_Prep.Rmd:946-982. The only
# addition is the optional `seed`: when NULL (default) no set.seed() is
# called, so the shuffle is exactly as random as the original; pass an
# integer to make the split reproducible (needed for the step-6
# testthat regression tests).
assign_player_slots <- function(matches, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)

  # Shuffle all rows, then take a random half for each slot assignment.
  matches <- matches[sample(nrow(matches)), ]
  split <- sort(sample(nrow(matches), nrow(matches) * .5))
  top_half <- matches[split, ]
  bottom_half <- matches[-split, ]

  # Top half: winner -> p1, loser -> p2. Bottom half: the reverse.
  # Order of substitutions is preserved from the original; no column
  # name matches more than one pattern so the order is not load-bearing.
  names(top_half) <- sub("^w_", "p1_", names(top_half))
  names(top_half) <- sub("^winner_", "p1_", names(top_half))
  names(top_half) <- sub("^l_", "p2_", names(top_half))
  names(top_half) <- sub("^loser_", "p2_", names(top_half))

  names(bottom_half) <- sub("^w_", "p2_", names(bottom_half))
  names(bottom_half) <- sub("^winner_", "p2_", names(bottom_half))
  names(bottom_half) <- sub("^l_", "p1_", names(bottom_half))
  names(bottom_half) <- sub("^loser_", "p1_", names(bottom_half))

  # The label: did the player now sitting in the p1 slot win?
  top_half$p1_won <- 1
  bottom_half$p1_won <- 0

  matches <- rbind(top_half, bottom_half)

  # LEAKAGE FIX (third leak; moved here from match_stats.R): rank_diff
  # must be slot-oriented. The original computed it pre-slot as
  # winner_rank - loser_rank, and the prefix renames above never touch
  # it, so the model feature encoded the label (see match_stats.R
  # header). Computing it here, from the slot ranks, gives the same
  # quantity inference builds at serve time (p1$rank - p2$rank in
  # R/predict.R).
  matches$rank_diff <- matches$p1_rank - matches$p2_rank

  # Upset = the lower-ranked (numerically smaller rank) player won.
  matches$p1_upset_scored <- ifelse(matches$p1_rank < matches$p2_rank & matches$p1_won == 1, 1, 0)
  matches$p2_upset_scored <- ifelse(matches$p2_rank < matches$p1_rank & matches$p1_won == 0, 1, 0)
  matches$p1_upset_against <- matches$p2_upset_scored
  matches$p2_upset_against <- matches$p1_upset_scored

  # Retirements/walkovers carry incomplete stats; drop them last so the
  # feature engineering above still saw full rows.
  matches <- matches %>% dplyr::filter(ret == "No")

  matches
}
