
library(baseballr)
library(tidyverse)

# Required variables for trajectory reconstruction and modeling
required_vars <- c(
  "release_pos_x", "release_pos_y", "release_pos_z",
  "vx0", "vy0", "vz0",
  "ax", "ay", "az",
  "plate_x", "plate_z",
  "sz_top", "sz_bot",
  "game_date", "game_pk", "pitcher", "batter",
  "pitch_type", "release_speed",
  "balls", "strikes", "stand", "p_throws"
)

# Load the complete April 2025 dataset
statcast_april <- readRDS(
  "data/statcast_april_2025.rds"
)

# Validate required columns
stopifnot(
  all(required_vars %in% names(statcast_april))
)

# Keep pitches with complete required measurements
trajectory_data <- statcast_april %>%
  filter(
    if_all(all_of(required_vars), ~ !is.na(.x))
  )

# Confirm expected dataset size
stopifnot(nrow(trajectory_data) == 108400)

cat("April data loaded:", nrow(trajectory_data), "pitches\n")
