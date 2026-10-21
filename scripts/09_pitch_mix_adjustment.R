library(tidyverse)

# Exploratory May-only, leave-one-pitcher-out pitch-type adjustment.
# These are retrospective GAM errors, not verified batter deception.
stopifnot(all(c('pitcher', 'pitch_type', 'strike_overlap', 'gam_prob') %in%
                names(may_evaluation)))

pitch_errors <- may_evaluation %>%
  mutate(
    confident_error = as.integer(
      (strike_overlap == 0 & gam_prob >= 0.70) |
      (strike_overlap == 1 & gam_prob <= 0.30)
    )
  )

pitch_type_reference <- pitch_errors %>%
  group_by(pitch_type, strike_overlap) %>%
  summarise(reference_pitches = n(),
            reference_errors = sum(confident_error), .groups = 'drop')

pitcher_cells <- pitch_errors %>%
  group_by(pitcher, pitch_type, strike_overlap) %>%
  summarise(pitches = n(), observed = sum(confident_error),
            .groups = 'drop') %>%
  left_join(pitch_type_reference, by = c('pitch_type', 'strike_overlap')) %>%
  mutate(
    other_pitches = reference_pitches - pitches,
    other_errors = reference_errors - observed,
    expected_rate = if_else(other_pitches > 0,
                            other_errors / other_pitches, NA_real_),
    expected = pitches * expected_rate
  )


# Summarize observed vs. expected errors by pitcher
pitch_mix_summary <- pitcher_cells %>%
  group_by(pitcher) %>%
  summarise(
    total_pitches = sum(pitches),
    
    eligible_pitches = sum(
      pitches[!is.na(expected_rate)]
    ),
    
    observed_errors = sum(
      observed[!is.na(expected_rate)]
    ),
    
    expected_errors = sum(expected, na.rm = TRUE),
    
    .groups = "drop"
  ) %>%
  mutate(
    observed_rate = if_else(
      eligible_pitches > 0,
      observed_errors / eligible_pitches,
      NA_real_
    ),
    
    expected_rate = if_else(
      eligible_pitches > 0,
      expected_errors / eligible_pitches,
      NA_real_
    ),
    
    adjusted_pp = 100 * (observed_rate - expected_rate)
  )

# Initial pitcher comparison
pitch_mix_summary %>%
  filter(
    total_pitches >= 50,
    eligible_pitches == total_pitches
  ) %>%
  arrange(desc(adjusted_pp)) %>%
  select(
    pitcher, total_pitches,
    observed_rate, expected_rate, adjusted_pp
  ) %>%
  slice_head(n = 10) %>%
  print(width = Inf)

# Check reference coverage
pitch_mix_summary %>%
  summarise(
    pitchers = n(),
    eligible_pitchers = sum(
      eligible_pitches == total_pitches
    ),
    pitches_without_reference = sum(
      total_pitches - eligible_pitches
    )
  )







# Identify the pitcher's throwing hand
pitcher_hand <- may_evaluation %>%
  filter(pitcher == 669461) %>%
  distinct(p_throws) %>%
  pull(p_throws)

stopifnot(length(pitcher_hand) == 1)

# Compare with same-handed pitchers
handedness_comparison <- may_evaluation %>%
  filter(
    pitch_type %in% c("SL", "FC"),
    p_throws == pitcher_hand
  ) %>%
  mutate(
    group = if_else(
      pitcher == 669461,
      "Pitcher 669461",
      "Same-handed peers"
    )
  ) %>%
  group_by(pitch_type, group) %>%
  summarise(
    pitches = n(),
    avg_velocity = mean(release_speed, na.rm = TRUE),
    horizontal_in = mean(pfx_x, na.rm = TRUE) * 12,
    vertical_in = mean(pfx_z, na.rm = TRUE) * 12,
    .groups = "drop"
  ) %>%
  arrange(pitch_type, group)

print(handedness_comparison, n = Inf, width = Inf)






library(tidyverse)

# April 26-30: adjustment-model training data
adjustment_train <- evaluation_data %>%
  mutate(
    confident_error = as.integer(
      (strike_overlap == 0 & gam_prob >= 0.70) |
        (strike_overlap == 1 & gam_prob <= 0.30)
    )
  ) %>%
  filter(
    !is.na(pitch_type),
    !is.na(release_speed),
    !is.na(pfx_x),
    !is.na(pfx_z)
  )



# Verify all model predictors are complete
adjustment_vars <- c(
  "confident_error", "pitch_type",
  "release_speed", "pfx_x", "pfx_z",
  "balls", "strikes", "stand",
  "p_throws", "strike_overlap"
)

stopifnot(
  !anyNA(adjustment_train[, adjustment_vars])
)

# Fit expected-error model using April data only
# Identify sparse pitch types from April training only
common_types <- adjustment_train %>%
  count(pitch_type) %>%
  filter(n >= 200) %>%
  pull(pitch_type)

# Group uncommon pitch types in April
adjustment_train <- adjustment_train %>%
  mutate(
    pitch_type_grouped = if_else(
      pitch_type %in% common_types,
      pitch_type,
      "Other"
    ),
    pitch_type_grouped = factor(pitch_type_grouped)
  )

