# TDA Fertility -- Weighted Topological Fertility Entropy (WTFE)

> **Replication code for:**
> *A Topological Indicator for Fertility Regime Dynamics*
> Stanislaw M. S. Halkiewicz, Kornelia Kozaczewska, Jean-Marc Freyermuth
> *(working paper, 2025)*

---

## What is this?

Standard demographic measures like the Total Fertility Rate (TFR) capture
*levels* but are blind to *dynamical regime* -- whether a country's fertility
trajectory still has rebound capacity or has collapsed into monotone decline.

This project proposes the **Weighted Topological Fertility Entropy (WTFE)**,
a single scalar indicator rooted in Topological Data Analysis (TDA) that
quantifies the cyclic structure of fertility trajectories via persistent
homology. It is designed as an early-warning signal: WTFE should deteriorate
*before* TFR levels themselves reach alarming thresholds.

The indicator is defined as:

```
WTFE(t) = H(t) * l*(t)
```

where `H(t)` is the persistent entropy of the H1 persistence diagram and
`l*(t)` is the maximal persistence, both computed on the delay-embedded TFR
point cloud in a rolling window normalised to unit diameter.

---

## Requirements

| Tool  | Version | Notes |
|-------|---------|-------|
| R     | >= 4.2  | packages installed automatically by `R/00_setup.R` |
| Julia | >= 1.9  | packages installed by `julia/01_install_deps.jl` |
| Git   | any     | for cloning |

Key R packages: `HMDHFDplus`, `OECD`, `eurostat`, `dplyr`, `ggplot2`

Key Julia packages: `Ripserer.jl`, `PersistenceDiagrams.jl`, `Distances.jl`

---

## Setup

### 1. Clone the repository
```bash
git clone https://github.com/yourusername/TDA_Fertility.git
cd TDA_Fertility
```

### 2. Create your credentials file
```bash
cp .env.example .env
```
Then open `.env` and fill in your HFD email and password.
Register for free at https://www.humanfertility.org.
`.env` is git-ignored and will never be committed.

### 3. Install R packages (once)
```r
source("R/00_setup.R")
```

### 4. Install Julia packages (once)
```bash
julia --project=julia julia/01_install_deps.jl
```

---

## Running the pipeline

### Automated (recommended)

**Windows (PowerShell):**
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\run_pipeline.ps1
```

**Linux / macOS:**
```bash
chmod +x run_pipeline.sh
./run_pipeline.sh
```

Both scripts run all steps in order, print coloured status messages, and
distinguish between fatal failures (pipeline stops) and non-fatal ones
(warning printed, pipeline continues).

### Manual step-by-step

**Step 1 -- Download data (R)**
```r
source("R/01_download_hfd.R")       # TFR, ASFR, MAB from HFD
source("R/02_download_oecd.R")      # TFR for Korea + contextual vars
source("R/03_download_eurostat.R")  # NUTS-2 ASFR (optional)
```

**Step 2 -- Harmonise (R)**
```r
source("R/04_clean_harmonise.R")
source("R/05_exploratory_plots.R")
```

**Step 3 -- Compute WTFE (Julia)**
```bash
julia --project=julia julia/03_simulation.jl
julia --project=julia julia/04_compute_wtfe.jl
julia --project=julia julia/05_plot_wtfe.jl
julia --project=julia julia/06_early_warning.jl
julia --project=julia julia/07_multivariate_asfr.jl   # optional
julia --project=julia julia/08_quantum_tempo.jl        # optional
```

**Step 4 -- Contextual analysis (R)**
```r
source("R/06_contextual_correlations.R")
```

---

## Repository structure

```
TDA_Fertility/
|
|-- .env.example               <- credentials template (copy to .env)
|-- .gitignore
|-- README.md
|-- run_pipeline.ps1           <- automated runner (Windows)
|-- run_pipeline.sh            <- automated runner (Linux/macOS)
|
|-- R/
|   |-- 00_setup.R             <- install R packages
|   |-- 01_download_hfd.R      <- HFD: TFR, ASFR, MAB
|   |-- 02_download_oecd.R     <- OECD: Korea TFR + GDP, LFPR, family exp.
|   |-- 03_download_eurostat.R <- Eurostat: NUTS-2 ASFR (optional)
|   |-- 04_clean_harmonise.R   <- merge and harmonise all sources
|   |-- 05_exploratory_plots.R <- TFR trajectory plots
|   \-- 06_contextual_correlations.R
|
|-- julia/
|   |-- Project.toml           <- Julia package declarations
|   |-- 01_install_deps.jl     <- install Julia packages
|   |-- 02_wtfe_functions.jl   <- core WTFE library (sourced by others)
|   |-- 03_simulation.jl       <- proof-of-concept on synthetic data
|   |-- 04_compute_wtfe.jl     <- rolling WTFE + parameter sensitivity
|   |-- 05_plot_wtfe.jl        <- trajectory plots
|   |-- 06_early_warning.jl    <- structural break + WTFE lead analysis
|   |-- 07_multivariate_asfr.jl <- ASFR-vector extension (optional)
|   \-- 08_quantum_tempo.jl    <- quantum vs. tempo decomposition (optional)
|
|-- data/
|   |-- raw/                   <- downloaded files       [git-ignored]
|   \-- processed/             <- harmonised CSVs        [git-ignored]
|
\-- output/
    |-- figures/               <- PDF/PNG plots           [git-ignored]
    \-- tables/                <- CSV result tables       [git-ignored]
```

---

## Key outputs

| File | Description |
|------|-------------|
| `output/tables/wtfe_baseline.csv` | Rolling WTFE, baseline params (m=2, tau=1, w=20) |
| `output/tables/wtfe_all_params.csv` | WTFE across full (m, tau, window) grid |
| `output/tables/wtfe_summary.csv` | Per-country summary statistics |
| `output/tables/early_warning.csv` | TFR break years and WTFE lead times |
| `output/tables/quantum_tempo.csv` | WTFE(TFR) vs. WTFE(MAB) per country |
| `output/figures/simulation_wtfe.pdf` | Proof-of-concept on synthetic series |
| `output/figures/wtfe_all_countries.pdf` | Multi-country WTFE overlay |

---

## Data sources

| Source | URL | Access |
|--------|-----|--------|
| Human Fertility Database | https://www.humanfertility.org | Free registration required |
| OECD Family Database | https://stats.oecd.org | Open API, no registration |
| Eurostat | https://ec.europa.eu/eurostat | Open API, no registration |

Data files are **not** included in this repository and must be downloaded
by running the pipeline. This is required by the HFD terms of use.

---

## Citation

If you use this code, please cite the accompanying paper (forthcoming).

---

## License

MIT License. See `LICENSE` for details.
