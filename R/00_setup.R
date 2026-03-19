# ============================================================
#  00_setup.R
#  Install and attach all packages needed for the WTFE project.
#  Run this once before any other script.
# ============================================================

required_packages <- c(
  # credentials & environment
  "dotenv",
  # data fetching
  "HMDHFDplus",   # HFD / HMD authenticated download
  "OECD",         # OECD SDMX API
  "eurostat",     # Eurostat REST API
  "httr",         # generic HTTP (fallback)
  "jsonlite",     # JSON parsing
  # data wrangling
  "dplyr",
  "tidyr",
  "purrr",
  "readr",
  "stringr",
  "lubridate",
  # output
  "ggplot2",
  "scales",
  "writexl"
)

missing <- required_packages[!(required_packages %in% installed.packages()[, "Package"])]
if (length(missing) > 0) {
  message("Installing missing packages: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = "https://cloud.r-project.org")
}

invisible(lapply(required_packages, library, character.only = TRUE))
message("All packages loaded successfully.")
