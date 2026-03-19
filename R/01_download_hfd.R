# ============================================================
#  01_download_hfd.R
#  Download TFR and ASFR series from the Human Fertility Database
#  using HMDHFDplus.  Saves raw CSVs to data/raw/.
#
#  Requires: .env with HFD_EMAIL and HFD_PASSWORD
#  Register:  https://www.humanfertility.org
# ============================================================

source("R/00_setup.R")
dotenv::load_dot_env(".env")

hfd_email    <- Sys.getenv("HFD_EMAIL")
hfd_password <- Sys.getenv("HFD_PASSWORD")

if (hfd_email == "" || hfd_password == "") {
  stop("HFD credentials not found. Please fill in .env")
}

# ------------------------------------------------------------
#  Countries to download
#  HFD country codes: https://www.humanfertility.org/Data/Countries
# ------------------------------------------------------------
countries <- c(
  "POL",   # Poland
  "SWE",   # Sweden          -- well-documented rebound
  "FRATNP",# France (total)  -- well-documented rebound
  "JPN",   # Japan           -- prolonged monotone decline
  "ISR",   # Israel          -- high-fertility control
  "USA",   # United States
  "DEUT",  # Germany (total, reunified series)
  "ITA",   # Italy
  "CZE",   # Czech Republic
  "NOR"    # Norway
)

raw_dir <- "data/raw"
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)

# ------------------------------------------------------------
#  Helper: safe download with informative error
#  HMDHFDplus 2.x uses item = "tfr" (lowercase) but the
#  readHFDweb() signature changed — we try both calling
#  conventions for robustness.
# ------------------------------------------------------------
safe_hfd <- function(country, item, ...) {
  tryCatch(
    HMDHFDplus::readHFDweb(
      CNTRY    = country,
      item     = item,
      username = hfd_email,
      password = hfd_password,
      ...
    ),
    error = function(e) {
      warning("Failed to download ", item, " for ", country, ": ",
              conditionMessage(e))
      NULL
    }
  )
}

# HMDHFDplus 2.x changed item names. We probe by trying a known
# test download and falling through a list of candidate names.
message("Detecting correct HFD item names (HMDHFDplus 2.x)...")

probe_item <- function(country, candidates) {
  for (nm in candidates) {
    result <- tryCatch(
      HMDHFDplus::readHFDweb(
        CNTRY    = country,
        item     = nm,
        username = hfd_email,
        password = hfd_password
      ),
      error = function(e) NULL
    )
    if (!is.null(result) && nrow(result) > 0) {
      message("  Item '", nm, "' works for ", country)
      return(nm)
    }
  }
  return(NULL)
}

# Candidate names in order of likelihood for each variable
tfr_candidates  <- c("tfrRR", "tfr", "TFRperiod", "TFR")
asfr_candidates <- c("asfrVH", "asfrRR", "ASFRstand_per", "ASFR")
mab_candidates  <- c("mabRR", "mabVH", "mabVHbo", "MAB")

message("Probing TFR item name against SWE...")
tfr_item <- probe_item("SWE", tfr_candidates)
if (is.null(tfr_item)) {
  message("WARNING: Could not find working TFR item name. Trying 'tfrRR' as default.")
  tfr_item <- "tfrRR"
}

message("Probing ASFR item name against SWE...")
asfr_item <- probe_item("SWE", asfr_candidates)
if (is.null(asfr_item)) asfr_item <- "asfrVH"

message("Probing MAB item name against SWE...")
mab_item <- probe_item("SWE", mab_candidates)
if (is.null(mab_item)) mab_item <- "mabRR"

message("Final item names: TFR='", tfr_item,
        "', ASFR='", asfr_item,
        "', MAB='", mab_item, "'")

# ------------------------------------------------------------
#  1. Period Total Fertility Rate
# ------------------------------------------------------------
message("Downloading TFR (period)...")
tfr_list <- purrr::map(countries, function(cntry) {
  message("  ", cntry)
  df <- safe_hfd(cntry, tfr_item)
  if (!is.null(df)) df$Country <- cntry
  df
})

tfr_all <- dplyr::bind_rows(purrr::compact(tfr_list))
readr::write_csv(tfr_all, file.path(raw_dir, "hfd_tfr.csv"))
message("Saved: data/raw/hfd_tfr.csv  (", nrow(tfr_all), " rows)")

# ------------------------------------------------------------
#  2. Age-Specific Fertility Rates (ASFRperiod)
#     Columns: Year, Age, ASFR  (Age is 12, 13, ..., 55 or 5-year groups)
# ------------------------------------------------------------
message("Downloading ASFR (period, 1-year age groups)...")
asfr_list <- purrr::map(countries, function(cntry) {
  message("  ", cntry)
  df <- safe_hfd(cntry, asfr_item)
  if (!is.null(df)) df$Country <- cntry
  df
})

asfr_all <- dplyr::bind_rows(purrr::compact(asfr_list))
readr::write_csv(asfr_all, file.path(raw_dir, "hfd_asfr.csv"))
message("Saved: data/raw/hfd_asfr.csv  (", nrow(asfr_all), " rows)")

# ------------------------------------------------------------
#  3. Mean Age at First Birth (mabRR)
# ------------------------------------------------------------
message("Downloading mean age at first birth...")
mab_list <- purrr::map(countries, function(cntry) {
  message("  ", cntry)
  df <- safe_hfd(cntry, mab_item)
  if (!is.null(df)) df$Country <- cntry
  df
})

mab_all <- dplyr::bind_rows(purrr::compact(mab_list))
readr::write_csv(mab_all, file.path(raw_dir, "hfd_mab.csv"))
message("Saved: data/raw/hfd_mab.csv  (", nrow(mab_all), " rows)")

message("\nHFD download complete.")
