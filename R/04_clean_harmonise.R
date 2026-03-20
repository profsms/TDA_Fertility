# ============================================================
#  04_clean_harmonise.R
#  Read raw downloads, harmonise column names, merge into
#  clean panel datasets, and save to data/processed/.
# ============================================================

source("R/00_setup.R")

raw_dir  <- "data/raw"
proc_dir <- "data/processed"
dir.create(proc_dir, showWarnings = FALSE, recursive = TRUE)

# Country metadata: HFD code -> ISO-3 -> display name
country_meta <- tibble::tribble(
  ~hfd_code,  ~iso3, ~iso2, ~name,
  "POL",      "POL", "PL",  "Poland",
  "SWE",      "SWE", "SE",  "Sweden",
  "FRATNP",   "FRA", "FR",  "France",
  "JPN",      "JPN", "JP",  "Japan",
  "ISR",      "ISR", "IL",  "Israel",
  "USA",      "USA", "US",  "United States",
  "DEUT",     "DEU", "DE",  "Germany",
  "ITA",      "ITA", "IT",  "Italy",
  "CZE",      "CZE", "CZ",  "Czech Republic",
  "NOR",      "NOR", "NO",  "Norway",
  "KOR",      "KOR", "KR",  "South Korea"   # OECD only
)

# ============================================================
#  1. TFR panel
# ============================================================
message("Building TFR panel...")

# Helper: safely read a CSV and return NULL if empty or missing
safe_read_csv <- function(path, ...) {
  tryCatch({
    df <- readr::read_csv(path, show_col_types = FALSE, ...)
    if (nrow(df) == 0) { warning(path, " is empty"); return(NULL) }
    df
  }, error = function(e) { warning(path, " could not be read: ", conditionMessage(e)); NULL })
}

# -- HFD TFR
hfd_tfr_raw <- safe_read_csv(file.path(raw_dir, "hfd_tfr.csv"))

hfd_tfr <- if (!is.null(hfd_tfr_raw)) {
  df <- dplyr::rename_with(hfd_tfr_raw, tolower)
  # Detect column names defensively
  cols <- names(df)
  tfr_col  <- dplyr::coalesce(
    if ("tfr"  %in% cols) "tfr"  else NA_character_,
    if ("TFR"  %in% cols) "TFR"  else NA_character_
  )
  year_col <- dplyr::coalesce(
    if ("year" %in% cols) "year" else NA_character_,
    if ("Year" %in% cols) "Year" else NA_character_
  )
  if (is.na(tfr_col) || is.na(year_col)) {
    message("HFD TFR columns found: ", paste(cols, collapse = ", "))
    message("Could not identify year/tfr columns -- skipping HFD TFR")
    NULL
  } else {
    df |>
      dplyr::rename(year = !!year_col, tfr = !!tfr_col) |>
      dplyr::select(year, tfr, country) |>
      dplyr::left_join(country_meta |> dplyr::select(hfd_code, iso3, name),
                       by = c("country" = "hfd_code")) |>
      dplyr::mutate(source = "HFD") |>
      dplyr::select(iso3, name, year, tfr, source)
  }
} else {
  message("HFD TFR not available -- will use Eurostat as primary source.")
  NULL
}

# -- Eurostat national TFR as fallback (downloaded successfully)
eurostat_tfr_raw <- safe_read_csv(file.path(raw_dir, "eurostat_national_tfr.csv"))

eurostat_tfr <- if (!is.null(eurostat_tfr_raw)) {
  eurostat_iso2_map <- c(
    "PL" = "POL", "SE" = "SWE", "FR" = "FRA",
    "DE" = "DEU", "IT" = "ITA", "CZ" = "CZE", "NO" = "NOR"
  )
  df <- dplyr::rename_with(eurostat_tfr_raw, tolower)
  message("Eurostat TFR columns: ", paste(names(df), collapse = ", "))

  # time column can be "time" or "time_period" depending on eurostat pkg version
  val_col  <- intersect(c("values","value"),     names(df))[1]
  time_col <- intersect(c("time","time_period"), names(df))[1]
  geo_col  <- intersect(c("geo","geo\\time"),    names(df))[1]

  if (is.na(val_col) || is.na(time_col) || is.na(geo_col)) {
    message("Cannot parse Eurostat TFR -- skipping")
    NULL
  } else {
    df |>
      dplyr::rename(value = !!val_col, time = !!time_col, geo = !!geo_col) |>
      dplyr::mutate(
        year = as.integer(time),
        tfr  = as.numeric(value),
        iso3 = dplyr::recode(as.character(geo), !!!eurostat_iso2_map)
      ) |>
      dplyr::filter(iso3 %in% country_meta$iso3) |>
      dplyr::left_join(country_meta |> dplyr::select(iso3, name), by = "iso3") |>
      dplyr::mutate(source = "Eurostat") |>
      dplyr::select(iso3, name, year, tfr, source) |>
      tidyr::drop_na(tfr)
  }
} else NULL

