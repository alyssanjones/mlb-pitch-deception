# 08_may_evaluation.R
# May 1-7, 2025: independent retrospective prediction evaluation.
# Requires saved May data and April-trained models. Never trains on May.
library(tidyverse)

may_path <- "data/statcast_may_verified_2025.rds"
gam_path <- "models/gam_model_k10.rds"
baseline_path <- "models/baseline_model.rds"
constant_path <- "models/constant_strike_rate.rds"

for (path in c(may_path, gam_path, baseline_path, constant_path)) {
  if (!file.exists(path)) stop("Missing required file: ", path)
}

statcast_may <- readRDS(may_path)
gam_model_k10 <- readRDS(gam_path)
baseline_model <- readRDS(baseline_path)
train_strike_rate <- readRDS(constant_path)

required_vars <- c(
  "game_date", "game_type", "game_pk", "at_bat_number", "pitch_number",
  "pitcher", "batter", "pitch_type", "release_speed", "pfx_x", "pfx_z",
  "release_pos_x", "release_pos_y", "release_pos_z",
  "vx0", "vy0", "vz0", "ax", "ay", "az",
  "plate_x", "plate_z", "sz_top", "sz_bot",
  "balls", "strikes", "stand", "p_throws"
)
missing_vars <- setdiff(required_vars, names(statcast_may))
if (length(missing_vars)) stop("Missing May columns: ", paste(missing_vars, collapse = ", "))
statcast_may <- statcast_may %>% mutate(game_date = as.Date(game_date))
stopifnot(
  nrow(statcast_may) > 0,
  !anyNA(statcast_may$game_date),
  all(statcast_may$game_type == "R"),
  all(statcast_may$game_date >= as.Date("2025-05-01")),
  all(statcast_may$game_date <= as.Date("2025-05-07")),
  !anyDuplicated(statcast_may[c("game_pk", "at_bat_number", "pitch_number")]),
  is.numeric(train_strike_rate), length(train_strike_rate) == 1,
  is.finite(train_strike_rate), train_strike_rate > 0, train_strike_rate < 1
)

# Complete-case reconstruction: same required April fields; movement retained.
may_trajectory_data <- statcast_may %>%
  filter(if_all(all_of(required_vars), ~ !is.na(.x)))

may_trajectory_validation <- may_trajectory_data %>%
  mutate(
    y0 = 50, y_plate = 1.417,
    disc_plate = vy0^2 - 2 * ay * (y0 - y_plate),
    disc_release = vy0^2 - 2 * ay * (y0 - release_pos_y),
    valid_roots = is.finite(disc_plate) & is.finite(disc_release) &
      disc_plate >= 0 & disc_release >= 0 & abs(ay) > 1e-6,
    t_plate = if_else(valid_roots,
      (-vy0 - sqrt(pmax(disc_plate, 0))) / ay, NA_real_),
    t_release = if_else(valid_roots,
      (-vy0 - sqrt(pmax(disc_release, 0))) / ay, NA_real_),
    x0 = release_pos_x - vx0 * t_release - 0.5 * ax * t_release^2,
    z0 = release_pos_z - vz0 * t_release - 0.5 * az * t_release^2,
    x_pred = x0 + vx0 * t_plate + 0.5 * ax * t_plate^2,
    z_pred = z0 + vz0 * t_plate + 0.5 * az * t_plate^2,
    x_error = x_pred - plate_x,
    z_error = z_pred - plate_z
  ) %>%
  filter(valid_roots, is.finite(t_plate), is.finite(t_release),
    t_plate > 0, t_plate < 1, t_release < 0)

may_decision_data <- may_trajectory_validation %>%
  mutate(
    decision_window = 0.175,
    t_decision = t_plate - decision_window,
    x_decision = x0 + vx0 * t_decision + 0.5 * ax * t_decision^2,
    y_decision = y0 + vy0 * t_decision + 0.5 * ay * t_decision^2,
    z_decision = z0 + vz0 * t_decision + 0.5 * az * t_decision^2,
    reconstruction_error_max = pmax(abs(x_error), abs(z_error)),
    reconstruction_flag_001 = reconstruction_error_max > 0.01,
    reconstruction_flag_002 = reconstruction_error_max > 0.02
  )
stopifnot(nrow(may_decision_data) > 0,
  all(is.finite(may_decision_data$t_decision)),
  all(may_decision_data$t_decision >= 0 &
      may_decision_data$t_decision < may_decision_data$t_plate))

