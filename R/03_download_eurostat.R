# ============================================================
#  03_download_eurostat.R
#  Download NUTS-2 age-specific fertility rates from Eurostat.
#  Dataset: demo_r_find2
#  No authentication required.
# ============================================================

source("R/00_setup.R")

raw_dir <- "data/raw"
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)

# ------------------------------------------------------------
#  NUTS-2 ASFR  (demo_r_find2)
#  Age groups: Y_LT15, Y15-19, Y20-24, Y25-29, Y30-34,
#              Y35-39, Y40-44, Y45-49, Y_GE50, TOTAL
#  Coverage: EU countries, ~2000-present (patchy before 2010)
# ------------------------------------------------------------
message("Downloading Eurostat NUTS-2 ASFR (demo_r_find2)...")

nuts2_asfr <- tryCatch({
  eurostat::get_eurostat(
    "demo_r_find2",
    time_format = "num",
    cache       = FALSE
  )
}, error = function(e) {
  warning("Eurostat download failed: ", conditionMessage(e))
  NULL
})

if (!is.null(nuts2_asfr)) {
  # Filter to NUTS-2 level (code length == 4: 2-letter country + 2 digits)
  # and to countries in our panel
  panel_iso2 <- c("PL", "SE", "FR", "DE", "IT", "CZ", "NO", "IL", "US")

  nuts2_asfr_filtered <- nuts2_asfr |>
    dplyr::filter(
      nchar(as.character(geo)) == 4,
      substr(as.character(geo), 1, 2) %in% panel_iso2
    )

  readr::write_csv(nuts2_asfr_filtered, file.path(raw_dir, "eurostat_nuts2_asfr.csv"))
  message("Saved: data/raw/eurostat_nuts2_asfr.csv  (",
          nrow(nuts2_asfr_filtered), " rows)")
} else {
  message("Skipping Eurostat NUTS-2 (download failed).")
}

# ------------------------------------------------------------
#  National TFR from Eurostat as cross-check (demo_find)
# ------------------------------------------------------------
message("Downloading Eurostat national TFR (demo_find)...")

nat_tfr <- tryCatch({
  eurostat::get_eurostat("demo_find", time_format = "num", cache = FALSE)
}, error = function(e) {
  warning("Eurostat national TFR download failed: ", conditionMessage(e))
  NULL
})

if (!is.null(nat_tfr)) {
  nat_tfr_filtered <- nat_tfr |>
    dplyr::filter(
      indic_de == "TOTFERRT",
      geo %in% c("PL", "SE", "FR", "DE", "IT", "CZ", "NO")
    )
  readr::write_csv(nat_tfr_filtered, file.path(raw_dir, "eurostat_national_tfr.csv"))
  message("Saved: data/raw/eurostat_national_tfr.csv")
}

message("\nEurostat download complete.")
