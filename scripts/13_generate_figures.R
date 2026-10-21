# 13_generate_figures.R
# Publication-quality figures for the MLB Pitcher Deception project.
# Run from the repository root: source("scripts/13_generate_figures.R")
# This script only visualizes existing analysis outputs; it does not fit models.

library(tidyverse)

if (!dir.exists("scripts") || !dir.exists("figures")) {
  stop("Run from the project root, which must contain scripts/ and figures/.")
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

get_result <- function(name) {
  if (exists(name, envir = .GlobalEnv, inherits = FALSE)) {
    return(get(name, envir = .GlobalEnv))
  }
  path <- file.path("data", "processed", paste0(name, ".rds"))
  if (file.exists(path)) return(readRDS(path))
  NULL
}

has_columns <- function(data, columns) {
  !is.null(data) && all(columns %in% names(data))
}

skip_figure <- function(name, reason) {
  message("SKIP ", name, ": ", reason)
}

model_palette <- c(
  "Original GAM" = "#5B3F8C",
  "Separate LHP/RHP" = "#1B9E77",
  "Mirrored (relative)" = "#2C7FB8",
  "Mirrored (original)" = "#D95F02"
)

outcome_palette <- c(
  "Correct classification" = "#2166AC",
  "False strike" = "#B2182B",
  "Hidden strike" = "#D8A031"
)

hand_palette <- c(
  "Left-handed" = "#2C7FB8",
  "Right-handed" = "#B2182B"
)

fmt_pct <- function(x, digits = 0.1) {
  scales::percent(x, accuracy = digits)
}

fmt_num <- function(x, digits = 3) {
  formatC(x, digits = digits, format = "f")
}

theme_publication <- function() {
  theme_minimal(base_size = 13) +
    theme(
      plot.title = element_text(face = "bold", size = 16, colour = "#1F2937"),
      plot.subtitle = element_text(size = 11.5, colour = "#4B5563", margin = margin(b = 8)),
      plot.caption = element_text(size = 9, colour = "#6B7280", hjust = 0, margin = margin(t = 10)),
      axis.title = element_text(face = "bold", colour = "#374151"),
      axis.text = element_text(colour = "#374151"),
      strip.text = element_text(face = "bold", colour = "#1F2937"),
      legend.position = "bottom",
      legend.title = element_blank(),
      legend.text = element_text(colour = "#374151"),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_line(colour = "#E5E7EB", linewidth = 0.35),
      panel.grid.major.y = element_blank(),
      plot.margin = margin(14, 18, 12, 12)
    )
}

save_figure <- function(plot, filename, width = 9, height = 6) {
  png_path <- file.path("figures", filename)
  pdf_path <- file.path("figures", sub("\\.png$", ".pdf", filename))

  ggsave(
    filename = png_path,
    plot = plot,
    width = width,
    height = height,
    dpi = 320,
    bg = "white"
  )

  ggsave(
    filename = pdf_path,
    plot = plot,
    width = width,
    height = height,
    device = cairo_pdf,
    bg = "white"
  )

  message("SAVED ", png_path)
  message("SAVED ", pdf_path)
}

# -----------------------------------------------------------------------------
# Load available analysis objects
# -----------------------------------------------------------------------------

week2 <- get_result("may_week2_evaluation")
may1 <- get_result("may_evaluation")
rankings <- get_result("adjusted_pitcher_scores")
if (is.null(rankings)) rankings <- get_result("pitch_mix_summary")

plot_data <- if (has_columns(week2, c("gam_prob", "strike_overlap"))) week2 else may1
period_label <- if (!is.null(week2) && identical(plot_data, week2)) {
  "May 8–14, 2025"
} else {
  "May 1–7, 2025"
}
prob_col <- if (has_columns(plot_data, "separate_prob")) "separate_prob" else "gam_prob"
model_label <- if (identical(prob_col, "separate_prob")) "Separate LHP/RHP GAMs" else "Original GAM"

# ---------------------------------------------------
# FIGURE 1: RECONSTRUCTED PITCH TRAJECTORY
# ---------------------------------------------------

trajectory_vars <- c(
  "x0", "z0", "vx0", "vy0", "vz0",
  "ax", "ay", "az",
  "t_plate", "t_decision", "y0", "z_decision"
)

trajectory_source <- if (
  has_columns(week2, trajectory_vars)
) week2 else may1

if (
  has_columns(trajectory_source, trajectory_vars) &&
  nrow(trajectory_source) > 0
) {
  
  candidate <- trajectory_source %>%
    filter(
      is.finite(t_plate),
      is.finite(t_decision),
      t_decision > 0,
      t_decision < t_plate,
      is.finite(z_decision)
    )
  
  if (nrow(candidate) > 0) {
    
    pitch <- candidate[1, ]
    
    # Reconstruct trajectory
    times <- seq(
      0,
      pitch$t_plate,
      length.out = 180
    )
    
    flight <- tibble(
      t = times,
      
      y = pitch$y0 +
        pitch$vy0 * times +
        0.5 * pitch$ay * times^2,
      
      z = pitch$z0 +
        pitch$vz0 * times +
        0.5 * pitch$az * times^2,
      
      phase = if_else(
        times <= pitch$t_decision,
        "Before decision point",
        "After decision point"
      )
    )
    
    # Decision-point coordinates
    decision_y <- pitch$y0 +
      pitch$vy0 * pitch$t_decision +
      0.5 * pitch$ay * pitch$t_decision^2
    
    decision_z <- pitch$z_decision
    
    # Position annotation above the trajectory
    label_y <- decision_y + 5
    label_z <- max(flight$z) + 0.30
    
    # Create figure
    figure_01 <- ggplot(
      flight,
      aes(x = y, y = z, color = phase)
    ) +
      
      geom_path(
        linewidth = 1.5,
        lineend = "round"
      ) +
      
      # Mark estimated decision point
      geom_point(
        data = tibble(
          y = decision_y,
          z = decision_z
        ),
        aes(x = y, y = z),
        inherit.aes = FALSE,
        size = 3.5,
        color = "#111827"
      ) +
      
      # Dashed connector from label to decision point
      annotate(
        "segment",
        x = label_y,
        y = label_z - 0.12,
        xend = decision_y,
        yend = decision_z + 0.08,
        linetype = "dashed",
        linewidth = 0.55,
        color = "#6B7280"
      ) +
      
      # Decision-point annotation
      annotate(
        "label",
        x = label_y,
        y = label_z,
        label = "Decision point (175 ms)",
        size = 3.7,
        fontface = "bold",
        fill = "white",
        color = "#1F2937",
        label.size = 0.25,
        label.padding = grid::unit(0.25, "lines")
      ) +
      
      # Plate crossing reference
      geom_vline(
        xintercept = 1.417,
        linetype = "dashed",
        linewidth = 0.65,
        color = "#6B7280"
      ) +
      
      annotate(
        "text",
        x = 3.3,
        y = min(flight$z) - 0.18,
        label = "Home plate",
        size = 3.5,
        color = "#374151"
      ) +
      
      scale_x_reverse() +
      
      scale_y_continuous(
        expand = expansion(mult = c(0.12, 0.24))
      ) +
      
      scale_color_manual(
        values = c(
          "Before decision point" = "#2166AC",
          "After decision point" = "#B2182B"
        ),
        breaks = c(
          "Before decision point",
          "After decision point"
        )
      ) +
      
      labs(
        title = "Example Reconstructed Pitch Trajectory",
        
        subtitle = paste(
          "Side view of a pitch trajectory",
          "with its estimated swing-decision point"
        ),
        
        x = "Distance from back of home plate (ft)",
        y = "Ball height (ft)",
        color = NULL,
        
        caption = paste(
          "Trajectory reconstructed using full-flight-fitted",
          "Statcast parameters; not independent pre-decision tracking."
        )
      ) +
      
      theme_publication() +
      
      theme(
        legend.position = "bottom",
        panel.grid.minor = element_blank()
      )
    
    print(figure_01)
    
    save_figure(
      figure_01,
      "figure_01_trajectory_example.png",
      width = 9,
      height = 6
    )
    
  } else {
    skip_figure("01", "no suitable reconstructed pitches")
  }
  
} else {
  skip_figure("01", "trajectory data unavailable")
}

# -----------------------------------------------------------------------------
# Figure 02: Model comparison
# -----------------------------------------------------------------------------

model_cols <- c(
  "strike_overlap", "gam_prob", "separate_prob",
  "mirrored_prob", "mirrored_full_prob"
)

if (has_columns(week2, model_cols)) {
  comparison <- week2 %>%
    select(all_of(model_cols)) %>%
    pivot_longer(-strike_overlap, names_to = "model", values_to = "probability") %>%
    group_by(model) %>%
    summarise(
      accuracy = mean((probability >= 0.5) == strike_overlap),
      brier = mean((probability - strike_overlap)^2),
      log_loss = -mean(
        strike_overlap * log(pmax(probability, 1e-15)) +
          (1 - strike_overlap) * log(pmax(1 - probability, 1e-15))
      ),
      .groups = "drop"
    ) %>%
    mutate(
      model = recode(
        model,
        gam_prob = "Original GAM",
        separate_prob = "Separate LHP/RHP",
        mirrored_prob = "Mirrored (relative)",
        mirrored_full_prob = "Mirrored (original)"
      ),
      model = factor(
        model,
        levels = c(
          "Original GAM",
          "Separate LHP/RHP",
          "Mirrored (relative)",
          "Mirrored (original)"
        )
      )
    )

  model_plot <- comparison %>%
    pivot_longer(c(accuracy, brier, log_loss), names_to = "metric", values_to = "score") %>%
    mutate(
      metric = factor(metric,
        levels = c("accuracy", "brier", "log_loss"),
        labels = c("Accuracy", "Brier score", "Log loss")
      )
    ) %>%
    group_by(metric) %>%
    mutate(
      metric_min = min(score),
      metric_max = max(score),
      metric_range = pmax(metric_max - metric_min, 0.001),
      axis_min = metric_min - 0.35 * metric_range,
      axis_max = metric_max + 0.45 * metric_range,
      label = if_else(metric == "Accuracy", fmt_pct(score, 0.1), fmt_num(score, 3))
    ) %>%
    ungroup()

  fig <- ggplot(model_plot, aes(x = score, y = model, color = model)) +
    geom_blank(aes(x = axis_min)) +
    geom_blank(aes(x = axis_max)) +
    geom_segment(
      aes(x = axis_min, xend = score, yend = model),
      linewidth = 1.3,
      alpha = 0.7,
      show.legend = FALSE
    ) +
    geom_point(size = 4.3) +
    geom_text(aes(label = label), hjust = -0.2, size = 3.8, fontface = "bold", show.legend = FALSE) +
    facet_wrap(~ metric, scales = "free_x", nrow = 1) +
    coord_cartesian(clip = "off") +
    scale_color_manual(values = model_palette) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.01))) +
    labs(
      title = "Handedness-aware models improve strike-zone forecasting",
      subtitle = "Frozen April-trained models evaluated on May 8–14, 2025. Panels are zoomed separately so small performance differences are visible.",
      x = NULL,
      y = NULL,
      caption = "Accuracy is higher-is-better. Brier score and log loss are lower-is-better. All models are evaluated on the same May pitches."
    ) +
    theme_publication() +
    theme(
      axis.text.y = element_text(face = "bold"),
      strip.text = element_text(size = 12),
      strip.background = element_rect(fill = "#F3F4F6", colour = "#D1D5DB", linewidth = 0.6),
      panel.border = element_rect(colour = "#D1D5DB", fill = NA, linewidth = 0.7),
      panel.spacing = unit(1.2, "lines"),
      plot.margin = margin(14, 34, 12, 12)
    )

  save_figure(fig, "figure_02_model_comparison.png", 12.5, 5.8)
} else {
  skip_figure("02", "need week2 evaluation with all four model probability columns")
}

