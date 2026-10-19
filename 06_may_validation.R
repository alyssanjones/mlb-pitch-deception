
library(tidyverse)

# ---------------------------------------------------
# 1. LOAD VERIFIED MAY DATA
# ---------------------------------------------------

statcast_may <- readRDS(
  "data/statcast_may_verified_2025.rds"
)

# ---------------------------------------------------
# 2. VALIDATE MAY DATA
# ---------------------------------------------------

statcast_may <- statcast_may %>%
  mutate(game_date = as.Date(game_date))

stopifnot(
  nrow(statcast_may) > 0,
  all(statcast_may$game_type == "R"),
  all(statcast_may$game_date >= as.Date("2025-05-01")),
  all(statcast_may$game_date <= as.Date("2025-05-07")),
  !anyDuplicated(
    statcast_may[c(
      "game_pk", "at_bat_number", "pitch_number"
    )]
  )
)

may_download_summary <- statcast_may %>%
  summarise(
    pitches = n(),
    pitchers = n_distinct(pitcher),
    games = n_distinct(game_pk),
    first_date = min(game_date),
    last_date = max(game_date)
  )

print(may_download_summary, width = Inf)
