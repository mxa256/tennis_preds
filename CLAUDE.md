# CLAUDE.md

Context for AI assistants (Claude Code etc.) working in this repo.

## What this is

An ATP men's tennis match-outcome predictor. Given two ATP players plus
match context, it returns the probability that player 1 wins. Trained on
Jeff Sackmann's `tennis_atp` match-level data, served via a Plumber R API
plus a static HTML frontend.

Served model (since 2026-07): **calibrated Elo + rank predictor**
(`R/predict_elo.R`) — logistic regression on overall/surface Elo
deltas + log rank ratio, exactly antisymmetric by construction.
Honest 2025–26 holdout: acc 0.642 / AUC 0.701 / Brier 0.219,
calibrated by decile (bars: better-rank 0.640, leak-free XGBoost
0.617; ~0.70 is the literature ceiling). The XGBoost pipeline
(~100 rolling-form features) remains as the historical-row research
stack; leak-free it is WEAK (acc 0.617) — see Known issues (third
leak).

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
│   ├── predict.R           #   Legacy XGBoost inference (research path; API no longer uses it)
│   └── predict_elo.R       #   SERVED inference: calibrated Elo+rank predictor (fit/ratings/predict_winner_elo)
├── analysis/               # Orchestration + EDA (side effects live here)
│   ├── build_training_data.R #  compose R/ pipeline → data/*.csv
│   ├── train_model.R       #   time-split baseline XGBoost + holdout
│   ├── train_elo_predictor.R # train/evaluate/save the SERVED Elo predictor
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

# Train + save the SERVED interactive predictor (models/elo_predictor.rds)
Rscript analysis/train_elo_predictor.R

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
- **THREE target leaks found & fixed** (the original project's headline
  accuracy was inflated and never caught): end-of-history Elo (commit
  ea6acde), shuffle-order rolling averages (commit 90b6289), and —
  found only 2026-07-04, AFTER the refactor shipped — winner-oriented
  `rank_diff` (commit 9dd74ad): computed pre-slot as winner_rank −
  loser_rank and untouched by the slot rename, so the label was 100%
  recoverable from it (25% of xgb gain). It evaded the step-4
  univariate-AUC audit because it decodes only via interactions with
  slot-strength features. True leak-free baseline on the 2025–26
  time-based holdout: XGBoost acc 0.617 / AUC 0.669 / Brier 0.235;
  pure as-of Elo 0.630 / 0.689; "better ATP rank wins" 0.640. The
  rolling-form features add nothing over Elo/rank alone (consistent
  with the ~0.70 bookmaker ceiling in the literature). **Never quote
  the ~0.92 OR the ~0.856 numbers — both were leakage.** Any
  improvement claim must beat 0.640 on the time-based holdout.
- **`bp_ratio` is +Inf in ~83% of rows** (divide-by-zero in
  `match_stats.R`). `analysis/train_model.R` drops the degenerate
  `bp_ratio_av_*` columns; a root-cause formula fix is a pending
  deliberate feature change (changes model inputs).
- **The XGBoost serving path was retired (2026-07).** History: the
  interactive collapse (≈0.5 on most pairs) blamed on a "train/serve
  task mismatch" in step 7 was actually the third leak — training
  rank_diff encoded winner−loser while inference computed p1−p2, so
  the channel carrying the model's discriminative power was empty at
  serve time. The model was never good; it had the answer key during
  evaluation. `/predict` now serves the calibrated Elo predictor
  (`R/predict_elo.R`, commits 604a893/e2d3254). `R/predict.R` +
  `models/model.rds` remain as the historical-row research path only;
  old leaky model kept as `models/model_legacy.rds`.
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
   (2 target leaks found & fixed; baseline ≈0.856 believed honest at
   the time — later found still inflated by a 3rd leak, see Known
   issues; tuning = no gain, also a leak-era result)
5. ✅ Legacy `.Rmd` notebooks retired; lean `analysis/eda.qmd`
   (sources `R/`, leak-free data) replaces their EDA
6. ✅ `README.md` rewritten (honest numbers) + `testthat` regression
   suite (`tests/testthat/`, 36 tests)
7. ✅ Production model trained on all data + promoted; API rewired to
   it (symmetrized, parity-checked); `surface`/`best_of` added; no
   Docker (solo/local). Interactive predictor shipped **experimental**
   — attributed at the time to a train/serve task-mismatch; that
   explanation was superseded 2026-07 by the 3rd-leak finding (see
   Known issues).

**Refactor complete (7/7).** Net: a tested, honestly-evaluated
pipeline. Its evaluation discipline ultimately surfaced all three
leaks — the third only after the refactor itself had shipped.

## Elo predictor: SHIPPED (2026-07-04)

The calibrated Elo predictor is built, tested, and serving `/predict`
(commits 604a893 + e2d3254). Summary (do not re-derive the hard way):

- **Model:** glm on antisymmetric features only — overall Elo delta,
  surface Elo delta (learned blend ≈ 1/3 surface), log rank ratio,
  delta:bo5 interactions; NO intercept / NO bo5 main effect (slot-bias
  artifacts), so P(A,B)+P(B,A)==1 exactly. Fit on all 13,132 labelled
  rows; artifact `models/elo_predictor.rds` = glm + per-player current
  ratings (overall + per-surface, via `compute_player_elos`'
  `final_elos` attribute) + latest rank.
- **Honest holdout (2025–26, n=2913): acc 0.642 / AUC 0.701 / Brier
  0.219, calibrated by decile.** Experiment ladder: raw Elo 0.630 →
  +surface 0.635 → +recalibration (Brier 0.241→0.221) → +learned
  blend 0.641 → +rank 0.644 eval-form / 0.642 symmetric-form. The
  accuracy edge over the 0.640 rank bar is within noise; the real
  wins are AUC, calibration, and no-leak-by-construction.
- **Possible future improvements** (none started): warm-start the Elo
  walk pre-2020 (upstream data goes back decades; 2020 cold start
  wastes early seasons), K-factor tuning, margin-of-victory Elo.
- **`bp_ratio`** degenerate feature (+Inf ~83% rows) still dropped in
  the research pipeline; root-cause formula fix pending.

Keep the time-based-holdout / leak-audit discipline; every claimed
improvement must beat the shipped 0.642/0.701/0.219 on the holdout,
evaluated leak-free.
