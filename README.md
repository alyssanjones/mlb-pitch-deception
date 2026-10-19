# MLB Pitcher Deception

**Can I identify MLB pitchers whose pitches are especially difficult to predict at the batter's swing-decision point?**

This ongoing R research project investigates whether a pitch's eventual location inside or outside the strike zone is predictable before it reaches home plate, and whether some pitchers produce more unexpected outcomes than others. The longer-term goal is to develop and validate a **Decision-Point Deception Score (DPDS)** and test its relationship with chase rate, whiff rate, and pitching performance.

> **Research status:** Prototype and exploratory analysis. The current trajectory model is **retrospective**: Statcast's fitted trajectory parameters use information from the full pitch flight. Its prediction errors are **not** direct observations of batter perception or validated measurements of deception. A model using genuine time-stamped, pre-decision tracking observations is the next methodological priority.

## Current results

I analyzed 2025 regular-season Statcast data obtained through [`baseballr`](https://billpetti.github.io/baseballr/). April was used for model development; May 1–7 was evaluated using the April-trained models.

| Dataset | Raw pitches | Complete trajectory records |
|---|---:|---:|
| April 1–30, 2025 | 108,708 | 108,400 |
| May 1–7, 2025 | 27,706 | 27,640 |

The initial seven-day May request returned exactly 25,000 pitches; downloading individual days recovered another 2,706. The May analysis uses the combined daily downloads, with records deduplicated by game, at-bat, and pitch number. Daily coverage was checked, but completeness was not independently audited against every official game record.

### Out-of-period strike-zone prediction (May 1–7)

| Model | Accuracy ↑ | Brier ↓ | Log loss ↓ | ECE ↓ |
|---|---:|---:|---:|---:|
| Constant training strike rate | 50.8% | 0.250 | 0.693 | 0.00799 |
| Pre-pitch context logistic regression | 56.4% | 0.245 | 0.682 | 0.0168 |
| Retrospective trajectory GAM | **74.3%** | **0.174** | **0.522** | 0.0186 |

All three models were fitted using April data and evaluated on the same **27,640 May pitches**. The GAM's performance on April 26–30 was similar (74.4% accuracy; Brier 0.173; log loss 0.518). The low ECE of the constant model does not imply good pitch-by-pitch discrimination. These results establish performance of a **retrospective forecasting benchmark**, not what a hitter could actually see or predict.

## Methodology

### 1. Reconstruct the flight

The initial pitch-flight approximation uses the fitted Statcast velocity and acceleration components:

\[
\begin{aligned}
x(t) &= x_0 + v_{x0}t + \tfrac12 a_x t^2,\\
y(t) &= 50 + v_{y0}t + \tfrac12 a_y t^2,\\
z(t) &= z_0 + v_{z0}t + \tfrac12 a_z t^2.
\end{aligned}
\]

Coordinates are in feet and time is in seconds. Statcast's fitted velocity parameters refer to the approximately 50-foot reference plane; release-position coordinates are aligned to that reference before extrapolation. Plate crossing is evaluated at `y = 1.417` feet under the project's geometric convention.

The baseline **decision time** is 175 milliseconds before plate crossing:

\[
t_{\mathrm{decision}} = t_{\mathrm{plate}} - 0.175.
\]

Alternative windows of 150 and 200 ms were explored. For the complete April sample, mean absolute error between reconstructed and recorded plate location was about **0.0025 ft** on each axis. This validates numerical consistency with the fitted Statcast trajectory, **not** pre-decision predictive independence. Unusually large reconstruction discrepancies are flagged rather than automatically removed.

### 2. Define the strike-zone outcome

The primary binary target, `strike_overlap`, is a geometric approximation: a baseball modeled as a circle of radius **1.45 inches** overlaps the rectangular zone defined by plate half-width **8.5 inches** and the pitch-specific `sz_bot` / `sz_top`. A stricter ball-center-inside-zone label (`strike_center`) is retained as a sensitivity check.

In May, **14,047 / 27,640 (50.8%)** pitches were classified as overlap strikes. The two labeling conventions disagreed on **2,478 (9.0%)** pitches. This is a geometric outcome definition, not a model of umpire calls.

### 3. Predict strike-zone status

I compared a constant-probability baseline, pre-pitch logistic regression using count and handedness, and a generalized additive model (GAM) using the same context plus reconstructed decision-point `x`, `y`, and `z` coordinates.

The GAM was fitted with `mgcv::gam(..., family = binomial(), method = "REML")`. Smooth-basis dimension `k = 10` was selected using April 21–25 after comparing against `k = 5`; model fitting used April 1–20, and development evaluation used April 26–30. The selected model was then tested on May 1–7 without refitting. Accuracy, Brier score, log loss, and 10-bin expected calibration error (ECE) were reported.

**Critical limitation:** Reconstructed decision-point coordinates use parameters estimated from observations throughout the pitch. Simply truncating points simulated from those parameters would **not** remove future-information leakage.

### 4. Explore directional prediction errors

A model-predicted strike that finishes outside the zone is labeled a **false strike**; a model-predicted ball that finishes inside is a **hidden strike**. Using a 0.50 probability cutoff, the May GAM made:

| Outcome | Pitches | Share |
|---|---:|---:|
| Correct classification | 20,530 | 74.3% |
| False strike | 4,456 | 16.1% |
| Hidden strike | 2,654 | 9.6% |

An exploratory *confident error* uses `P(strike) >= 0.70` for an actual ball or `P(strike) <= 0.30` for an actual strike. May contained **2,682** such errors. These thresholds are descriptive, not a final deception definition.

### 5. Adjust for pitch characteristics

Some pitch types produce higher GAM error rates than others. To avoid treating pitch mix alone as pitcher skill, I explored observed-minus-expected confident-error rates:

\[
\mathrm{ExcessErrorPP}_{p}=100\times\frac{\sum_{i\in p}(e_i-\hat q_i)}{N_p},
\]

where `e_i` indicates a confident model error and `q̂_i` is an expected error probability. An initial leave-one-pitcher-out comparison conditions on pitch type and final zone status. A later exploratory logistic adjustment was trained on April 26–30 and included grouped pitch type, velocity, measured movement, count, handedness, and actual zone status. On May data, this expected-error model improved Brier score **0.0876 → 0.0856** and log loss **0.319 → 0.309** against a constant error-rate baseline.

These are **exploratory retrospective error-adjustment scores**, not a validated DPDS or final pitcher rankings. They use outcome-conditioned and full-flight inputs, and the short May window provides too few appearances for trustworthy ranking uncertainty or repeatability claims. Some later adjustment and game-level diagnostics were performed interactively and may not yet be incorporated in the checked-in scripts.

## Repository workflow

This project uses **R and RStudio**. Core packages include `baseballr`, `tidyverse`, and `mgcv`.

```r
install.packages(c("baseballr", "tidyverse", "mgcv"))
```

Run the scripts from the repository's root working directory. Cached `.rds` Statcast data and trained-model files are required for the analysis scripts; downloaded datasets are **not necessarily included in the repository**.

| Script | Role |
|---|---|
| `05_expand_statcast.R` | Download and cache April regular-season Statcast data |
| `01_data_collection.R` | Load April data; check required variables and complete cases |
| `02_trajectory_reconstruction.R` | Reconstruct April trajectories and decision points |
| `03_strike_zone.R` | Create geometric strike-zone outcomes |
| `04_deception_model.R` | Fit/save the April GAM and evaluate development periods |
| `07_verify_may_download.R` | Download May 1–7 by day and save the combined verified file |
| `06_may_validation.R` | Load and check the saved May data |
| `08_may_evaluation.R` | Apply frozen April models to May and score predictions |
| `09_pitch_mix_adjustment.R` | Exploratory pitch-type adjustment; later covariate-adjustment work is in progress |

**Typical execution order after downloading/caching data:**

```r
source("01_data_collection.R")
source("02_trajectory_reconstruction.R")
source("03_strike_zone.R")
source("04_deception_model.R")
source("08_may_evaluation.R")
```

Before running May evaluation, confirm the following artifacts exist (the baselines were also saved separately during development):

```text
data/statcast_april_2025.rds
data/statcast_may_verified_2025.rds
models/gam_model_k10.rds
models/baseline_model.rds
models/constant_strike_rate.rds
```

If these files are absent, run the acquisition scripts, then regenerate the April model artifacts before May evaluation. The modeling workflow should never train on the May evaluation set. Note that the scripts have been developed incrementally and are **not yet packaged as a one-command, clean-environment reproducibility release**. Paths and file names assume the project root is the working directory.

## Limitations and next steps

The principal unresolved issue is **information availability at the decision point**. Ordinary pitch-level Statcast exports provide fitted flight parameters rather than a time-stamped series of directly observed 3D ball positions. A stronger study needs genuine observations acquired **at or before** the modeled decision point, with defensible timestamps and coordinate calibration.

Priorities:

1. Investigate availability of frame-level tracking measurements and their measurement uncertainty; do not represent synthetic points from full-flight fits as leak-free observations.
2. Fit early-flight-only constant-velocity and constant-acceleration forecasts, then evaluate strike probabilities on later games.
3. Test decision windows (150, 175, 200 ms), and quantify sensitivity to strike-zone geometry and tracking uncertainty.
4. Develop separate continuous-probability false-strike and hidden-strike components, controlling for pitch mix and other covariates without erasing the phenomenon of interest.
5. Collect more appearances; evaluate game-level uncertainty, shrinkage, and season-to-season repeatability before ranking pitchers.
6. Test incremental associations with chase rate, whiff rate, and established pitching metrics. Avoid causal claims from observational correlations.

## Interpretation

**What the current project demonstrates:** a nonlinear model built from retrospectively reconstructed 175-ms pitch coordinates predicts eventual geometric strike-zone status substantially better than pre-pitch context alone on May 2025 data.

**What it does not demonstrate:** that a batter could make the same predictions, that model errors directly measure deception, or that any pitcher has a statistically established deception skill. The DPDS remains a research goal rather than a finalized metric.
