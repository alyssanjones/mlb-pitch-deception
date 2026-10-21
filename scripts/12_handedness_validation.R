# 12_handedness_validation.R
# Chronological May 8-14 follow-up, with April-trained models kept frozen.
# Requires Files 01-04, 08, and 11 in the current R session.
# Source files 02-03 inside local() to avoid overwriting April objects.

library(tidyverse)
stopifnot(exists("required_vars"), exists("gam_model_k10"),
          exists("predict_handedness"), exists("score_hand_models"))

week2_dates <- as.character(seq(as.Date("2025-05-08"),
                                 as.Date("2025-05-14"), by = "day"))
week2_files <- file.path("data", "may_daily", paste0(week2_dates, ".rds"))
if (!all(file.exists(week2_files))) {
  stop("Missing daily files: ", paste(week2_files[!file.exists(week2_files)], collapse = ", "))
}

may_week2_raw <- purrr::map_dfr(week2_files, readRDS) %>%
  mutate(game_date = as.Date(game_date))
stopifnot(nrow(may_week2_raw) > 0,
          all(may_week2_raw$game_type == "R"),
          all(as.character(may_week2_raw$game_date) %in% week2_dates),
          all(required_vars %in% names(may_week2_raw)),
          !anyDuplicated(may_week2_raw[c("game_pk", "at_bat_number", "pitch_number")]))

may_week2_summary <- may_week2_raw %>%
  summarise(total_pitches = n(), games = n_distinct(game_pk),
            pitchers = n_distinct(pitcher), first_date = min(game_date),
            last_date = max(game_date),
            missing_pitch_ids = sum(is.na(game_pk) | is.na(at_bat_number) | is.na(pitch_number)))
print(may_week2_summary, width = Inf)

may_week2_complete <- may_week2_raw %>%
  filter(if_all(all_of(required_vars), ~ !is.na(.x)))

may_week2_evaluation <- local({
  trajectory_data <- may_week2_complete
  source("scripts/02_trajectory_reconstruction.R", local = TRUE)
  source("scripts/03_strike_zone.R", local = TRUE)
  strike_zone_data
})

may_week2_validation <- may_week2_evaluation %>%
  summarise(pitches = n(), pitchers = n_distinct(pitcher),
            lhp_pitches = sum(p_throws == "L"),
            rhp_pitches = sum(p_throws == "R"),
            strike_rate = mean(strike_overlap),
            x_mae = mean(abs(x_error)), z_mae = mean(abs(z_error)),
            flagged_pitches = sum(reconstruction_flag_001))
print(may_week2_validation, width = Inf)

may_week2_evaluation$gam_prob <- as.numeric(predict(
  gam_model_k10, newdata = may_week2_evaluation, type = "response"))
may_week2_evaluation <- predict_handedness(may_week2_evaluation)

week2_model_comparison <- score_hand_models(may_week2_evaluation)
print(week2_model_comparison, width = Inf)

week2_handedness_performance <- may_week2_evaluation %>%
  select(p_throws, strike_overlap, gam_prob, separate_prob,
         mirrored_prob, mirrored_full_prob) %>%
  pivot_longer(c(gam_prob, separate_prob, mirrored_prob, mirrored_full_prob),
               names_to = "model", values_to = "predicted") %>%
  group_by(p_throws, model) %>%
  summarise(pitches = n(),
            accuracy = mean((predicted >= 0.5) == strike_overlap),
            brier = mean((predicted - strike_overlap)^2),
            log_loss = -mean(strike_overlap * log(pmax(predicted, 1e-15)) +
                               (1 - strike_overlap) * log(pmax(1 - predicted, 1e-15))),
            .groups = "drop") %>%
  arrange(p_throws, brier)
print(week2_handedness_performance, n = Inf, width = Inf)

game_model_performance <- may_week2_evaluation %>%
  group_by(game_pk) %>%
  summarise(pitches = n(),
            original_brier = mean((gam_prob - strike_overlap)^2),
            separate_brier = mean((separate_prob - strike_overlap)^2),
            .groups = "drop") %>%
  mutate(brier_improvement = original_brier - separate_brier)
game_improvement_summary <- game_model_performance %>%
  summarise(games = n(), games_improved = sum(brier_improvement > 0),
            games_worse = sum(brier_improvement < 0),
            games_tied = sum(brier_improvement == 0),
            median_improvement = median(brier_improvement),
            mean_improvement = mean(brier_improvement))
print(game_improvement_summary, width = Inf)

# Save the evaluated observations; files in data/ should remain gitignored.
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
saveRDS(may_week2_evaluation, "data/processed/may_week2_evaluation.rds")
