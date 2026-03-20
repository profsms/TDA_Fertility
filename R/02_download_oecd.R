# ============================================================
#  02_download_oecd.R
#  Download contextual variables from OECD and World Bank.
#  OECD new API requires Accept + User-Agent headers.
# ============================================================

source("R/00_setup.R")

raw_dir <- "data/raw"
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)

oecd_countries <- c("POL","SWE","FRA","JPN","ISR","USA","DEU","ITA","CZE","NOR","KOR")
country_filter <- paste(oecd_countries, collapse = "+")

# ------------------------------------------------------------
#  Generic OECD new-API fetcher (sdmx.oecd.org)
# ------------------------------------------------------------
fetch_oecd <- function(dataset, filter_str, agency, start_period = "1960") {
  url <- paste0(
    "https://sdmx.oecd.org/public/rest/data/",
    agency, ",", dataset, "/", filter_str,
    "?startPeriod=", start_period, "&format=csvfilewithlabels"
  )
  message("  GET ", url)
  tmp  <- tempfile(fileext = ".csv")
  resp <- tryCatch(
    httr::GET(
      url,
      httr::add_headers(
        "Accept"     = "text/csv",
        "User-Agent" = "Mozilla/5.0 (R httr)"
      ),
      httr::write_disk(tmp, overwrite = TRUE),
      httr::timeout(120)
    ),
    error = function(e) { warning("HTTP error: ", e$message); NULL }
  )
  code <- if (is.null(resp)) NA else httr::status_code(resp)
  if (is.na(code) || code != 200) {
    warning("OECD fetch failed for ", dataset, " (HTTP ", code, ")")
    return(NULL)
  }
  tryCatch(
    readr::read_csv(tmp, show_col_types = FALSE),
    error = function(e) { warning("CSV parse error: ", e$message); NULL }
  )
}

# ------------------------------------------------------------
#  World Bank fetcher (json v2 API)
# ------------------------------------------------------------
fetch_worldbank <- function(iso2_codes, indicator, label) {
  countries <- paste(iso2_codes, collapse = ";")
  url <- paste0(
    "https://api.worldbank.org/v2/country/", countries,
    "/indicator/", indicator,
    "?format=json&per_page=2000&mrv=70"
  )
  message("  GET ", url)
  resp <- tryCatch(
    httr::GET(url, httr::timeout(60),
              httr::add_headers("User-Agent" = "Mozilla/5.0 (R httr)")),
    error = function(e) { warning("WB error: ", e$message); NULL }
  )
  if (is.null(resp) || httr::status_code(resp) != 200) {
    warning("World Bank fetch failed for ", indicator,
            " (HTTP ", if(is.null(resp)) "NA" else httr::status_code(resp), ")")
    return(NULL)
  }
  txt    <- httr::content(resp, "text", encoding = "UTF-8")
  parsed <- tryCatch(jsonlite::fromJSON(txt, flatten = TRUE),
                     error = function(e) NULL)
  if (is.null(parsed) || length(parsed) < 2 || !is.data.frame(parsed[[2]])) {
    warning("World Bank response parse failed for ", indicator)
    return(NULL)
  }
  df <- parsed[[2]]
  # column names vary slightly by WB API version
  iso_col  <- intersect(c("countryiso3code","country.id"), names(df))[1]
  val_col  <- intersect(c("value","obs_value"),            names(df))[1]
  date_col <- intersect(c("date","time"),                  names(df))[1]
  if (any(is.na(c(iso_col, val_col, date_col)))) {
    warning("Cannot identify WB columns. Got: ", paste(names(df), collapse=", "))
    return(NULL)
  }
  df |>
    dplyr::select(iso3 = !!iso_col, year = !!date_col, !!label := !!val_col) |>
    dplyr::mutate(year = as.integer(year),
                  !!label := as.numeric(.data[[label]])) |>
    tidyr::drop_na()
}

wb_iso2 <- c("PL","SE","FR","JP","IL","US","DE","IT","CZ","NO","KR")

# ------------------------------------------------------------
#  1. TFR (Korea)
# ------------------------------------------------------------
message("Downloading OECD TFR...")
tfr_raw <- fetch_oecd(
  dataset    = "DF_FERT_RATE",
  agency     = "OECD.ELS.FAM",
  filter_str = paste0(country_filter, ".FERTILITY_RATE_TOTAL.")
)
if (!is.null(tfr_raw)) {
  readr::write_csv(tfr_raw, file.path(raw_dir, "oecd_tfr.csv"))
  message("Saved: data/raw/oecd_tfr.csv  (", nrow(tfr_raw), " rows)")
} else {
  message("OECD TFR failed -- Korea will be missing from panel.")
}

# ------------------------------------------------------------
#  2. GDP per capita PPP (World Bank NY.GDP.PCAP.PP.KD)
# ------------------------------------------------------------
message("Downloading GDP per capita (World Bank)...")
gdp <- fetch_worldbank(wb_iso2, "NY.GDP.PCAP.PP.KD", "gdp_pc_ppp")
if (!is.null(gdp)) {
  readr::write_csv(gdp, file.path(raw_dir, "oecd_gdp_pc.csv"))
  message("Saved: data/raw/oecd_gdp_pc.csv  (", nrow(gdp), " rows)")
} else {
  message("GDP download failed.")
}

# ------------------------------------------------------------
#  3. Female LFPR (World Bank SL.TLF.ACTI.FE.ZS)
# ------------------------------------------------------------
message("Downloading female LFPR (World Bank)...")
flfpr <- fetch_worldbank(wb_iso2, "SL.TLF.ACTI.FE.ZS", "female_lfpr")
if (!is.null(flfpr)) {
  readr::write_csv(flfpr, file.path(raw_dir, "oecd_flfpr.csv"))
  message("Saved: data/raw/oecd_flfpr.csv  (", nrow(flfpr), " rows)")
} else {
  message("Female LFPR download failed.")
}

# ------------------------------------------------------------
#  4. Family policy expenditure -- OECD SOCX
# ------------------------------------------------------------
message("Downloading family policy expenditure (OECD)...")
socx_raw <- fetch_oecd(
  dataset    = "DF_SOCX_SUMM",
  agency     = "OECD.ELS.SPD",
  filter_str = paste0(country_filter, ".FAM.PCTGDP._T.A.")
)
if (!is.null(socx_raw)) {
  readr::write_csv(socx_raw, file.path(raw_dir, "oecd_family_expenditure.csv"))
  message("Saved: data/raw/oecd_family_expenditure.csv")
} else {
  message("Family expenditure download failed.")
}

message("\nOECD download complete.")
