# ============================================================
#  06_contextual_correlations.R
#  Merge WTFE baseline results (from Julia) with contextual
#  variables (GDP, female LFPR, family expenditure) and
#  produce correlation tables and scatter plots.
# ============================================================

source("R/00_setup.R")

tbl_dir  <- "output/tables"
fig_dir  <- "output/figures"
proc_dir <- "data/processed"
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

# ------------------------------------------------------------
#  Load data
# ------------------------------------------------------------
wtfe_base <- readr::read_csv(file.path(tbl_dir, "wtfe_baseline.csv"),
                              show_col_types = FALSE)
context   <- readr::read_csv(file.path(proc_dir, "context_panel.csv"),
                              show_col_types = FALSE)
tfr       <- readr::read_csv(file.path(proc_dir, "tfr_panel.csv"),
                              show_col_types = FALSE)

# Merge
panel <- wtfe_base |>
  dplyr::left_join(context, by = c("iso3", "year")) |>
  dplyr::left_join(tfr |> dplyr::select(iso3, year, tfr),
                   by = c("iso3", "year")) |>
  tidyr::drop_na(wtfe)

# ------------------------------------------------------------
#  1. Correlation table: WTFE vs. contextual variables
# ------------------------------------------------------------
vars <- c("tfr", "gdp_pc_ppp", "female_lfpr", "family_exp_pct_gdp")
vars_present <- vars[vars %in% names(panel)]

cor_results <- purrr::map_dfr(vars_present, function(v) {
  d <- tidyr::drop_na(panel, dplyr::all_of(v))
  ct <- cor.test(d$wtfe, d[[v]], method = "pearson")
  tibble::tibble(
    variable   = v,
    n          = ct$parameter + 2L,
    pearson_r  = round(ct$estimate, 3),
    p_value    = round(ct$p.value, 4),
    ci_low     = round(ct$conf.int[1], 3),
    ci_high    = round(ct$conf.int[2], 3)
  )
})

print(cor_results)
readr::write_csv(cor_results,
                 file.path(tbl_dir, "wtfe_contextual_correlations.csv"))
message("Saved: output/tables/wtfe_contextual_correlations.csv")

# Within-country (demeaned) correlations
cor_within <- panel |>
  dplyr::group_by(iso3) |>
  dplyr::mutate(dplyr::across(
    dplyr::all_of(c("wtfe", vars_present)),
    ~ . - mean(., na.rm = TRUE)
  )) |>
  dplyr::ungroup()

cor_within_results <- purrr::map_dfr(vars_present, function(v) {
  d <- tidyr::drop_na(cor_within, dplyr::all_of(v))
  ct <- cor.test(d$wtfe, d[[v]], method = "pearson")
  tibble::tibble(
    variable  = v,
    n         = ct$parameter + 2L,
    pearson_r = round(ct$estimate, 3),
    p_value   = round(ct$p.value, 4)
  )
})

message("\nWithin-country (demeaned) correlations:")
print(cor_within_results)
readr::write_csv(cor_within_results,
                 file.path(tbl_dir, "wtfe_within_correlations.csv"))

# ------------------------------------------------------------
#  2. Scatter plots: WTFE vs. each contextual variable
# ------------------------------------------------------------
scatter_vars <- vars_present[vars_present != "tfr"]

plots <- purrr::map(scatter_vars, function(v) {
  d <- tidyr::drop_na(panel, dplyr::all_of(v))
  label_map <- c(
    gdp_pc_ppp            = "GDP per capita (PPP, USD)",
    female_lfpr           = "Female labour force participation (%)",
    family_exp_pct_gdp    = "Family policy expenditure (% GDP)"
  )
  x_label <- label_map[[v]]

  ggplot2::ggplot(d, ggplot2::aes(x = .data[[v]], y = wtfe,
                                   colour = name)) +
    ggplot2::geom_point(alpha = 0.5, size = 1.5) +
    ggplot2::geom_smooth(method = "lm", se = TRUE,
                         colour = "grey30", linewidth = 0.8) +
    ggplot2::scale_colour_brewer(palette = "Paired", name = NULL) +
    ggplot2::labs(x = x_label, y = "WTFE",
                  title = paste("WTFE vs.", x_label)) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(legend.position = "bottom")
})

purrr::walk2(plots, scatter_vars, function(p, v) {
  fname <- file.path(fig_dir, paste0("scatter_wtfe_", v, ".pdf"))
  ggplot2::ggsave(fname, p, width = 7, height = 5)
  message("Saved: ", fname)
})

# ------------------------------------------------------------
#  3. WTFE + TFR dual-axis time series per country (R version)
# ------------------------------------------------------------
countries <- unique(panel$iso3)

purrr::walk(countries, function(cntry) {
  sub <- dplyr::filter(panel, iso3 == cntry)
  if (nrow(sub) < 5) return(invisible(NULL))
  cname <- sub$name[1]

  p <- ggplot2::ggplot(sub, ggplot2::aes(x = year)) +
    ggplot2::geom_line(ggplot2::aes(y = wtfe, colour = "WTFE"),
                       lwd = 1) +
    ggplot2::geom_line(ggplot2::aes(y = tfr / max(tfr, na.rm=TRUE),
                                     colour = "TFR (normalised)"),
                       lwd = 1, linetype = "dashed") +
    ggplot2::scale_colour_manual(
      values = c("WTFE" = "steelblue",
                 "TFR (normalised)" = "firebrick"),
      name = NULL
    ) +
    ggplot2::labs(title = cname, x = "Year", y = "Value") +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(legend.position = "top")

  fname <- file.path(fig_dir,
                     paste0("wtfe_tfr_", tolower(cntry), ".pdf"))
  ggplot2::ggsave(fname, p, width = 8, height = 4)
})
message("Saved country dual-axis plots.")

message("\nContextual correlation analysis complete.")
