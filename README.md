# ATP Tennis Match-Outcome Predictor

Given two ATP men's singles players plus match context, predict the
probability that player 1 wins. Trained on Jeff Sackmann's
[`tennis_atp`](https://github.com/JeffSackmann/tennis_atp) match data,
served via a Plumber API behind a static HTML frontend.

> **Status:** mid-modernisation on the `refresh-2026` branch. The data
> pipeline has been carved from a legacy notebook into a tested
> pure-function library, two serious data leaks were found and fixed,
> and the model has an honest, leak-free baseline. See
> [Model performance](#model-performance) and
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

Champion engine: XGBoost on ~100 engineered features (serve/return %,
point dominance, break-point ratios, 30-match rolling form, as-of Elo
and Elo-derived odds).

## How to run

Dependencies are pinned with [`renv`](https://rstudio.github.io/renv/)
(`renv::restore()` to install). From the project root:

```r
source("R/refresh_data.R")                 # sync upstream ATP data
Rscript analysis/build_training_data.R     # pipeline -> data/*.csv + serving snapshot
Rscript analysis/train_model.R             # time-split baseline + honest holdout metrics
Rscript analysis/tune_model.R              # (optional) time-aware hyperparameter search
Rscript analysis/train_production_model.R  # final model on ALL data -> models/model.rds
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
| Baseline XGBoost (honest) | **0.856** | 0.940 | 0.100 |
| — on lopsided matches | 0.954 | | |
| — on competitive matches | 0.758 | | |
| Trivial "higher Elo wins" | 0.635 | | |

Hyperparameter tuning over time-aware folds produced **no meaningful
improvement** — the ceiling is set by features/data, not the knobs.

> ⚠️ **Earlier reported numbers (e.g. AUC ≈ 0.91, accuracy ≈ 0.83)
> were inflated by two target leaks** — end-of-history Elo and
> shuffle-order rolling averages — now fixed (`R/elo.R`,
> `R/rolling_averages.R`) and guarded by regression tests. Do not cite
> the pre-fix figures.

## Known limitations

- **The interactive API is experimental.** Those metrics are for the
  *historical-match-row* task (predict a real match given both
  players' as-of form). The `/predict` endpoint solves a *different,
  harder* task — arbitrary player A vs B from each one's latest solo
  snapshot — a joint distribution the model never trained on. After
  correctly symmetrizing out XGBoost's slot bias, predictions are only
  weakly discriminative on non-lopsided matchups. It is **not** a
  calibrated betting tool. This is model-agnostic (a problem-framing
  gap, not an algorithm or wiring bug).
- **`bp_ratio`** is `+Inf` in ~83% of rows (divide-by-zero in
  `match_stats.R`); the degenerate `bp_ratio_av_*` columns are dropped
  before modelling. A principled root-cause fix is pending.

### Future work (separate modelling project)

A usable interactive predictor needs a serving-consistent
representation or a purpose-built player-rating model (calibrated Elo
/ Bradley–Terry), then re-evaluation *as an A-vs-B task*. Out of scope
for this refactor, whose deliverable was a correct, tested,
honestly-evaluated pipeline.

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
- `markdowns/` — legacy notebooks (being retired/migrated)
- `CLAUDE.md` — detailed context, conventions, refactor status

## Author

Mona Ascha