# Geometric strike-zone labels: unchanged April conventions.
plate_half_width <- 8.5 / 12
ball_radius <- 1.45 / 12
may_strike_zone_data <- may_decision_data %>%
  mutate(
    strike_center = as.integer(abs(plate_x) <= plate_half_width &
      plate_z >= sz_bot & plate_z <= sz_top),
    dx = pmax(abs(plate_x) - plate_half_width, 0),
    dz = pmax(sz_bot - plate_z, plate_z - sz_top, 0),
    distance_to_zone = sqrt(dx^2 + dz^2),
    strike_overlap = as.integer(distance_to_zone <= ball_radius),
    overlap_margin = distance_to_zone - ball_radius
  ) %>%
  select(-dx, -dz)
stopifnot(!anyNA(may_strike_zone_data$strike_overlap))

may_data_summary <- may_strike_zone_data %>%
  summarise(
    raw_pitches = nrow(statcast_may),
    usable_pitches = nrow(may_trajectory_data),
    reconstructed_pitches = n(),
    x_mae = mean(abs(x_error)), z_mae = mean(abs(z_error)),
    flagged_pitches = sum(reconstruction_flag_001),
    strike_rate = mean(strike_overlap)
  )
print(may_data_summary, width = Inf)

# Frozen April-trained predictions on May pitches.
may_evaluation <- may_strike_zone_data %>%
  mutate(
    gam_prob = as.numeric(predict(gam_model_k10, newdata = may_strike_zone_data,
                                  type = "response")),
    baseline_prob = as.numeric(predict(baseline_model,
                                     newdata = may_strike_zone_data,
                                     type = "response")),
    constant_prob = train_strike_rate
  )
prob_cols <- c("gam_prob", "baseline_prob", "constant_prob")
for (col in prob_cols) {
  p <- may_evaluation[[col]]
  stopifnot(length(p) == nrow(may_evaluation), all(is.finite(p)),
            all(p >= 0 & p <= 1))
}

# Evaluation functions: lower Brier, log loss and ECE are better.
calculate_ece <- function(actual, predicted, bins = 10) {
  tibble(actual = actual, predicted = predicted,
         bin = cut(predicted, breaks = seq(0, 1, length.out = bins + 1),
                   include.lowest = TRUE)) %>%
    group_by(bin) %>%
    summarise(n = n(), observed = mean(actual), estimated = mean(predicted),
              .groups = "drop") %>%
    summarise(ece = weighted.mean(abs(observed - estimated), n)) %>%
    pull(ece)
}

score_predictions <- function(actual, predicted, model_name) {
  safe_p <- pmin(pmax(predicted, 1e-15), 1 - 1e-15)
  tibble(
    model = model_name,
    accuracy = mean((predicted >= 0.5) == actual),
    brier_score = mean((predicted - actual)^2),
    log_loss = -mean(actual * log(safe_p) + (1 - actual) * log1p(-safe_p)),
    ece = calculate_ece(actual, predicted)
  )
}

may_model_comparison <- bind_rows(
  score_predictions(may_evaluation$strike_overlap,
                    may_evaluation$constant_prob, "Constant"),
  score_predictions(may_evaluation$strike_overlap,
                    may_evaluation$baseline_prob, "Context"),
  score_predictions(may_evaluation$strike_overlap,
                    may_evaluation$gam_prob, "Trajectory GAM")
)
print(may_model_comparison, width = Inf)

may_results <- may_model_comparison %>%
  filter(model == "Trajectory GAM") %>%
  mutate(pitches = nrow(may_evaluation), .before = 1) %>%
  select(-model)

# Descriptive retrospective-error categories (NOT directly observed deception).
may_evaluation <- may_evaluation %>%
  mutate(
    predicted_strike = as.integer(gam_prob >= 0.5),
    deception_type = case_when(
      predicted_strike == 1 & strike_overlap == 0 ~ "False strike",
      predicted_strike == 0 & strike_overlap == 1 ~ "Hidden strike",
      TRUE ~ "Correct prediction"
    ),
    confident_error = as.integer(
      (strike_overlap == 0 & gam_prob >= 0.70) |
      (strike_overlap == 1 & gam_prob <= 0.30)
    )
  )
deception_summary <- may_evaluation %>%
  count(deception_type) %>%
  mutate(percentage = round(100 * n / sum(n), 2))
print(deception_summary, n = Inf)

# File 09 handles expected-error adjustment and pitcher rankings.
# Decision coordinates are derived from full-flight fits: retrospective only.
