
library(baseballr)
library(tidyverse)

# ---------------------------------------------------
# 1. DEFINE MAY DOWNLOAD PERIOD
# ---------------------------------------------------

may_dates <- as.character(seq(
  as.Date("2025-05-01"),
  as.Date("2025-05-07"),
  by = "day"
))

dir.create(
  "data/may_daily",
  recursive = TRUE,
  showWarnings = FALSE
)

# ---------------------------------------------------
# 2. DOWNLOAD AND CACHE DAILY DATA
# ---------------------------------------------------

for (date in may_dates) {
  
  file_path <- paste0("data/may_daily/", date, ".rds")
  
  if (file.exists(file_path)) {
    message("Using saved data: ", date)
    next
  }
  
  daily_data <- baseballr::statcast_search(
    start_date = date,
    end_date = date
  ) %>%
    filter(game_type == "R")
  
  if (nrow(daily_data) == 0) {
    stop("Empty download for ", date)
  }
  
  if (any(as.character(daily_data$game_date) != date)) {
    stop("Incorrect game dates for ", date)
  }
  
  saveRDS(daily_data, file_path)
  
  message("Saved ", date, ": ", nrow(daily_data), " pitches")
}

# ---------------------------------------------------
# 3. COMBINE DAILY DATA
# ---------------------------------------------------

daily_files <- paste0(
  "data/may_daily/",
  may_dates,
  ".rds"
)

stopifnot(all(file.exists(daily_files)))

statcast_may_complete <- purrr::map(
  daily_files,
  readRDS
) %>%
  list_rbind() %>%
  distinct(
    game_pk, at_bat_number, pitch_number,
    .keep_all = TRUE
  ) %>%
  mutate(game_date = as.Date(game_date))

# ---------------------------------------------------
# 4. VALIDATE MAY DATA
# ---------------------------------------------------

stopifnot(
  nrow(statcast_may_complete) > 0,
  all(statcast_may_complete$game_type == "R"),
  setequal(
    as.character(unique(statcast_may_complete$game_date)),
    may_dates
  )
)

daily_summary <- statcast_may_complete %>%
  count(game_date, name = "pitches") %>%
  arrange(game_date)

print(daily_summary, n = Inf)

# ---------------------------------------------------
# 5. SAVE VERIFIED DATASET
# ---------------------------------------------------

saveRDS(
  statcast_may_complete,
  "data/statcast_may_verified_2025.rds"
)

message(
  "May dataset saved: ",
  nrow(statcast_may_complete),
  " pitches"
)
