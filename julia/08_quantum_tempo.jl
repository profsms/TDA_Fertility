# ============================================================
#  08_quantum_tempo.jl
#  Quantum–tempo decomposition:
#  Compute WTFE separately on
#    (1) TFR             — quantum indicator
#    (2) Mean age at first birth (MAB) — tempo indicator
#  and compare trajectories.
#
#  Divergence between the two signals may flag demographic
#  transitions where tempo postponement temporarily depresses
#  measured TFR without a genuine quantum decline.
#
#  Run:  julia --project=julia julia/08_quantum_tempo.jl
# ============================================================

using Pkg; Pkg.activate(joinpath(@__DIR__))

include("02_wtfe_functions.jl")

using CSV, DataFrames, Plots, Statistics

proc_dir = "data/processed"
tbl_dir  = "output/tables"
fig_dir  = "output/figures"
mkpath(tbl_dir); mkpath(fig_dir)

# ------------------------------------------------------------
#  Load data
# ------------------------------------------------------------
tfr_panel = CSV.read(joinpath(proc_dir, "tfr_panel.csv"), DataFrame)
dropmissing!(tfr_panel, :tfr)
sort!(tfr_panel, [:iso3, :year])

mab_path = joinpath(proc_dir, "mab_panel.csv")
if !isfile(mab_path)
    println("mab_panel.csv not found — skipping quantum-tempo decomposition.")
    println("Run R/01_download_hfd.R and R/04_clean_harmonise.R first.")
    exit(0)
end

mab_panel = CSV.read(mab_path, DataFrame)
dropmissing!(mab_panel, :mab)
sort!(mab_panel, [:iso3, :year])

# Merge on common years
joint = innerjoin(
    tfr_panel[!, [:iso3, :name, :year, :tfr]],
    mab_panel[!, [:iso3, :year, :mab]],
    on = [:iso3, :year]
)
sort!(joint, [:iso3, :year])

countries = sort(unique(joint.iso3))
println("Countries with both TFR and MAB: ", join(countries, ", "))

# ------------------------------------------------------------
#  Compute rolling WTFE for TFR and MAB separately
# ------------------------------------------------------------
params = (window=20, m=2, τ=1)
all_qt = DataFrame()

for cntry in countries
    sub   = filter(:iso3 => ==(cntry), joint)
    cname = first(sub.name)
    sort!(sub, :year)
    length(sub.year) < params.window && continue

    # Quantum: WTFE on TFR
    res_tfr = rolling_wtfe(sub.year, sub.tfr; params...)

    # Tempo: WTFE on MAB
    res_mab = rolling_wtfe(sub.year, sub.mab; params...)

    # Align on common years
    yr_common = intersect(res_tfr.year, res_mab.year)
    idx_tfr = [findfirst(==(y), res_tfr.year) for y in yr_common]
    idx_mab = [findfirst(==(y), res_mab.year) for y in yr_common]

    n = length(yr_common)
    n == 0 && continue

    df = DataFrame(
        iso3        = fill(cntry, n),
        name        = fill(cname, n),
        year        = yr_common,
        wtfe_tfr    = res_tfr.wtfe[idx_tfr],
        wtfe_mab    = res_mab.wtfe[idx_mab],
        entropy_tfr = res_tfr.entropy[idx_tfr],
        entropy_mab = res_mab.entropy[idx_mab],
        maxp_tfr    = res_tfr.max_persistence[idx_tfr],
        maxp_mab    = res_mab.max_persistence[idx_mab]
    )

    # Divergence measure: absolute difference
    df.divergence = abs.(df.wtfe_tfr .- df.wtfe_mab)

    append!(all_qt, df)
end

CSV.write(joinpath(tbl_dir, "quantum_tempo.csv"), all_qt)
println("Saved: output/tables/quantum_tempo.csv  (",
        nrow(all_qt), " rows)")

# ------------------------------------------------------------
#  Summary: correlation between WTFE_TFR and WTFE_MAB
# ------------------------------------------------------------
cor_df = combine(groupby(all_qt, [:iso3, :name]),
    [:wtfe_tfr, :wtfe_mab] =>
        ((a, b) -> cor(a, b)) => :cor_wtfe_tfr_mab,
    :divergence => mean => :mean_divergence,
    :divergence => maximum => :max_divergence
)
sort!(cor_df, :cor_wtfe_tfr_mab)
println("\n=== Quantum–tempo correlation ===")
println(cor_df)
CSV.write(joinpath(tbl_dir, "quantum_tempo_summary.csv"), cor_df)

# ------------------------------------------------------------
#  Plots per country
# ------------------------------------------------------------
for cntry in countries
    sub   = filter(:iso3 => ==(cntry), all_qt)
    isempty(sub) && continue
    cname = first(sub.name)

    p = plot(sub.year, sub.wtfe_tfr,
             label="WTFE (TFR — quantum)", lw=2, colour=:steelblue)
    plot!(p, sub.year, sub.wtfe_mab,
          label="WTFE (MAB — tempo)", lw=2, colour=:firebrick,
          linestyle=:dash)
    plot!(p, sub.year, sub.divergence,
          label="|divergence|", lw=1, colour=:grey50,
          linestyle=:dot, alpha=0.8)
    xlabel!(p, "Year"); ylabel!(p, "WTFE")
    title!(p, "$cname — quantum vs. tempo WTFE")

    savefig(p, joinpath(fig_dir,
            "quantum_tempo_$(lowercase(cntry)).pdf"))
end
println("Saved quantum-tempo plots.")

# ------------------------------------------------------------
#  Multi-country divergence heatmap
# ------------------------------------------------------------
# Pivot to wide: rows = countries, cols = years
years_all = sort(unique(all_qt.year))
div_mat   = fill(NaN, length(countries), length(years_all))
for (i, cntry) in enumerate(countries)
    sub = filter(:iso3 => ==(cntry), all_qt)
    for row in eachrow(sub)
        j = findfirst(==(row.year), years_all)
        isnothing(j) && continue
        div_mat[i, j] = row.divergence
    end
end

cnames = [first(filter(:iso3 => ==(c), all_qt)).name for c in countries]
p_heat = heatmap(years_all, cnames, div_mat,
                 xlabel="Year",
                 title="Quantum–tempo WTFE divergence",
                 colour=:RdYlGn, size=(900, 400))
savefig(p_heat, joinpath(fig_dir, "quantum_tempo_heatmap.pdf"))
savefig(p_heat, joinpath(fig_dir, "quantum_tempo_heatmap.png"))
println("Saved: quantum_tempo_heatmap.pdf / .png")

println("\nQuantum-tempo decomposition complete.")
