# ============================================================
#  run_pipeline.ps1
#  Full WTFE pipeline runner for Windows (PowerShell).
#  Run from the wtfe_project\ directory:
#    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#    .\run_pipeline.ps1
# ============================================================

$ErrorActionPreference = "Stop"

# Colours
function Write-Step  { param($msg) Write-Host "`n$("-"*56)" -ForegroundColor Cyan
                                   Write-Host "  $msg"         -ForegroundColor Cyan
                                   Write-Host "$("-"*56)"      -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "  [OK]   $msg" -ForegroundColor Green  }
function Write-Warn  { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host "  [FAIL] $msg" -ForegroundColor Red; exit 1 }

# Helper: run a command and handle non-fatal failures
function Invoke-Step {
    param([string]$Command, [string[]]$CmdArgs, [bool]$Fatal = $true)
    try {
        & $Command @CmdArgs
        if ($LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE" }
    } catch {
        if ($Fatal) { Write-Fail "Command failed: $Command $CmdArgs`n  $_" }
        else        { Write-Warn "Non-fatal failure: $_" }
    }
}

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#  Header
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Write-Host ""
Write-Host "  WTFE Project --- Full Pipeline" -ForegroundColor Cyan
Write-Host "  $(Get-Date)"                  -ForegroundColor Cyan

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#  Pre-flight checks
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Working directory
if (-not (Test-Path "R") -or -not (Test-Path "julia")) {
    Write-Fail "Please run this script from the wtfe_project\ directory (must contain R\ and julia\ subfolders)."
}

# .env
if (-not (Test-Path ".env")) {
    Write-Fail ".env file not found. Fill in your HFD credentials first."
}
$envContent = Get-Content ".env" -Raw
if ($envContent -match "your_email@example\.com") {
    Write-Fail ".env still contains placeholder credentials. Please fill in HFD_EMAIL and HFD_PASSWORD."
}

# R
try {
    $rver = & Rscript --version 2>&1
    Write-Ok "R found: $rver"
} catch {
    Write-Fail "Rscript not found. Install R from https://cran.r-project.org"
}

# Julia
try {
    $jver = & julia --version 2>&1
    Write-Ok "Julia found: $jver"
} catch {
    Write-Fail "julia not found. Install Julia from https://julialang.org/downloads"
}

# Output dirs
New-Item -ItemType Directory -Force -Path "data\raw","data\processed",
    "output\figures","output\tables" | Out-Null
Write-Ok "Output directories ready."

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#  Step 1 --- R packages
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Write-Step "Step 1: R package installation"
Invoke-Step -Command "Rscript" -CmdArgs @("R\00_setup.R") -Fatal $true
Write-Ok "R packages installed."

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#  Step 2 --- Julia packages
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Write-Step "Step 2: Julia package installation"
Invoke-Step -Command "julia" -CmdArgs @("--project=julia", "julia\01_install_deps.jl") -Fatal $true
Write-Ok "Julia packages installed."

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#  Step 3 --- Data download
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Write-Step "Step 3a: Downloading HFD data (TFR, ASFR, MAB)"
Invoke-Step -Command "Rscript" -CmdArgs @("R\01_download_hfd.R") -Fatal $true
Write-Ok "HFD download complete."

Write-Step "Step 3b: Downloading OECD data"
Invoke-Step -Command "Rscript" -CmdArgs @("R\02_download_oecd.R") -Fatal $false
Write-Ok "OECD download complete."

Write-Step "Step 3c: Downloading Eurostat NUTS-2 data"
Invoke-Step -Command "Rscript" -CmdArgs @("R\03_download_eurostat.R") -Fatal $false
Write-Ok "Eurostat download complete."

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#  Step 4 --- Harmonisation
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Write-Step "Step 4a: Cleaning and harmonising data"
Invoke-Step -Command "Rscript" -CmdArgs @("R\04_clean_harmonise.R") -Fatal $true
Write-Ok "Processed data saved to data\processed\"

Write-Step "Step 4b: Exploratory plots"
Invoke-Step -Command "Rscript" -CmdArgs @("R\05_exploratory_plots.R") -Fatal $false
Write-Ok "Exploratory plots saved to output\figures\"

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#  Step 5 --- Julia WTFE computation
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Write-Step "Step 5a: Simulation proof-of-concept"
Invoke-Step -Command "julia" -CmdArgs @("--project=julia", "julia\03_simulation.jl") -Fatal $true
Write-Ok "Simulation complete."

Write-Step "Step 5b: Computing rolling WTFE (main analysis)"
Invoke-Step -Command "julia" -CmdArgs @("--project=julia", "julia\04_compute_wtfe.jl") -Fatal $true
Write-Ok "WTFE results saved to output\tables\"

Write-Step "Step 5c: Plotting WTFE trajectories"
Invoke-Step -Command "julia" -CmdArgs @("--project=julia", "julia\05_plot_wtfe.jl") -Fatal $false
Write-Ok "WTFE plots saved to output\figures\"

Write-Step "Step 5d: Early-warning analysis"
Invoke-Step -Command "julia" -CmdArgs @("--project=julia", "julia\06_early_warning.jl") -Fatal $false
Write-Ok "Early-warning results saved."

Write-Step "Step 5e: Multivariate ASFR extension"
Invoke-Step -Command "julia" -CmdArgs @("--project=julia", "julia\07_multivariate_asfr.jl") -Fatal $false
Write-Ok "Multivariate analysis complete."

Write-Step "Step 5f: Quantum-tempo decomposition"
Invoke-Step -Command "julia" -CmdArgs @("--project=julia", "julia\08_quantum_tempo.jl") -Fatal $false
Write-Ok "Quantum-tempo decomposition complete."

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#  Step 6 --- Contextual correlations
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Write-Step "Step 6: Contextual correlation analysis"
Invoke-Step -Command "Rscript" -CmdArgs @("R\06_contextual_correlations.R") -Fatal $false
Write-Ok "Contextual analysis complete."

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#  Done
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Write-Host ""
Write-Host "$("-"*56)" -ForegroundColor Green
Write-Host "  Pipeline complete!  $(Get-Date)" -ForegroundColor Green
Write-Host "$("-"*56)" -ForegroundColor Green
Write-Host ""
Write-Host "  Key outputs:"
Write-Host "    output\tables\wtfe_baseline.csv       : main WTFE results"
Write-Host "    output\tables\wtfe_summary.csv        : per-country summary"
Write-Host "    output\tables\early_warning.csv       : early-warning lead times"
Write-Host "    output\figures\wtfe_all_countries.pdf : trajectory overview"
Write-Host "    output\figures\simulation_wtfe.pdf    : proof-of-concept"
Write-Host ""
