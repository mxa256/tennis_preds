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
├── analysis/               # (future) Quarto orchestration docs
├── markdowns/              # Legacy Rmd notebooks (being decomposed into R/)
├── data/                   # Generated training/test CSVs (regenerable from pipeline)
├── models/                 # (future) Final saved .rds artifacts
├── mlruns/                 # MLflow experiment tracking (gitignored)
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

# Re-run the data prep pipeline (legacy monolith — being refactored)
rmarkdown::render("markdowns/Tennis_Data_Prep.Rmd")

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
- **The repo is mid-refactor.** When extracting code from the legacy
  monolith into `R/`, preserve behaviour exactly. Style improvements
  (collapsing the `data1 → data2 → ...` chain, replacing per-set unrolled
  blocks with `purrr::map`, etc.) go in separate follow-up commits.
  Genuine bugs found during a carve **do** get fixed — but as their own
  clearly-labelled `fix(...)` commit, separate from the faithful
  extraction (e.g. the SvGms, `gameswon_perc`, and rolling-averages
  split fixes).
- **Commit messages: no AI co-author trailer.** Do not append
  `Co-Authored-By: Claude` (or any AI/assistant co-author line) to
  commits in this repo. End the message at its last content line.

## Known issues

- **SvGms P2-slot bug — fixed in `R/predict.R`** (commit dc6616e). The
  identical bug still lurks at `markdowns/deployment_test.Rmd:57`; that file
  is a manual test harness slated for deletion and will be replaced by a
  testthat regression test in Phase 6.
- **Stale training data.** Current model was trained on 2018–2022. Refresh
  in progress to retrain on 2020–2026 YTD with a time-based test split.
- **`renv` lockfile is lean by design.** `renv.lock` locks only the
  ~10 runtime deps in `DESCRIPTION` (+ transitive = 76 pkgs), via
  explicit snapshot. The legacy `markdowns/` ML stack (keras,
  tidymodels, caret, …) is intentionally NOT locked — those notebooks
  are retired/migrated in step 5. Re-snapshot after the step-4 retrain
  adds modelling deps.
- **Hard-coded absolute paths: `api.R` fixed** (`here::here()`, commit
  af62626; served model now at `models/model.rds`). The legacy
  `Tennis_Data_Prep.Rmd` (superseded by `R/`), `Preprocessing.Rmd`,
  `MLF_HP_Tuning.Rmd`, `Tennis_Models.Rmd`, `Unseen_Test_Set.Rmd`,
  `deployment_test.Rmd` still have absolute paths — deferred to step 5
  (Quarto migration / deletion), not worth churning first.

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
   `DESCRIPTION` dependency contract; legacy `.Rmd` paths deferred to
   step 5)
4. 🟡 Retrain on fresh data via `tidymodels` (XGBoost engine) with a
   time-based holdout
5. Migrate `.Rmd` → Quarto, separate EDA from pipeline
6. Add `README.md` + minimal `testthat` coverage
7. Clean up Plumber API + Dockerize + deploy
