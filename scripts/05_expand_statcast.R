
library(baseballr)
library(tidyverse)

# ---------------------------------------------------
# 1. DEFINE APRIL DOWNLOAD PERIODS
# ---------------------------------------------------

date_ranges <- tibble(
  start_date = c(
    "2025-04-01", "2025-04-08", "2025-04-15",
    "2025-04-22", "2025-04-29"
  ),
  end_date = c(
    "2025-04-07", "2025-04-14", "2025-04-21",
    "2025-04-28", "2025-04-30"
  )
)

dir.create("data", showWarnings = FALSE)


# ---------------------------------------------------
# 2. DOWNLOAD AND CACHE DATA
# ---------------------------------------------------

for (i in seq_len(nrow(date_ranges))) {
  
  file_path <- sprintf(
    "data/statcast_april_batch_%02d.rds", i
  )
  
  if (file.exists(file_path)) {
    message("Using saved batch ", i)
    next
  }
  
  batch <- baseballr::statcast_search(
    start_date = date_ranges$start_date[i],
    end_date = date_ranges$end_date[i]
  ) %>%
    filter(game_type == "R")
  
  if (nrow(batch) == 0) {
    stop("Empty download for batch ", i)
  }
  
  saveRDS(batch, file_path)
  message("Saved batch ", i, ": ", nrow(batch), " pitches")
}


# ---------------------------------------------------
# 3. COMBINE AND VALIDATE
# ---------------------------------------------------

batch_files <- sprintf(
  "data/statcast_april_batch_%02d.rds",
  seq_len(nrow(date_ranges))
)

statcast_april <- purrr::map(batch_files, readRDS) %>%
  list_rbind() %>%
  distinct(
    game_pk, at_bat_number, pitch_number,
    .keep_all = TRUE
  ) %>%
  mutate(game_date = as.Date(game_date))

stopifnot(
  nrow(statcast_april) > 0,
  all(statcast_april$game_type == "R"),
  all(statcast_april$game_date >= as.Date("2025-04-01")),
  all(statcast_april$game_date <= as.Date("2025-04-30"))
)


# ---------------------------------------------------
# 4. SAVE DATASET
# ---------------------------------------------------

saveRDS(
  statcast_april,
  "data/statcast_april_2025.rds"
)

download_summary <- statcast_april %>%
  summarise(
    pitches = n(),
    pitchers = n_distinct(pitcher),
    batters = n_distinct(batter),
    games = n_distinct(game_pk),
    first_date = min(game_date),
    last_date = max(game_date)
  )

print(download_summary, width = Inf)