# -- OECD TFR (for Korea)
oecd_tfr_raw <- safe_read_csv(file.path(raw_dir, "oecd_tfr.csv"))

oecd_tfr <- if (!is.null(oecd_tfr_raw)) {
  df_o <- dplyr::rename_with(oecd_tfr_raw, tolower)
  message("OECD TFR columns: ", paste(names(df_o), collapse = ", "))
  # New API uses "ref_area" and "obs_value" and "time_period";
  # old API used "location", "obsvalue", "time"
  loc_col  <- intersect(c("ref_area","location","country"), names(df_o))[1]
  val_col  <- intersect(c("obs_value","obsvalue","value"),  names(df_o))[1]
  time_col <- intersect(c("time_period","time","year"),     names(df_o))[1]

  if (any(is.na(c(loc_col, val_col, time_col)))) {
    message("Cannot parse OECD TFR columns -- skipping")
    NULL
  } else {
    df_o |>
      dplyr::mutate(
        iso3 = as.character(.data[[loc_col]]),
        year = as.integer(.data[[time_col]]),
        tfr  = as.numeric(.data[[val_col]])
      ) |>
      dplyr::filter(iso3 %in% country_meta$iso3) |>
      dplyr::left_join(country_meta |> dplyr::select(iso3, name), by = "iso3") |>
      dplyr::mutate(source = "OECD") |>
      dplyr::select(iso3, name, year, tfr, source) |>
      tidyr::drop_na(tfr)
  }
} else NULL

# Combine all sources; priority: HFD > Eurostat > OECD
sources_available <- purrr::compact(list(hfd_tfr, eurostat_tfr, oecd_tfr))

if (length(sources_available) == 0) {
  stop("No TFR data available from any source (HFD, Eurostat, OECD). ",
       "Check your credentials and internet connection.")
}

tfr_panel <- dplyr::bind_rows(sources_available) |>
  dplyr::mutate(source_priority = dplyr::case_when(
    source == "HFD"      ~ 1L,
    source == "Eurostat" ~ 2L,
    source == "OECD"     ~ 3L,
    TRUE                 ~ 4L
  )) |>
  dplyr::group_by(iso3, year) |>
  dplyr::arrange(source_priority, .by_group = TRUE) |>
  dplyr::slice(1) |>
  dplyr::ungroup() |>
  dplyr::select(-source_priority) |>
  tidyr::drop_na(iso3, tfr) |>
  dplyr::arrange(iso3, year)

readr::write_csv(tfr_panel, file.path(proc_dir, "tfr_panel.csv"))
message("Saved: data/processed/tfr_panel.csv  (", nrow(tfr_panel), " rows, ",
        dplyr::n_distinct(tfr_panel$iso3), " countries)")

# ============================================================
#  2. ASFR panel (5-year age groups, harmonised)
# ============================================================
message("Building ASFR panel...")

asfr_raw <- safe_read_csv(file.path(raw_dir, "hfd_asfr.csv"))

if (!is.null(asfr_raw)) {
  df_asfr <- dplyr::rename_with(asfr_raw, tolower)
  cols_a   <- names(df_asfr)
  message("ASFR columns found: ", paste(cols_a, collapse = ", "))

  # Detect ASFR value column: could be "asfr", "ASFR", "asfr1", etc.
  asfr_val_col <- cols_a[grepl("^asfr", cols_a, ignore.case = TRUE)][1]
  age_col      <- cols_a[grepl("^age",  cols_a, ignore.case = TRUE)][1]
  cntry_col_a  <- cols_a[grepl("^country", cols_a, ignore.case = TRUE)][1]
  # HFD asfrVH has a "cohort" column not "year" -- accept either
  yr_col_a     <- intersect(c("year","cohort","period"), cols_a)[1]

  if (any(is.na(c(asfr_val_col, age_col, yr_col_a, cntry_col_a)))) {
    message("Cannot identify required ASFR columns -- skipping ASFR panel")
    message("  Available columns: ", paste(cols_a, collapse = ", "))
  } else {
    message("  ASFR using: year=", yr_col_a, " age=", age_col,
            " asfr=", asfr_val_col, " country=", cntry_col_a)
    asfr_panel <- df_asfr |>
      dplyr::rename(asfr = !!asfr_val_col, age = !!age_col,
                    year = !!yr_col_a,     country = !!cntry_col_a) |>
      dplyr::filter(age >= 15, age <= 49) |>
      dplyr::mutate(
        age_group = cut(age, breaks = c(14, 19, 24, 29, 34, 39, 44, 49),
                        labels = c("15-19","20-24","25-29","30-34",
                                   "35-39","40-44","45-49"),
                        include.lowest = TRUE)
      ) |>
      dplyr::group_by(country, year, age_group) |>
      dplyr::summarise(asfr = mean(asfr, na.rm = TRUE), .groups = "drop") |>
      dplyr::left_join(country_meta |> dplyr::select(hfd_code, iso3, name),
                       by = c("country" = "hfd_code")) |>
      tidyr::drop_na(iso3) |>
      dplyr::select(iso3, name, year, age_group, asfr)

    readr::write_csv(asfr_panel, file.path(proc_dir, "asfr_panel.csv"))
    message("Saved: data/processed/asfr_panel.csv  (", nrow(asfr_panel), " rows)")
  }
} else {
  message("hfd_asfr.csv not found -- skipping ASFR panel")
}