# -----------------------------------------------------------------------------
# Figure 03: Calibration plot
# -----------------------------------------------------------------------------

if (has_columns(plot_data, c("strike_overlap", prob_col))) {
  calibration <- plot_data %>%
    transmute(
      actual = strike_overlap,
      prob = .data[[prob_col]],
      bin = cut(prob, breaks = seq(0, 1, by = 0.1), include.lowest = TRUE)
    ) %>%
    group_by(bin) %>%
    summarise(
      pitches = n(),
      predicted = mean(prob),
      observed = mean(actual),
      .groups = "drop"
    )

  fig <- ggplot(calibration, aes(predicted, observed)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50", linewidth = 0.8) +
    geom_path(color = "#2166AC", linewidth = 1.1) +
    geom_point(aes(size = pitches), color = "#2166AC", alpha = 0.95) +
    coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
    scale_size_continuous(range = c(2.5, 7)) +
    labs(
      title = "Calibration of predicted strike probabilities",
      subtitle = paste(model_label, "•", period_label),
      x = "Mean predicted strike probability",
      y = "Observed strike rate",
      caption = "Each point represents one fixed 10-bin probability group. The dashed line indicates perfect calibration."
    ) +
    theme_publication()

  save_figure(fig, "figure_03_calibration_plot.png", 8.2, 6.6)
} else {
  skip_figure("03", "need strike outcomes and evaluated probabilities")
}

# -----------------------------------------------------------------------------
# Figure 04: Prediction breakdown
# -----------------------------------------------------------------------------

if (has_columns(plot_data, c("strike_overlap", prob_col))) {
  breakdown <- plot_data %>%
    mutate(type = case_when(
      strike_overlap == 0 & .data[[prob_col]] >= 0.5 ~ "False strike",
      strike_overlap == 1 & .data[[prob_col]] < 0.5 ~ "Hidden strike",
      TRUE ~ "Correct classification"
    )) %>%
    count(type) %>%
    mutate(
      share = n / sum(n),
      type = factor(type, levels = c("Correct classification", "False strike", "Hidden strike"))
    )

  fig <- ggplot(breakdown, aes(x = type, y = share, fill = type)) +
    geom_col(width = 0.68, show.legend = FALSE) +
    geom_text(
      aes(label = fmt_pct(share, 0.1)),
      vjust = -0.35,
      size = 4.1,
      fontface = "bold",
      colour = "#1F2937"
    ) +
    scale_fill_manual(values = outcome_palette) +
    scale_y_continuous(
      labels = scales::percent,
      expand = expansion(mult = c(0, 0.12))
    ) +
    labs(
      title = "Retrospective prediction outcomes by type",
      subtitle = paste(model_label, "•", period_label),
      x = NULL,
      y = "Share of all pitches",
      caption = "False strikes and hidden strikes are model-based classifications, not direct measures of batter perception."
    ) +
    theme_publication() +
    theme(
      axis.text.x = element_text(face = "bold")
    )

  save_figure(fig, "figure_04_prediction_breakdown.png", 8.4, 5.8)
} else {
  skip_figure("04", "need strike outcomes and evaluated probabilities")
}

# -----------------------------------------------------------------------------
# Figure 05: Coxcomb plot by pitch type
# -----------------------------------------------------------------------------

if (has_columns(plot_data, c("pitch_type", "strike_overlap", prob_col))) {
  pitch_rates <- plot_data %>%
    filter(!is.na(pitch_type)) %>%
    group_by(pitch_type) %>%
    summarise(
      pitches = n(),
      balls = sum(strike_overlap == 0),
      strikes = sum(strike_overlap == 1),
      false_strikes = sum(strike_overlap == 0 & .data[[prob_col]] >= 0.70),
      hidden_strikes = sum(strike_overlap == 1 & .data[[prob_col]] <= 0.30),
      .groups = "drop"
    ) %>%
    filter(pitches >= 200, balls >= 50, strikes >= 50) %>%
    mutate(
      false_strike_rate = false_strikes / balls,
      hidden_strike_rate = hidden_strikes / strikes,
      ordering_rate = pmax(false_strike_rate, hidden_strike_rate)
    )

  if (nrow(pitch_rates) > 0) {
    pitch_levels <- pitch_rates %>%
      arrange(desc(ordering_rate)) %>%
      pull(pitch_type)

    pitch_palette <- setNames(
      grDevices::hcl.colors(length(pitch_levels), palette = "Dark 3"),
      pitch_levels
    )

    coxcomb_data <- pitch_rates %>%
      select(pitch_type, false_strike_rate, hidden_strike_rate) %>%
      pivot_longer(
        cols = c(false_strike_rate, hidden_strike_rate),
        names_to = "type",
        values_to = "rate"
      ) %>%
      mutate(
        type = recode(
          type,
          false_strike_rate = "False strike",
          hidden_strike_rate = "Hidden strike"
        ),
        pitch_type = factor(pitch_type, levels = pitch_levels),
        radius = sqrt(rate),
        label = fmt_pct(rate, 0.1)
      )

    max_radius <- max(coxcomb_data$radius)

    fig <- ggplot(coxcomb_data, aes(x = pitch_type, y = radius, fill = pitch_type)) +
      geom_col(width = 1, color = "white", linewidth = 0.5, alpha = 0.98) +
      geom_text(
        aes(y = radius + max_radius * 0.09, label = label),
        size = 3,
        color = "#1F2937"
      ) +
      coord_polar() +
      facet_wrap(~ type) +
      scale_fill_manual(values = pitch_palette) +
      scale_y_continuous(expand = expansion(mult = c(0, 0.22))) +
      labs(
        title = "Confident prediction errors differ by pitch type",
        subtitle = paste(model_label, "•", period_label, "• Coxcomb view"),
        x = NULL,
        y = NULL,
        caption = paste(
          "All slices have equal angle.",
          "Radius is scaled to the square root of the conditional error rate so slice area tracks the underlying rate.",
          "False strikes are calculated among actual balls; hidden strikes are calculated among actual strikes."
        )
      ) +
      theme_publication() +
      theme(
        legend.position = "none",
        axis.text.y = element_blank(),
        axis.text.x = element_text(face = "bold", size = 9),
        panel.grid.major.y = element_line(colour = "#E5E7EB", linewidth = 0.35),
        panel.grid.major.x = element_blank()
      )

    save_figure(fig, "figure_05_pitch_type_errors.png", 11.2, 6.9)
  } else {
    skip_figure("05", "no pitch types meet the minimum sample thresholds")
  }
} else {
  skip_figure("05", "need pitch type, strike outcomes, and evaluated probabilities")
}

# -----------------------------------------------------------------------------
# Figure 06: Exploratory pitcher rankings
# -----------------------------------------------------------------------------

if (has_columns(rankings, c("pitcher", "pitches", "adjusted_pp"))) {
  top <- rankings %>%
    filter(pitches >= 50, is.finite(adjusted_pp)) %>%
    arrange(desc(adjusted_pp)) %>%
    slice_head(n = 12) %>%
    mutate(pitcher_label = as.character(pitcher))

  if (nrow(top) > 0) {
    fig <- ggplot(top, aes(x = reorder(pitcher_label, adjusted_pp), y = adjusted_pp)) +
      geom_col(fill = "#2166AC", width = 0.7) +
      geom_text(aes(label = paste0("n = ", pitches)), hjust = -0.12, size = 3.3, colour = "#374151") +
      coord_flip() +
      scale_y_continuous(expand = expansion(mult = c(0.03, 0.24))) +
      labs(
        title = "Exploratory pitcher rankings from adjusted excess model errors",
        subtitle = "May 1–7 only • at least 50 pitches • preliminary results",
        x = "MLBAM pitcher ID",
        y = "Observed minus expected error rate (percentage points)",
        caption = "These are exploratory retrospective scores, not final validated DPDS rankings. Uncertainty and repeatability have not yet been estimated."
      ) +
      theme_publication()

    save_figure(fig, "figure_06_exploratory_pitchers.png", 9.2, 7)
  } else {
    skip_figure("06", "no pitcher satisfies the minimum sample size threshold")
  }
} else {
  skip_figure("06", "need adjusted_pitcher_scores or pitch_mix_summary")
}

# -----------------------------------------------------------------------------
# Figure 07: Brier score by throwing hand
# -----------------------------------------------------------------------------

if (has_columns(week2, c("p_throws", "strike_overlap", "gam_prob", "separate_prob"))) {
  by_hand <- week2 %>%
    filter(p_throws %in% c("L", "R")) %>%
    select(p_throws, strike_overlap, gam_prob, separate_prob) %>%
    pivot_longer(c(gam_prob, separate_prob), names_to = "model", values_to = "prob") %>%
    group_by(p_throws, model) %>%
    summarise(brier = mean((prob - strike_overlap)^2), .groups = "drop") %>%
    mutate(
      model = recode(model,
        gam_prob = "Original GAM",
        separate_prob = "Separate LHP/RHP"
      ),
      hand = recode(p_throws,
        L = "Left-handed",
        R = "Right-handed"
      )
    )

  fig <- ggplot(by_hand, aes(x = hand, y = brier, fill = model)) +
    geom_col(position = position_dodge(width = 0.72), width = 0.64) +
    geom_text(
      aes(label = fmt_num(brier, 3)),
      position = position_dodge(width = 0.72),
      vjust = -0.35,
      size = 3.7,
      fontface = "bold"
    ) +
    scale_fill_manual(values = c(
      "Original GAM" = model_palette[["Original GAM"]],
      "Separate LHP/RHP" = model_palette[["Separate LHP/RHP"]]
    )) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(
      title = "Brier score improves for both throwing-hand groups",
      subtitle = "May 8–14, 2025 • lower values indicate better probability forecasts",
      x = NULL,
      y = "Brier score",
      caption = "The reduction is larger for left-handed pitchers, helping narrow the original model's handedness-related performance gap."
    ) +
    theme_publication() +
    theme(
      panel.grid.major.y = element_line(colour = "#E5E7EB", linewidth = 0.35)
    )

  save_figure(fig, "figure_07_handedness_brier.png", 8.6, 5.8)
} else {
  skip_figure("07", "need week2 probabilities and throwing-hand labels")
}

message("Figure generation complete. Any skipped figures are listed above with the missing inputs.")
