
library(tidyverse)

# ---------------------------------------------------
# 1. DEFINE STRIKE-ZONE DIMENSIONS
# ---------------------------------------------------

plate_half_width <- 8.5 / 12
ball_radius <- 1.45 / 12


# ---------------------------------------------------
# 2. CLASSIFY PITCH LOCATIONS
# ---------------------------------------------------

strike_zone_data <- decision_data %>%
  mutate(
    # Ball center within the rectangular zone
    strike_center = as.integer(
      abs(plate_x) <= plate_half_width &
        plate_z >= sz_bot &
        plate_z <= sz_top
    ),
    
    # Distance from ball center to strike-zone rectangle
    dx = pmax(abs(plate_x) - plate_half_width, 0),
    dz = pmax(sz_bot - plate_z, plate_z - sz_top, 0),
    
    distance_to_zone = sqrt(dx^2 + dz^2),
    
    # Primary outcome: ball intersects the strike zone
    strike_overlap = as.integer(
      distance_to_zone <= ball_radius
    ),
    
    # Distance relative to the modeled overlap boundary
    overlap_margin = distance_to_zone - ball_radius
  ) %>%
  select(-dx, -dz)


# ---------------------------------------------------
# 3. VALIDATE CLASSIFICATIONS
# ---------------------------------------------------

stopifnot(
  nrow(strike_zone_data) == nrow(decision_data),
  all(!is.na(strike_zone_data$strike_overlap)),
  all(!is.na(strike_zone_data$strike_center)),
  all(strike_zone_data$strike_overlap >=
        strike_zone_data$strike_center)
)

strike_zone_summary <- strike_zone_data %>%
  summarise(
    pitches = n(),
    center_strikes = sum(strike_center),
    overlap_strikes = sum(strike_overlap),
    changed_labels = sum(strike_center != strike_overlap),
    flagged_pitches = sum(reconstruction_flag_001)
  )

print(strike_zone_summary, width = Inf)
