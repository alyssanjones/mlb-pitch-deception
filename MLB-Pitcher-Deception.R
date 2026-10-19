library(baseballr)
library(tidyverse)

statcast_sample <- baseballr::statcast_search(
  start_date = "2025-04-01",
  end_date = "2025-04-03"
)

# Keep only regular-season games
statcast_sample <- statcast_sample %>%
  filter(game_type == "R")

# Inspect the data
dim(statcast_sample)

glimpse(statcast_sample)