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
│   └── impute_heights.R    #   impute_heights(matches) — fills winner_ht/loser_ht
├── analysis/               # (future) Quarto orchestration docs
├── markdowns/              # Legacy Rmd notebooks (being decomposed into R/)
├── data/                   # Generated training/test CSVs (regenerable from pipeline)
├── models/                 # (future) Final saved .rds artifacts
├── mlruns/                 # MLflow experiment tracking (gitignored)
├── api.R                   # Plumber API serving the XGBoost model
├── prepare_features.R      # Legacy — being merged into R/predict.R
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

## Known issues

- **`prepare_features.R:26` (duplicated at `markdowns/deployment_test.Rmd:57`):**
  `SvGms_av = ifelse(name_P_1 == player, SvGms_av_P_1, X2ndWon_av_P_2)` — when
  the player is in the P2 slot, the SvGms feature gets the 2nd-serve-won
  value instead. Will be fixed during the `R/predict.R` extraction.
- **Stale training data.** Current model was trained on 2018–2022. Refresh
  in progress to retrain on 2020–2026 YTD with a time-based test split.
- **No `renv` lockfile yet.** Packages must be installed manually. Lockfile
  will land later in the refactor.
- **Hard-coded absolute paths** still exist in `api.R`, `Tennis_Data_Prep.Rmd`,
  `Preprocessing.Rmd`, `MLF_HP_Tuning.Rmd`, `deployment_test.Rmd`. Will be
  replaced with `here::here()` once `renv` is in place.

## Refactor status

The repo is being modernised on the `refresh-2026` branch in May 2026.
See `git log refresh-2026` for the play-by-play. High-level arc:

1. ✅ Hygiene + live data refresh
2. 🟡 Carve `Tennis_Data_Prep.Rmd` into focused pure functions in `R/`
3. `renv::init()` + replace absolute paths with `here::here()`
4. Retrain on fresh data via `tidymodels` (XGBoost engine) with a
   time-based holdout
5. Migrate `.Rmd` → Quarto, separate EDA from pipeline
6. Add `README.md` + minimal `testthat` coverage
7. Clean up Plumber API + Dockerize + deploy