# Refit the expected-error model
error_model <- glm(
  confident_error ~
    pitch_type_grouped +
    release_speed +
    pfx_x + pfx_z +
    balls + strikes +
    stand + p_throws +
    strike_overlap,
  data = adjustment_train,
  family = binomial(link = "logit")
)



# Prepare May using April's pitch-type categories
adjustment_test <- may_evaluation %>%
  mutate(
    pitch_type_grouped = if_else(
      pitch_type %in% common_types,
      pitch_type,
      "Other"
    ),
    pitch_type_grouped = factor(
      pitch_type_grouped,
      levels = levels(adjustment_train$pitch_type_grouped)
    ),
    
    confident_error = as.integer(
      (strike_overlap == 0 & gam_prob >= 0.70) |
        (strike_overlap == 1 & gam_prob <= 0.30)
    )
  )

# Use complete observations for the adjustment model
adjustment_test <- adjustment_test %>%
  filter(
    !is.na(pitch_type_grouped),
    !is.na(release_speed),
    !is.na(pfx_x),
    !is.na(pfx_z),
    !is.na(balls),
    !is.na(strikes),
    !is.na(stand),
    !is.na(p_throws),
    !is.na(strike_overlap)
  )

# Predict expected error probabilities
adjustment_test <- adjustment_test %>%
  mutate(
    expected_error_prob = as.numeric(
      predict(
        error_model,
        newdata = adjustment_test,
        type = "response"
      )
    )
  )

# Verify prediction quality and coverage
adjustment_check <- adjustment_test %>%
  summarise(
    pitches = n(),
    observed_error_rate = mean(confident_error),
    expected_error_rate = mean(expected_error_prob),
    min_probability = min(expected_error_prob),
    max_probability = max(expected_error_prob)
  )

stopifnot(
  all(is.finite(adjustment_test$expected_error_prob)),
  all(adjustment_test$expected_error_prob >= 0),
  all(adjustment_test$expected_error_prob <= 1)
)

print(adjustment_check, width = Inf)




# Check fitting stability
stopifnot(
  error_model$converged,
  all(is.finite(coef(error_model)))
)

summary(error_model)
# Inspect model fit
summary(error_model)

# Check for numerical fitting problems
stopifnot(
  error_model$converged,
  all(is.finite(coef(error_model)))
)

# Save for use in May evaluation
dir.create("models", showWarnings = FALSE)

saveRDS(
  error_model,
  "models/expected_error_model.rds"
)




# Check the response distribution
adjustment_train %>%
  count(confident_error) %>%
  mutate(percentage = round(100 * n / sum(n), 2))





# Constant benchmark learned from April only
constant_error_prob <- mean(adjustment_train$confident_error)

# Evaluate predicted probabilities
score_error_model <- function(actual, predicted, model_name) {
  p <- pmin(pmax(predicted, 1e-15), 1 - 1e-15)
  
  tibble(
    model = model_name,
    brier_score = mean((p - actual)^2),
    log_loss = -mean(
      actual * log(p) +
        (1 - actual) * log(1 - p)
    ),
    ece = calculate_ece(actual, p, bins = 10)
  )
}

# Both models evaluated on identical May observations
error_model_comparison <- bind_rows(
  score_error_model(
    adjustment_test$confident_error,
    rep(constant_error_prob, nrow(adjustment_test)),
    "Constant"
  ),
  score_error_model(
    adjustment_test$confident_error,
    adjustment_test$expected_error_prob,
    "Adjusted logistic"
  )
)

print(error_model_comparison, width = Inf)











adjusted_pitcher_scores <- adjustment_test %>%
  group_by(pitcher) %>%
  summarise(
    pitches = n(),
    observed_errors = sum(confident_error),
    expected_errors = sum(expected_error_prob),
    observed_rate = mean(confident_error),
    expected_rate = mean(expected_error_prob),
    .groups = "drop"
  ) %>%
  mutate(
    adjusted_pp = 100 * (observed_rate - expected_rate)
  ) %>%
  arrange(desc(adjusted_pp))

# Exploratory rankings
adjusted_pitcher_scores %>%
  filter(pitches >= 50) %>%
  slice_head(n = 10) %>%
  print(width = Inf)

# Check the overall adjustment
adjusted_pitcher_scores %>%
  summarise(
    pitchers = n(),
    total_pitches = sum(pitches),
    total_observed = sum(observed_errors),
    total_expected = sum(expected_errors)
  ) %>%
  print(width = Inf)







# Summarize each pitcher's individual games
pitcher_game_summary <- adjustment_test %>%
  group_by(pitcher, game_pk) %>%
  summarise(
    game_pitches = n(),
    game_errors = sum(confident_error),
    game_expected = sum(expected_error_prob),
    .groups = "drop"
  )

# Aggregate games without overwriting intermediate columns
game_consistency <- pitcher_game_summary %>%
  group_by(pitcher) %>%
  summarise(
    games = n(),
    pitches = sum(game_pitches),
    observed_errors = sum(game_errors),
    expected_errors = sum(game_expected),
    
    max_errors_one_game = max(game_errors),
    
    pct_errors_one_game = if_else(
      sum(game_errors) > 0,
      100 * max(game_errors) / sum(game_errors),
      NA_real_
    ),
    
    .groups = "drop"
  ) %>%
  filter(
    pitcher %in% c(681982, 621199, 669461, 605463, 642547)
  ) %>%
  arrange(desc(pitches))

print(game_consistency, width = Inf)