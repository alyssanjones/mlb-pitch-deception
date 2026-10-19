library(baseballr)
library(tidyverse)

dates <- as.character(seq(
  as.Date("2025-05-08"),
  as.Date("2025-05-14"),
  by = "day"
))

dir.create("data/may_daily", recursive = TRUE,
           showWarnings = FALSE)

for (date in dates) {
  
  file <- paste0("data/may_daily/", date, ".rds")
  
  if (file.exists(file)) next
  
  batch <- baseballr::statcast_search(
    start_date = date,
    end_date = date
  ) %>%
    filter(game_type == "R")
  
  if (nrow(batch) == 0 ||
      any(is.na(batch$game_date)) ||
      any(as.character(batch$game_date) != date)) {
    stop("Invalid download for ", date)
  }
  
  saveRDS(batch, file)
  message(date, ": ", nrow(batch), " pitches")
}

# Summarize downloaded dates
map_dfr(dates, function(date) {
  data <- readRDS(
    paste0("data/may_daily/", date, ".rds")
  )
  
  tibble(
    game_date = date,
    pitches = nrow(data),
    games = n_distinct(data$game_pk)
  )
}) %>%
  print(n = Inf)