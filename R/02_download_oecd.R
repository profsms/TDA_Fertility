# ============================================================
#  02_download_oecd.R
#  Download TFR for South Korea (not in HFD) and contextual
#  variables (GDP per capita, female LFPR, family policy
#  expenditure) from the OECD API.
#  No authentication required.
# ============================================================

source("R/00_setup.R")

raw_dir <- "data/raw"
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)

# OECD country codes for our panel (ISO-3 / OECD codes)
oecd_countries <- c(
  "POL", "SWE", "FRA", "JPN", "ISR",
  "USA", "DEU", "ITA", "CZE", "NOR", "KOR"
)

# ------------------------------------------------------------
#  Helper: OECD dataset download with error handling
# ------------------------------------------------------------
safe_oecd <- function(dataset, filter_list, ...) {
  tryCatch(
    OECD::get_dataset(dataset, filter = filter_list, ...),
    error = function(e) {
      warning("OECD download failed for ", dataset, ": ", conditionMessage(e))
      NULL
    }
  )
}

# ------------------------------------------------------------
#  1. TFR  (dataset: "SF_FERT")
#     Variable: FERTILITY_RATE_TOTAL
# ------------------------------------------------------------
message("Downloading OECD TFR (SF_FERT)...")
tfr_oecd <- safe_oecd(
  "SF_FERT",
  filter_list = list(
    LOCATION  = oecd_countries,
    INDICATOR = "FERTILITY_RATE_TOTAL"
  )
)

if (!is.null(tfr_oecd)) {
  readr::write_csv(tfr_oecd, file.path(raw_dir, "oecd_tfr.csv"))
  message("Saved: data/raw/oecd_tfr.csv  (", nrow(tfr_oecd), " rows)")
}

# ------------------------------------------------------------
#  2. GDP per capita, PPP (dataset: "SNA_TABLE1")
#     We use the simpler ALFS / National Accounts shortcut via
#     the "MEI" (Main Economic Indicators) dataset
# ------------------------------------------------------------
message("Downloading GDP per capita (MEI)...")
gdp <- safe_oecd(
  "PDB_LV",
  filter_list = list(
    LOCATION  = oecd_countries,
    SUBJECT   = "T_GDPPOP",     # GDP per capita, constant USD PPP
    MEASURE   = "CPC"
  )
)

if (!is.null(gdp)) {
  readr::write_csv(gdp, file.path(raw_dir, "oecd_gdp_pc.csv"))
  message("Saved: data/raw/oecd_gdp_pc.csv")
}

# ------------------------------------------------------------
#  3. Female labour force participation rate (OECD ALFS)
# ------------------------------------------------------------
message("Downloading female LFPR (ALFS_SUMTAB)...")
flfpr <- safe_oecd(
  "ALFS_SUMTAB",
  filter_list = list(
    LOCATION = oecd_countries,
    SUBJECT  = "LFPR_F"          # Female LFPR, % of female pop 15-64
  )
)

if (!is.null(flfpr)) {
  readr::write_csv(flfpr, file.path(raw_dir, "oecd_flfpr.csv"))
  message("Saved: data/raw/oecd_flfpr.csv")
}

# ------------------------------------------------------------
#  4. Public spending on family benefits (SOCX)
#     % of GDP
# ------------------------------------------------------------
message("Downloading family policy expenditure (SOCX)...")
socx <- safe_oecd(
  "SOCX_AGG",
  filter_list = list(
    LOCATION = oecd_countries,
    DOMAIN   = "FAMILY",
    UNIT     = "PCGDP"           # % of GDP
  )
)

if (!is.null(socx)) {
  readr::write_csv(socx, file.path(raw_dir, "oecd_family_expenditure.csv"))
  message("Saved: data/raw/oecd_family_expenditure.csv")
}

message("\nOECD download complete.")
