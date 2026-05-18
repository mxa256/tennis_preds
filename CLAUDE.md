# CLAUDE.md

Context for AI assistants (Claude Code etc.) working in this repo.

## What this is

An ATP men's tennis match-outcome predictor. Given two ATP players plus
match context, it returns the probability that player 1 wins. Trained on
Jeff Sackmann's `tennis_atp` match-level data, served via a Plumber R API
plus a static HTML frontend.

Champion model: XGBoost on ~50 engineered features (serve %, return %,
point dominance, break-point conversion, 30-match rolling form averages,
Elo ratings and Elo-derived match odds).

## Layout

```
tennis_preds/
├── R/                      # Pure-function library; sourced by analyses and api.R
│   ├── data/               #   Static lookup tables (e.g. player_heights.csv)
│   ├── refresh_data.R      #   Idempotent git pull/clone of upstream ATP data
│   ├── load_matches.R      #   load_atp_matches / clean_matches — read + clean raw CSVs
│   ├── impute_heights.R    #   impute_heights(matches) — fills winner_ht/loser_ht
│   ├── parse_score.R       #   add_set_features(matches) — set_1..5 + tiebreak features
│   ├── set_winners.R       #   add_set_winners(matches) — per-set flags + sets won
│   ├── match_stats.R       #   add_match_stats(matches) — serve/return/dominance/BP
│   ├── assign_player_slots.R # assign_player_slots(matches, seed) — p1/p2 + label
│   ├── elo.R               #   compute_player_elos / elo_odds_* / add_elo_features
│   ├── rolling_averages.R  #   add_rolling_averages() — 30-match form, lag=1
│   ├── prune_columns.R     #   prune_columns(rolled) → list(clean, long)
│   ├── dummify.R           #   dummify_clean(clean) — one-hot + drop non-model cols
│   ├── split_train_ids.R   #   split_train_ids(clean) → list(train, ids)
│   └── predict.R           #   Inference: get_recent_averages/prepare_features/predict_winner
├── analysis/               # Orchestration + EDA (side effects live here)
│   ├── build_training_data.R #  compose R/ pipeline → data/*.csv
│   ├── train_model.R       #   time-split baseline XGBoost + holdout
│   ├── tune_model.R        #   time-aware hyperparameter search
│   └── eda.qmd             #   lean Quarto EDA (sources R/)
├── tests/testthat/         # Regression suite (run tests/testthat.R)
├── data/                   # Generated training/test CSVs (regenerable from pipeline)
├── models/                 # Saved .rds (model.rds served; *_baseline/_tuned gitignored)
├── mlruns/                 # Legacy MLflow tracking (gitignored)
├── api.R                   # Plumber API serving the XGBoost model
├── index.html              # Static frontend (calls localhost:8000/predict)
└── tennis_preds.Rproj
```

Upstream data lives **outside** the project at `../tennis_atp-master/`
(a real git clone of github.com/JeffSackmann/tennis_atp, fetched by
`R/refresh_data.R`).

## How to run things

From the project root, in R/RStudio:

```r
# Refresh upstream match data from Sackmann's repo
source("R/refresh_data.R")

# Re-run the data prep pipeline (R/ functions composed in analysis/)
Rscript analysis/build_training_data.R

# Train / tune (time-based holdout) and run the regression suite
Rscript analysis/train_model.R
Rscript analysis/tune_model.R
Rscript tests/testthat.R

# Train the final model on ALL data + promote -> models/model.rds
# (model .rds are gitignored; run this once on a fresh clone)
Rscript analysis/train_production_model.R

# Serve the prediction API on port 8000
plumber::pr_run(plumber::pr("api.R"))
```

## Conventions

- **Pure functions live in `R/`**, sourced by analyses. Side effects (reading
  data, plotting, writing CSVs) stay in the analysis docs.
- **Paths use `here::here("dir", "file")`** rather than absolute paths. Run
  `install.packages("here")` once if missing.
- **Data is fetched, not snapshotted.** Don't commit match-data CSVs from
  upstream — `R/refresh_data.R` re-syncs them. Small curated lookups like
  `R/data/player_heights.csv` are fine to commit.
- **The 7-step refactor is complete** (see Refactor status). The carve
  discipline still governs future changes to `R/`: preserve behaviour
  in mechanical moves; genuine bugs get their own clearly-labelled
  `fix(...)` commit separate from any faithful extraction (as the
  SvGms / `gameswon_perc` / rolling-split / Elo-leak fixes did).
- **Commit messages: no AI co-author trailer.** Do not append
  `Co-Authored-By: Claude` (or any AI/assistant co-author line) to
  commits in this repo. End the message at its last content line.

## Known issues

- **Three latent bugs found during the carve, all fixed in their own
  `fix()` commits + regression-tested** (`tests/testthat/`):
  `gameswon_perc` dataset-scalar (7e77655), rolling-averages
  player-split (90b6289-era), and the SvGms P2-slot bug in
  `R/predict.R` (dc6616e). The SvGms-specific test was retired in
  step 7 (it covered the now-removed 22-feature inference path); the
  player→slot correctness it guarded is re-asserted by
  `test-inference.R`. The old buggy `deployment_test.Rmd` copy was
  deleted with the legacy notebooks (step 5) — fully resolved.
