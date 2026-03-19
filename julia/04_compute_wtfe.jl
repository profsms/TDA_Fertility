# ============================================================
#  04_compute_wtfe.jl
#  Load processed TFR panel and compute rolling WTFE for each
#  country across a grid of (m, τ, window) parameters.
#  Saves results to output/tables/.
#
#  Run:  julia --project=julia julia/04_compute_wtfe.jl
# ============================================================

using Pkg; Pkg.activate(joinpath(@__DIR__))

include("02_wtfe_functions.jl")

using CSV, DataFrames

proc_dir = "data/processed"
tbl_dir  = "output/tables"
mkpath(tbl_dir)

# ------------------------------------------------------------
#  Load data
# ------------------------------------------------------------
tfr_panel = CSV.read(joinpath(proc_dir, "tfr_panel.csv"), DataFrame)
dropmissing!(tfr_panel, :tfr)
sort!(tfr_panel, [:iso3, :year])

countries = unique(tfr_panel.iso3)
println("Countries: ", join(countries, ", "))

# ------------------------------------------------------------
#  Parameter grid for sensitivity analysis
# ------------------------------------------------------------
param_grid = [
    (m=2, τ=1, window=15),
    (m=2, τ=1, window=20),   # ← baseline
    (m=2, τ=2, window=20),
    (m=3, τ=1, window=20),
    (m=3, τ=2, window=20),
    (m=2, τ=1, window=25),
]

# ------------------------------------------------------------
#  Compute WTFE for all countries × all parameter sets
# ------------------------------------------------------------
all_results = DataFrame()

for country in countries
    sub = filter(:iso3 => ==(country), tfr_panel)
    sort!(sub, :year)
    years = sub.year
    tfr   = sub.tfr

    # Auto-select τ via mutual information for the baseline
    τ_auto = mi_lag_select(tfr; max_τ=5)
    println("$country: auto τ = $τ_auto  (n=$(length(tfr)) years)")

    for p in param_grid
        # Skip if series too short for this window
        length(tfr) < p.window && continue

        res = rolling_wtfe(years, tfr;
                           window=p.window, m=p.m, τ=p.τ)

        n = length(res.year)
        df = DataFrame(
            iso3       = fill(country, n),
            name       = fill(first(sub.name), n),
            year       = res.year,
            wtfe       = res.wtfe,
            entropy    = res.entropy,
            max_pers   = res.max_persistence,
            n_cycles   = res.n_cycles,
            m          = fill(p.m, n),
            tau        = fill(p.τ, n),
            window     = fill(p.window, n),
            tau_auto   = fill(τ_auto, n)
        )
        append!(all_results, df)
    end
end

CSV.write(joinpath(tbl_dir, "wtfe_all_params.csv"), all_results)
println("\nSaved: output/tables/wtfe_all_params.csv  (",
        nrow(all_results), " rows)")

# ------------------------------------------------------------
#  Baseline results only (m=2, τ=1, window=20)
# ------------------------------------------------------------
baseline = filter(row -> row.m == 2 && row.tau == 1 && row.window == 20,
                  all_results)
CSV.write(joinpath(tbl_dir, "wtfe_baseline.csv"), baseline)
println("Saved: output/tables/wtfe_baseline.csv  (",
        nrow(baseline), " rows)")

# ------------------------------------------------------------
#  Summary statistics per country (baseline)
# ------------------------------------------------------------
summary = combine(groupby(baseline, [:iso3, :name]),
    :wtfe     => mean => :mean_wtfe,
    :wtfe     => maximum => :max_wtfe,
    :wtfe     => minimum => :min_wtfe,
    :entropy  => mean => :mean_entropy,
    :max_pers => mean => :mean_max_pers,
    :n_cycles => mean => :mean_n_cycles,
    :year     => minimum => :year_min,
    :year     => maximum => :year_max
)
sort!(summary, :mean_wtfe, rev=true)

println("\n=== Baseline WTFE summary (m=2, τ=1, window=20) ===")
println(summary)
CSV.write(joinpath(tbl_dir, "wtfe_summary.csv"), summary)
println("Saved: output/tables/wtfe_summary.csv")

println("\nWTFE computation complete.")
