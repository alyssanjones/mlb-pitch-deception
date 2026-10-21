# 04_deception_model.R
# Requires April strike_zone_data from 03_strike_zone.R.
# The GAM is a RETROSPECTIVE benchmark: decision coordinates use full-flight fits.

library(tidyverse)
library(mgcv)

# 1. Validate inputs and define chronological splits -----------------------
needed <- c("game_date", "strike_overlap", "balls", "strikes", "stand",
            "p_throws", "x_decision", "y_decision", "z_decision")
if (!exists("strike_zone_data")) {
  stop("Run 01_data_collection.R, 02_trajectory_reconstruction.R, and 03_strike_zone.R first.")
}
if (!all(needed %in% names(strike_zone_data))) {
  stop("Missing model columns: ",
       paste(setdiff(needed, names(strike_zone_data)), collapse = ", "))
}

model_data <- strike_zone_data %>%
  mutate(game_date = as.Date(game_date))
if (anyNA(model_data[, needed]) ||
    !all(model_data$strike_overlap %in% c(0, 1))) {
  stop("Model inputs contain missing values or invalid strike labels.")
}
if (any(model_data$game_date < as.Date("2025-04-01") |
        model_data$game_date > as.Date("2025-04-30"))) {
  stop("This training script accepts April 1-30, 2025 data only; do not train on May.")
}

train_data <- model_data %>% filter(game_date <= as.Date("2025-04-20"))
calibration_data <- model_data %>%
  filter(game_date >= as.Date("2025-04-21"),
         game_date <= as.Date("2025-04-25"))
evaluation_data <- model_data %>% filter(game_date >= as.Date("2025-04-26"))
stopifnot(nrow(train_data) > 0, nrow(calibration_data) > 0,
          nrow(evaluation_data) > 0)

# Train context-only baseline on April 1-20
baseline_model <- glm(
  strike_overlap ~ balls + strikes + stand + p_throws,
  data = train_data,
  family = binomial(link = "logit")
)

# Save the trained model
dir.create("models", showWarnings = FALSE)

saveRDS(
  baseline_model,
  "models/baseline_model.rds"
)

# Save the constant-model strike probability
train_strike_rate <- mean(train_data$strike_overlap)

saveRDS(
  train_strike_rate,
  "models/constant_strike_rate.rds"
)

# Verify both files exist
stopifnot(
  file.exists("models/baseline_model.rds"),
  file.exists("models/constant_strike_rate.rds")
)

# 2. Fit the already-selected GAM on April 1-20 only -----------------------
# k = 10 was selected previously using April 21-25; don't retune on May.
gam_model_k10 <- mgcv::gam(
  strike_overlap ~ balls + strikes + stand + p_throws +
    s(x_decision, k = 10) + s(y_decision, k = 10) +
    s(z_decision, k = 10),
  data = train_data,
  family = binomial(link = "logit"),
  method = "REML"
)


evaluation_data <- evaluation_data %>%
  mutate(
    gam_prob = as.numeric(
      predict(
        gam_model_k10,
        newdata = evaluation_data,
        type = "response"
      )
    )
  )

# Save the model so later scripts can load it in a fresh R session.
dir.create("models", showWarnings = FALSE)
saveRDS(gam_model_k10, "models/gam_model_k10.rds")

# 3. Reusable out-of-sample evaluation ------------------------------------
score_gam <- function(data, model) {
  probability <- as.numeric(predict(model, newdata = data,
                                    type = "response"))
  if (length(probability) != nrow(data) ||
      any(!is.finite(probability)) ||
      any(probability < 0 | probability > 1)) {
    stop("Invalid GAM predictions.")
  }
  actual <- data$strike_overlap
  p <- pmin(pmax(probability, 1e-15), 1 - 1e-15)
  bin <- cut(probability, breaks = seq(0, 1, by = 0.1),
             include.lowest = TRUE)
  ece <- tibble(actual, probability, bin) %>%
    group_by(bin) %>%
    summarise(n = n(), predicted = mean(probability),
              observed = mean(actual), .groups = "drop") %>%
    summarise(value = weighted.mean(abs(predicted - observed), n)) %>%
    pull(value)
  tibble(
    pitches = length(actual),
    accuracy = mean((probability >= 0.5) == actual),
    brier_score = mean((probability - actual)^2),
    log_loss = -mean(actual * log(p) + (1 - actual) * log1p(-p)),
    ece = ece
  )
}

april_model_results <- bind_rows(
  score_gam(calibration_data, gam_model_k10) %>%
    mutate(period = "April 21-25 calibration"),
  score_gam(evaluation_data, gam_model_k10) %>%
    mutate(period = "April 26-30 evaluation")
) %>%
  select(period, everything())

print(april_model_results, width = Inf)
message("GAM saved to models/gam_model_k10.rds")