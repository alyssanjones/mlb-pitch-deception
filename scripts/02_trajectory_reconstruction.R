
library(tidyverse)

# ---------------------------------------------------
# 1. RECONSTRUCT PITCH TRAJECTORIES
# ---------------------------------------------------

trajectory_validation <- trajectory_data %>%
  mutate(
    y0 = 50,
    y_plate = 1.417,
    
    disc_plate = vy0^2 - 2 * ay * (y0 - y_plate),
    disc_release = vy0^2 - 2 * ay * (y0 - release_pos_y),
    
    valid_roots = is.finite(disc_plate) &
      is.finite(disc_release) &
      disc_plate >= 0 &
      disc_release >= 0 &
      abs(ay) > 0.000001,
    
    t_plate = if_else(
      valid_roots,
      (-vy0 - sqrt(pmax(disc_plate, 0))) / ay,
      NA_real_
    ),
    
    t_release = if_else(
      valid_roots,
      (-vy0 - sqrt(pmax(disc_release, 0))) / ay,
      NA_real_
    ),
    
    # Align release coordinates with the 50-foot reference
    x0 = release_pos_x -
      vx0 * t_release - 0.5 * ax * t_release^2,
    
    z0 = release_pos_z -
      vz0 * t_release - 0.5 * az * t_release^2,
    
    # Reconstructed plate-crossing coordinates
    x_pred = x0 + vx0 * t_plate +
      0.5 * ax * t_plate^2,
    
    z_pred = z0 + vz0 * t_plate +
      0.5 * az * t_plate^2,
    
    x_error = x_pred - plate_x,
    z_error = z_pred - plate_z
  ) %>%
  filter(
    valid_roots,
    is.finite(t_plate),
    is.finite(t_release),
    t_plate > 0,
    t_plate < 1,
    t_release < 0
  )


# ---------------------------------------------------
# 2. CALCULATE DECISION POINT
# ---------------------------------------------------

decision_data <- trajectory_validation %>%
  mutate(
    decision_window = 0.175,
    t_decision = t_plate - decision_window,
    
    x_decision = x0 + vx0 * t_decision +
      0.5 * ax * t_decision^2,
    
    y_decision = y0 + vy0 * t_decision +
      0.5 * ay * t_decision^2,
    
    z_decision = z0 + vz0 * t_decision +
      0.5 * az * t_decision^2,
    
    # Flag unusual reconstruction discrepancies
    reconstruction_error_max = pmax(
      abs(x_error), abs(z_error)
    ),
    
    reconstruction_flag_001 =
      reconstruction_error_max > 0.01,
    
    reconstruction_flag_002 =
      reconstruction_error_max > 0.02
  )


# ---------------------------------------------------
# 3. DECISION-TIME SENSITIVITY
# ---------------------------------------------------

decision_sensitivity <- trajectory_validation %>%
  mutate(pitch_id = row_number()) %>%
  tidyr::crossing(
    decision_window = c(0.150, 0.175, 0.200)
  ) %>%
  mutate(
    t_decision = t_plate - decision_window,
    
    x_decision = x0 + vx0 * t_decision +
      0.5 * ax * t_decision^2,
    
    y_decision = y0 + vy0 * t_decision +
      0.5 * ay * t_decision^2,
    
    z_decision = z0 + vz0 * t_decision +
      0.5 * az * t_decision^2
  )


# ---------------------------------------------------
# 4. VALIDATION
# ---------------------------------------------------

stopifnot(
  nrow(decision_data) == nrow(trajectory_validation),
  nrow(decision_sensitivity) == 3 * nrow(trajectory_validation),
  all(is.finite(decision_data$t_decision)),
  all(decision_data$t_decision >= 0),
  all(decision_data$t_decision < decision_data$t_plate)
)

trajectory_summary <- decision_data %>%
  summarise(
    input_pitches = nrow(trajectory_data),
    validated_pitches = n(),
    excluded_pitches = input_pitches - validated_pitches,
    x_mae = mean(abs(x_error)),
    z_mae = mean(abs(z_error)),
    flagged_pitches = sum(reconstruction_flag_001)
  )

print(trajectory_summary, width = Inf)
