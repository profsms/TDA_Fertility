# ============================================================
#  05_exploratory_plots.R
#  Produce exploratory TFR trajectory plots for all countries.
#  Saved to output/figures/.
# ============================================================

source("R/00_setup.R")

proc_dir <- "data/processed"
fig_dir  <- "output/figures"
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

tfr <- readr::read_csv(file.path(proc_dir, "tfr_panel.csv"),
                       show_col_types = FALSE)

# ------------------------------------------------------------
#  1. TFR trajectories, all countries
# ------------------------------------------------------------
p_tfr <- ggplot2::ggplot(tfr, ggplot2::aes(x = year, y = tfr,
                                            colour = name)) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_hline(yintercept = 2.1, linetype = "dashed",
                      colour = "grey40", linewidth = 0.5) +
  ggplot2::annotate("text", x = min(tfr$year) + 1, y = 2.15,
                    label = "Replacement level (2.1)",
                    hjust = 0, size = 3, colour = "grey40") +
  ggplot2::scale_colour_brewer(palette = "Paired", name = NULL) +
  ggplot2::labs(
    title    = "Total Fertility Rate trajectories",
    subtitle = "Selected countries, all available years",
    x        = "Year",
    y        = "TFR (children per woman)",
    caption  = "Sources: Human Fertility Database, OECD"
  ) +
  ggplot2::theme_bw(base_size = 12) +
  ggplot2::theme(legend.position = "bottom")

ggplot2::ggsave(
  file.path(fig_dir, "tfr_trajectories.pdf"),
  p_tfr, width = 10, height = 6
)
ggplot2::ggsave(
  file.path(fig_dir, "tfr_trajectories.png"),
  p_tfr, width = 10, height = 6, dpi = 150
)
message("Saved: tfr_trajectories.pdf / .png")

# ------------------------------------------------------------
#  2. Small-multiple panels per country
# ------------------------------------------------------------
p_facet <- ggplot2::ggplot(tfr, ggplot2::aes(x = year, y = tfr)) +
  ggplot2::geom_line(colour = "steelblue", linewidth = 0.7) +
  ggplot2::geom_hline(yintercept = 2.1, linetype = "dashed",
                      colour = "firebrick", linewidth = 0.4) +
  ggplot2::facet_wrap(~ name, scales = "free_y") +
  ggplot2::labs(
    title   = "TFR by country (free y-axis)",
    x       = "Year", y = "TFR",
    caption = "Sources: HFD, OECD"
  ) +
  ggplot2::theme_bw(base_size = 10)

ggplot2::ggsave(
  file.path(fig_dir, "tfr_facets.pdf"),
  p_facet, width = 14, height = 10
)
message("Saved: tfr_facets.pdf")

# ------------------------------------------------------------
#  3. First differences (annual changes) -- useful visual
#     check for cyclical vs. monotone regimes
# ------------------------------------------------------------
tfr_diff <- tfr |>
  dplyr::group_by(iso3, name) |>
  dplyr::arrange(year) |>
  dplyr::mutate(d_tfr = tfr - dplyr::lag(tfr)) |>
  dplyr::ungroup() |>
  tidyr::drop_na(d_tfr)

p_diff <- ggplot2::ggplot(tfr_diff,
                          ggplot2::aes(x = year, y = d_tfr)) +
  ggplot2::geom_col(
    ggplot2::aes(fill = d_tfr > 0),
    width = 0.8, show.legend = FALSE
  ) +
  ggplot2::scale_fill_manual(values = c("TRUE" = "#2166ac",
                                        "FALSE" = "#d6604d")) +
  ggplot2::geom_hline(yintercept = 0, linewidth = 0.3) +
  ggplot2::facet_wrap(~ name, scales = "free_y") +
  ggplot2::labs(
    title   = "Annual TFR changes (first differences)",
    subtitle = "Blue = increase, Red = decrease",
    x = "Year", y = "dTFR",
    caption = "Sources: HFD, OECD"
  ) +
  ggplot2::theme_bw(base_size = 10)

ggplot2::ggsave(
  file.path(fig_dir, "tfr_first_differences.pdf"),
  p_diff, width = 14, height = 10
)
message("Saved: tfr_first_differences.pdf")

message("\nExploratory plots complete.")
