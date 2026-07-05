# ATP Tennis Match-Outcome Predictor

Given two ATP men's singles players plus match context, predict the
probability that player 1 wins. Trained on Jeff Sackmann's
[`tennis_atp`](https://github.com/JeffSackmann/tennis_atp) match data,
served via a Plumber API behind a static HTML frontend.

> **Status:** the 2026 refactor is complete — the data pipeline was
> carved from a legacy notebook into a tested pure-function library
> with time-based evaluation. **Three** target leaks were found and
> fixed along the way; the third (`rank_diff`, July 2026) was only
> caught *after* the refactor shipped, so the previously reported
> "honest" 0.856 baseline was itself still inflated. The true
> leak-free numbers are far more modest — see
> [Model performance](#model-performance). `/predict` is now served
> by a purpose-built **calibrated Elo + rank predictor** (July 2026)
> that beats every leak-free baseline and is honestly calibrated; see
> [`CLAUDE.md`](CLAUDE.md) for the full state.

## Pipeline

The data prep is a chain of pure functions in `R/`, each taking a data
frame and returning it enriched:

```
load_atp_matches → clean_matches        # R/load_matches.R (+ impute_heights.R)
  → add_set_features                     # R/parse_score.R
  → add_set_winners                      # R/set_winners.R
  → add_match_stats                      # R/match_stats.R
  → assign_player_slots(seed)            # R/assign_player_slots.R  (neutral p1/p2 + label)
  → add_elo_features                     # R/elo.R   (as-of-match Elo)
  → add_rolling_averages                 # R/rolling_averages.R (30-match form, chronological)
  → prune_columns                        # R/prune_columns.R
  → dummify_clean                        # R/dummify.R
  → split_train_ids → {train, ids}       # R/split_train_ids.R
```

**Served model** (`R/predict_elo.R`): calibrated Elo + rank — a
logistic regression on overall/surface Elo differences and log rank
ratio, exactly antisymmetric by construction. The XGBoost stack on
~100 engineered features (serve/return %, point dominance, rolling
form) remains as the historical-row research pipeline.

## How to run

Dependencies are pinned with [`renv`](https://rstudio.github.io/renv/)
(`renv::restore()` to install). From the project root:

```r
source("R/refresh_data.R")                 # sync upstream ATP data
Rscript analysis/build_training_data.R     # pipeline -> data/*.csv + serving snapshot
Rscript analysis/train_model.R             # time-split baseline + honest holdout metrics
Rscript analysis/tune_model.R              # (optional) time-aware hyperparameter search
Rscript analysis/train_production_model.R  # final model on ALL data -> models/model.rds
Rscript analysis/train_elo_predictor.R     # SERVED predictor -> models/elo_predictor.rds
Rscript tests/testthat.R                   # regression suite
plumber::pr_run(plumber::pr("api.R"))      # serve predictions on :8000
```

Model `.rds` artifacts are gitignored (regenerable from the committed
data + seeded scripts); on a fresh clone run
`analysis/train_production_model.R` once before serving. No Docker —
solo/local use; `plumber::pr_run` above is the deploy path.

The `/predict` endpoint takes `player1`, `player2`, `surface`
(Hard/Clay/Grass), `best_of` (3/5) and returns `p1_win_probability`.

## Model performance

Evaluated on a **time-based holdout** (train ≤2024, test 2025–2026
YTD) — *not* a random split, which would leak future form into the
past via the rolling-average features.

| | Accuracy | AUC | Brier |
|---|---|---|---|
| **Calibrated Elo + rank (SERVED)** | **0.642** | **0.701** | **0.219** |
| "Better ATP rank wins" | 0.640 | | |
| Pure as-of Elo (rating diff → odds) | 0.630 | 0.689 | 0.241 |
| Baseline XGBoost (leak-free) | 0.617 | 0.669 | 0.235 |

The sobering, honest picture: the ~100 rolling-form features currently
add **nothing** over a single Elo rating or the ATP ranking itself.
That is consistent with the literature — published tennis models and
even bookmakers top out around ~0.70 accuracy, so ~0.64–0.70 is the
realistic target range, and any past number far above it should have
been (and eventually was) diagnosed as leakage.

> ⚠️ **All earlier reported numbers were inflated by target leaks —
> including the 0.856/0.940 previously documented here as honest.**
> Three leaks total: end-of-history Elo and shuffle-order rolling
> averages (fixed during the refactor, `R/elo.R` /
> `R/rolling_averages.R`), and winner-oriented `rank_diff` (found
> July 2026, fixed in `R/assign_player_slots.R`, commit `9dd74ad`) —
> the training feature encoded winner-minus-loser rank, from which the
> label was 100% recoverable. All three are guarded by regression
> tests. Do not cite any pre-fix figure (0.83, 0.91, 0.856, 0.94).

Hyperparameter tuning over time-aware folds produced no improvement on
the leak-era data; it has not been re-run on leak-free data (feature
work, not knobs, is the bottleneck).

## Known limitations

- **Tennis is genuinely hard to predict.** The served model's 0.642
  accuracy / 0.701 AUC is real, calibrated skill — but bookmakers only
  reach ~0.70, so single-match probabilities are informed estimates,
  not certainties. Not a betting tool.
- **Ratings and ranks are as of the last data refresh** (each player's
  most recent match in the local `tennis_atp` clone). Re-run the
  pipeline + `train_elo_predictor.R` after refreshing data.
- **`bp_ratio`** is `+Inf` in ~83% of rows (divide-by-zero in
  `match_stats.R`); the degenerate `bp_ratio_av_*` columns are dropped
  before modelling in the research pipeline. Root-cause fix pending.

### Historical note (July 2026)

The previous XGBoost serving path was retired after the third leak was
found: its training `rank_diff` encoded winner-minus-loser rank (the
label was 100% recoverable), while serving computed p1 − p2, so its
apparent 0.856 skill vanished at serve time — the earlier "train/serve
task mismatch" theory is superseded. `R/predict.R` + `models/model.rds`
remain as a research path; possible future gains for the served model:
warm-starting Elo before 2020, K-factor tuning, margin-of-victory Elo.

## Data

Sackmann's match-level ATP data, currently 2020–2026 YTD (~13k
modelling rows after cleaning). Upstream lives **outside** the repo at
`../tennis_atp-master/` and is fetched, not vendored.

EDA domain notes (still valid): match outcomes vary by surface;
taller players tend to serve bigger; the field is dominated by a
small set of elite players, which is why pooled accuracy is high while
*competitive*-match accuracy is the honest difficulty signal.

## Layout

- `R/` — pure-function pipeline + inference (sourced; not a package)
- `analysis/` — orchestration scripts (side effects live here)
- `tests/testthat/` — regression suite (run `tests/testthat.R`)
- `api.R` / `index.html` — Plumber API + static frontend
- `CLAUDE.md` — detailed context, conventions, refactor status

## Author

Mona Ascha
