# MLB Pitcher Deception Research

## Research question

Which MLB pitchers make a pitch's eventual strike-zone status hardest to anticipate at the batter's estimated swing-decision point, and is that unpredictability associated with pitching success?

The proposed **Decision-Point Deception Score (DPDS)** will distinguish: - **False strikes:** pitches predicted to finish in the strike zone but actually finishing outside. - **Hidden strikes:** pitches predicted to finish outside the strike zone but actually finishing inside.

**Important:** The eventual model measures unpredictability relative to a specified statistical model, **not direct batter perception**. A model's errors may reflect modeling limitations rather than a pitcher's deception.

## Technical workflow

- Language/environment: R in RStudio.
- Data: 2025 MLB regular-season pitch-level Statcast data using `baseballr`.
- Data manipulation and figures: `tidyverse` / `ggplot2`.
- Future prediction: interpretable logistic regression first; `tidymodels` for modeling and evaluation.
- Final report: Quarto.

Maintain separate R scripts and keep raw data unchanged. All new methods should be validated on the small sample before scaling to a full season.

## 1. Small-sample download and validation — completed

**Sample period:** April 1–3, 2025. Retrieved with `baseballr::statcast_search()`.

``` r
statcast_sample <- baseballr::statcast_search(
  start_date = "2025-04-01",
  end_date = "2025-04-03"
)

statcast_sample <- statcast_sample |>
  dplyr::filter(game_type == "R")
```

**Why:** A small sample lets us validate availability, units, missingness, and trajectory reconstruction without prematurely downloading a full season.

**Observed results:**

| Check                                            |         Value |
|--------------------------------------------------|--------------:|
| Pitches in initial sample                        |         9,450 |
| Distinct pitchers                                |           251 |
| Distinct games                                   |            33 |
| Mean release speed                               |      89.2 mph |
| Required trajectory/zone columns found           |           All |
| Pitches with at least one missing required field |            38 |
| Complete-case pitches retained                   | 9,412 (99.6%) |

The full set of required fields was:

``` r
required_vars <- c(
  "release_pos_x", "release_pos_y", "release_pos_z",
  "vx0", "vy0", "vz0",
  "ax", "ay", "az",
  "plate_x", "plate_z",
  "sz_top", "sz_bot"
)

trajectory_data <- statcast_sample |>
  dplyr::filter(dplyr::if_all(dplyr::all_of(required_vars), ~ !is.na(.x)))
```

**Why:** We need complete fitted trajectory parameters to reconstruct flight and observed plate location to evaluate reconstruction error. Retain the unfiltered data so exclusions can be audited for bias.

**Velocity check:** Observed `vy0` values were negative (approximately -150 to -99.4 feet/second), consistent with the coordinate convention in which pitches travel toward decreasing y.

**Limit:** Column presence and low missingness do not prove physical or perceptual validity. We have not yet evaluated reconstruction error over the sample.

## 2. Pitch-flight geometry — in progress

Statcast provides fitted initial velocity and acceleration components. In a constant-acceleration approximation, the coordinate trajectories are

$$x(t) = x_0 + v_{x0}t + \frac{1}{2} a_x t^2,$$

$$y(t) = y_0 + v_{y0}t + \frac{1}{2} a_y t^2,$$

$$z(t) = z_0 + v_{z0}t + \frac{1}{2} a_z t^2.$$

Here, **t** is seconds since the fitted trajectory's reference point; **positions** are feet; **velocities** are feet/second; and **accelerations** are feet/second squared.

### Why use these equations?

They give a transparent, testable reconstruction of the fitted Statcast trajectory. Starting with this simple kinematic form makes it possible to check that our coordinate convention, signs, units, and plate-crossing time are correct before adding a decision-point model.

### Reference coordinates and caution

The fitted velocity parameters are referenced near **y = 50 ft**, whereas `release_pos_y` refers to a physical release estimate and must **not** automatically be substituted for the fitted y-coordinate. We will independently validate the x- and z-coordinate origins against observed `plate_x` and `plate_z` before computing trajectory-wide errors.

For this initial exercise, take the front-of-plate plane as **y = 1.417 ft** in the Statcast coordinate system. This convention needs to remain explicit and be checked against Statcast documentation.

### Time to plate

Set the vertical-in-field coordinate to the plate plane:

$$y_{\mathrm{plate}} = y_0 + v_{y0}t_{\mathrm{plate}} + \frac12 a_y t_{\mathrm{plate}}^2.$$

Rearrangement yields

$$\frac12 a_y t_{\mathrm{plate}}^2 + v_{y0}t_{\mathrm{plate}} + (y_0-y_{\mathrm{plate}}) = 0.$$

For nonzero $a_y$, the physically relevant first positive crossing generally uses

$$t_{\mathrm{plate}} = \frac{-v_{y0}-\sqrt{v_{y0}^2 - 2a_y(y_0-y_{\mathrm{plate}})}}{a_y}.$$

We must check that the discriminant is nonnegative, time is positive, and the calculated y-position returns the specified plate plane. For $a_y$ close to zero, a linear approximation is preferable to an unstable division.

**Current validation state:** The user has selected the first complete-case sample pitch, but its calculated crossing-time output has not yet been reviewed. The equations above are a **planned reconstruction**, not a validated result.

## 3. Decision-point assumption — planned

Initial time remaining before plate crossing: **175 milliseconds** (= 0.175 s).

$$t_{\mathrm{decision}} = t_{\mathrm{plate}} - 0.175.$$

The reconstructed position is evaluated at $t_{\mathrm{decision}}$. The resulting point varies from pitch to pitch because travel times vary. We will test alternate decision windows; 175 ms is a working assumption, **not an observed universal human swing decision time**.

## 4. Essential methodological protections — planned

1.  Compare reconstructed plate x/z coordinates to observed `plate_x`/`plate_z` across many pitches, not just one.
2.  Avoid using trajectory information fitted from the full flight as if it were information directly available to the batter at the decision point. Such use can leak future information into the predictive model.
3.  Use chronological training/test splits and evaluate calibration, log loss, Brier score, and classification performance.
4.  Report pitcher uncertainty and minimum sample sizes; control for pitch type, velocity, movement, count, and handedness where appropriate.
5.  Treat associations with chase, whiff, and pitching effectiveness as correlational rather than causal without stronger identification.

## Research log

- **2026-10-14:** Download pipeline working after package updates. Verified 9,450 sampled pitches and 9,412 complete cases. Began deriving the time-to-plate equation. **Next:** check the first pitch's computed time, then validate x/z trajectories before calculating the decision point.
