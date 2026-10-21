# Running the analysis in RStudio

Use the **repository root** as the working directory. These scripts currently pass named objects between source calls and are not yet a standalone package. The supplied ZIP did not include the Statcast data or model objects.

## 1. If the data are not already downloaded

- Run `scripts/05_expand_statcast.R` to assemble April data (review existing files before downloading).
- Run `scripts/07_verify_may_download.R` to assemble May 1–7 (downloads daily files).
- Run `scripts/10_expand_may.R` for May 8–14 (downloads daily files).

`06_may_validation.R` is a diagnostic and should not be treated as a required model-training step.

## 2. Train and validate models

``` r
source("scripts/01_data_collection.R")
source("scripts/02_trajectory_reconstruction.R")
source("scripts/03_strike_zone.R")
source("scripts/04_deception_model.R")
source("scripts/08_may_evaluation.R")
source("scripts/09_pitch_mix_adjustment.R")
source("scripts/11_handedness_models.R")
source("scripts/12_handedness_validation.R")
```

## 3. Plot from validated results

``` r
source("scripts/13_generate_figures.R")
```

The figure script expects in-memory objects or `data/processed/*.rds` snapshots. `12` saves the May 8–14 snapshot. For a fresh session, rerun the earlier scripts or save `may_evaluation` and `adjusted_pitcher_scores` in `data/processed/`.

## Dependencies

R packages: `tidyverse`, `mgcv`, `baseballr`, `scales`. Several graphics exports use Cairo PDF; your R installation must support Cairo or the PDF export line should be switched to `device = "pdf"`.

## Important methodological caveat

The reconstructed decision-point coordinates rely on full-flight-fitted Statcast parameters. They are a **retrospective modeling benchmark** and must not be described as independent tracking observations available to a batter. Pitcher rankings from File 09 remain preliminary and are based on the original combined GAM, not the subsequent handedness models.