- **Two target leaks found & fixed in step 4** (the original project's
  headline accuracy was inflated and never caught): end-of-history Elo
  (commit ea6acde) and shuffle-order rolling averages (commit 90b6289,
  the dominant one). Honest leak-free baseline on the 2025–26
  time-based holdout: accuracy ≈ 0.856 (0.95 lopsided / 0.76
  competitive), AUC 0.940. **Never quote pre-fix (~0.92) numbers.**
- **`bp_ratio` is +Inf in ~83% of rows** (divide-by-zero in
  `match_stats.R`). `analysis/train_model.R` drops the degenerate
  `bp_ratio_av_*` columns; a root-cause formula fix is a pending
  deliberate feature change (changes model inputs).
- **Interactive predictor is experimental (train/serve task gap).**
  Model trained/validated on historical match rows; the `/predict`
  A-vs-B task is a different, harder joint distribution. After
  symmetrizing out XGBoost's slot bias, it's weakly discriminative on
  non-lopsided pairs. Model-agnostic (problem framing, not algorithm/
  wiring). Shipped labelled experimental; a real interactive model
  (serving-consistent repr / Bradley–Terry-style rating) is future
  work. Old leaky model kept as `models/model_legacy.rds`.
- **`renv` lockfile is lean by design.** `renv.lock` locks the
  `DESCRIPTION` deps + transitive (currently 131 pkgs: runtime +
  tidymodels training stack + testthat). The legacy notebooks' wider
  ML zoo (keras, caret, …) was never locked and those notebooks are
  now deleted (step 5).
- **Hard-coded absolute paths: `api.R` fixed** (`here::here()`, commit
  af62626; served model now at `models/model.rds`). The legacy
  notebooks that carried the other absolute paths were deleted in
  step 5 — resolved. `analysis/` scripts use `here::here()`.

## Refactor status

The repo is being modernised on the `refresh-2026` branch in May 2026.
See `git log refresh-2026` for the play-by-play. High-level arc:

1. ✅ Hygiene + live data refresh
2. ✅ Carve `Tennis_Data_Prep.Rmd` into focused pure functions in `R/`
   (full pipeline now: load_matches → parse_score → set_winners →
   match_stats → assign_player_slots → elo → rolling_averages →
   prune_columns → dummify → split_train_ids; two latent bugs fixed
   along the way — `gameswon_perc`, rolling-averages split)
3. ✅ Lean `renv` + portable paths (`api.R` via `here::here()`;
   `DESCRIPTION` dependency contract)
4. ✅ Retrain on fresh data, `tidymodels`/XGBoost, time-based holdout
   (2 target leaks found & fixed; honest baseline ≈0.856; tuning =
   no gain)
5. ✅ Legacy `.Rmd` notebooks retired; lean `analysis/eda.qmd`
   (sources `R/`, leak-free data) replaces their EDA
6. ✅ `README.md` rewritten (honest numbers) + `testthat` regression
   suite (`tests/testthat/`, 36 tests)
7. ✅ Production model trained on all data + promoted; API rewired to
   it (symmetrized, parity-checked); `surface`/`best_of` added; no
   Docker (solo/local). Interactive predictor shipped **experimental**
   — a train/serve task-mismatch (documented) makes it weakly
   discriminative; a real interactive model is future work.

**Refactor complete (7/7).** Net: a tested, leak-free, honestly-
evaluated pipeline that surfaced both the original leakage *and* the
interactive train/serve gap that was previously hidden.

## Next project: fix poor production (interactive) performance

The refactor is done; the **next major effort is a modelling project**
to make the deployed `/predict` endpoint actually useful. Problems
identified with the currently-deployed model (all documented in Known
issues; do not re-derive these the hard way):

1. **Train/serve task mismatch (the core problem).** The model is
   trained/validated on *historical match rows* (two players' form
   as-of one real match they played — real draws pair similar-tier
   opponents, features jointly consistent). Serving feeds an
   *arbitrary* A-vs-B pair built from each player's *solo latest
   snapshot* — a joint distribution never seen in training. Result:
   after correctly symmetrizing out XGBoost's slot bias, predictions
   are weakly discriminative on non-lopsided pairs (≈0.5; e.g. #1 vs
   #1921 ≈ 0.54). Honest holdout metrics (≈0.856 / 0.76 competitive)
   are real but for the *easier historical-row task*, not this one.
2. **It is model-agnostic.** Not an XGBoost bug, not a wiring bug
   (serving features verified in-distribution, parity-asserted).
   Swapping the learner will NOT fix it. Tree no-extrapolation is a
   minor (~2% OOD) secondary factor only.
3. **`bp_ratio`** degenerate feature (+Inf ~83% rows) still dropped;
   root-cause formula fix pending (deliberate feature change).

Suggested directions for the next project: a serving-consistent
training representation, or a purpose-built player-rating model
(calibrated Elo / Bradley–Terry) designed for the A-vs-B task, then
**re-evaluate as an interactive task** (not the historical-row task).
Keep the time-based-holdout / leak-audit discipline from step 4.