# ============================================================
#  3. Mean age at first birth
# ============================================================
message("Building MAB panel...")

mab_raw <- tryCatch(
  readr::read_csv(file.path(raw_dir, "hfd_mab.csv"), show_col_types = FALSE),
  error = function(e) { warning("hfd_mab.csv not found"); NULL }
)

if (!is.null(mab_raw)) {
  mab_panel <- mab_raw |>
    dplyr::rename_with(tolower) |>
    dplyr::left_join(country_meta |> dplyr::select(hfd_code, iso3, name),
                     by = c("country" = "hfd_code")) |>
    dplyr::select(iso3, name, year, mab = mab) |>
    dplyr::arrange(iso3, year)

  readr::write_csv(mab_panel, file.path(proc_dir, "mab_panel.csv"))
  message("Saved: data/processed/mab_panel.csv")
}

# ============================================================
#  4. Contextual variables (OECD)
# ============================================================
message("Building contextual variables panel...")

# Flexible reader: handles both old SDMX column names and new WB/OECD formats
read_context_var <- function(file, value_col_new) {
  tryCatch({
    df <- readr::read_csv(file, show_col_types = FALSE) |>
      dplyr::rename_with(tolower)
    # Detect iso3 column
    iso_col  <- intersect(c("iso3","location","ref_area","countryiso3code"), names(df))[1]
    # Detect year column
    yr_col   <- intersect(c("year","time","time_period","date"),             names(df))[1]
    # Detect value column
    val_col  <- intersect(c(value_col_new,"obs_value","obsvalue","value",
                             "gdp_pc_ppp","female_lfpr","family_exp_pct_gdp"),
                          names(df))[1]
    if (any(is.na(c(iso_col, yr_col, val_col)))) {
      warning(file, ": cannot identify columns. Got: ", paste(names(df), collapse=", "))
      return(NULL)
    }
    df |>
      dplyr::mutate(
        iso3           = as.character(.data[[iso_col]]),
        year           = as.integer(.data[[yr_col]]),
        !!value_col_new := as.numeric(.data[[val_col]])
      ) |>
      dplyr::select(iso3, year, !!value_col_new) |>
      tidyr::drop_na()
  }, error = function(e) { warning(file, " not found or unreadable: ", e$message); NULL })
}

gdp   <- read_context_var(file.path(raw_dir, "oecd_gdp_pc.csv"),           "gdp_pc_ppp")
flfpr <- read_context_var(file.path(raw_dir, "oecd_flfpr.csv"),            "female_lfpr")
socx  <- read_context_var(file.path(raw_dir, "oecd_family_expenditure.csv"),"family_exp_pct_gdp")

available_context <- purrr::compact(list(gdp, flfpr, socx))

if (length(available_context) == 0) {
  message("No contextual variables available -- saving empty context panel.")
  context_panel <- tibble::tibble(iso3 = character(), year = integer(),
                                  gdp_pc_ppp = numeric(), female_lfpr = numeric(),
                                  family_exp_pct_gdp = numeric(), name = character())
} else {
  context_panel <- purrr::reduce(
    available_context,
    dplyr::full_join, by = c("iso3", "year")
  ) |>
    dplyr::left_join(country_meta |> dplyr::select(iso3, name), by = "iso3") |>
    dplyr::arrange(iso3, year)
}

readr::write_csv(context_panel, file.path(proc_dir, "context_panel.csv"))
message("Saved: data/processed/context_panel.csv  (", nrow(context_panel), " rows)")

# ============================================================
#  5. Quick summary
# ============================================================
message("\n=== Data coverage summary (TFR panel) ===")
tfr_panel |>
  dplyr::group_by(iso3, name) |>
  dplyr::summarise(
    years    = dplyr::n(),
    year_min = min(year),
    year_max = max(year),
    .groups  = "drop"
  ) |>
  print(n = Inf)

message("\nHarmonisation complete.")
