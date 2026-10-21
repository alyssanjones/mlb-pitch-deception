# 11_handedness_models.R
# Train throwing-hand-specific and mirrored GAMs on April 1-20 only.
# Model selection on May 1-7 is exploratory; May 8-14 is the follow-up check.
# Requires: source("scripts/01_data_collection.R") through 04, then File 08.

library(tidyverse)
library(mgcv)

stopifnot(exists("train_data"), exists("may_evaluation"))
model_vars <- c("strike_overlap", "balls", "strikes", "stand", "p_throws",
                "x_decision", "y_decision", "z_decision")
stopifnot(all(model_vars %in% names(train_data)),
          all(model_vars %in% names(may_evaluation)))

train_lhp <- train_data %>% filter(p_throws == "L")
train_rhp <- train_data %>% filter(p_throws == "R")
stopifnot(nrow(train_lhp) > 0, nrow(train_rhp) > 0)

handedness_formula <- strike_overlap ~ balls + strikes + stand +
  s(x_decision, k = 10) + s(y_decision, k = 10) + s(z_decision, k = 10)

gam_lhp <- mgcv::gam(handedness_formula, data = train_lhp,
                     family = binomial(link = "logit"), method = "REML")
gam_rhp <- mgcv::gam(handedness_formula, data = train_rhp,
                     family = binomial(link = "logit"), method = "REML")

# Mirror only the X decision coordinate for left-handed pitchers.
# This is a modeling representation, NOT a leakage-free trajectory.
add_mirrored_features <- function(data, reference_levels = c("Opposite", "Same")) {
  data %>%
    mutate(
      x_mirrored = if_else(p_throws == "L", -x_decision, x_decision),
      stand_relative = factor(if_else(stand == p_throws, "Same", "Opposite"),
                              levels = reference_levels)
    )
}

train_mirrored <- add_mirrored_features(train_data)

gam_mirrored <- mgcv::gam(
  strike_overlap ~ balls + strikes + stand_relative +
    s(x_mirrored, k = 10) + s(y_decision, k = 10) + s(z_decision, k = 10),
  data = train_mirrored,
  family = binomial(link = "logit"), method = "REML"
)

gam_mirrored_full <- mgcv::gam(
  strike_overlap ~ balls + strikes + stand + p_throws +
    s(x_mirrored, k = 10) + s(y_decision, k = 10) + s(z_decision, k = 10),
  data = train_mirrored,
  family = binomial(link = "logit"), method = "REML"
)

# Predict separate models while retaining original pitch ordering.
predict_handedness <- function(data) {
  stopifnot(all(model_vars %in% names(data)),
            all(data$p_throws %in% c("L", "R")))
  result <- add_mirrored_features(data, levels(train_mirrored$stand_relative))
  result$separate_prob <- NA_real_
  idx_l <- which(result$p_throws == "L")
  idx_r <- which(result$p_throws == "R")
  if (length(idx_l)) result$separate_prob[idx_l] <- as.numeric(
    predict(gam_lhp, newdata = result[idx_l, ], type = "response"))
  if (length(idx_r)) result$separate_prob[idx_r] <- as.numeric(
    predict(gam_rhp, newdata = result[idx_r, ], type = "response"))
  result$mirrored_prob <- as.numeric(predict(
    gam_mirrored, newdata = result, type = "response"))
  result$mirrored_full_prob <- as.numeric(predict(
    gam_mirrored_full, newdata = result, type = "response"))
  cols <- c("separate_prob", "mirrored_prob", "mirrored_full_prob")
  stopifnot(all(vapply(result[cols], function(x) all(is.finite(x) & x >= 0 & x <= 1), logical(1))))
  result
}

score_hand_models <- function(data) {
  data %>%
    select(strike_overlap, gam_prob, separate_prob, mirrored_prob, mirrored_full_prob) %>%
    pivot_longer(-strike_overlap, names_to = "model", values_to = "prob") %>%
    group_by(model) %>%
    summarise(
      pitches = n(),
      accuracy = mean((prob >= 0.5) == strike_overlap),
      brier = mean((prob - strike_overlap)^2),
      log_loss = -mean(strike_overlap * log(pmax(prob, 1e-15)) +
                         (1 - strike_overlap) * log(pmax(1 - prob, 1e-15))),
      .groups = "drop"
    ) %>% arrange(brier)
}

handedness_test <- predict_handedness(may_evaluation)
model_comparison <- score_hand_models(handedness_test)
print(model_comparison, width = Inf)

dir.create("models", showWarnings = FALSE)
saveRDS(gam_lhp, "models/gam_lhp.rds")
saveRDS(gam_rhp, "models/gam_rhp.rds")
saveRDS(gam_mirrored, "models/gam_mirrored.rds")
saveRDS(gam_mirrored_full, "models/gam_mirrored_full.rds")
