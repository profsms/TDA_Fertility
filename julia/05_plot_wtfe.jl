# ============================================================
#  05_plot_wtfe.jl
#  Visualise rolling WTFE trajectories alongside raw TFR for
#  each country.  Also produces sensitivity / parameter plots.
#
#  Run:  julia --project=julia julia/05_plot_wtfe.jl
# ============================================================

using Pkg; Pkg.activate(joinpath(@__DIR__))
using CSV, DataFrames, Plots, Statistics

tbl_dir = "output/tables"
fig_dir = "output/figures"
mkpath(fig_dir)

proc_dir = "data/processed"

# Load results
wtfe_all  = CSV.read(joinpath(tbl_dir, "wtfe_all_params.csv"),  DataFrame)
wtfe_base = CSV.read(joinpath(tbl_dir, "wtfe_baseline.csv"),    DataFrame)
tfr_panel = CSV.read(joinpath(proc_dir, "tfr_panel.csv"),       DataFrame)

countries = sort(unique(wtfe_base.iso3))

# Colour palette (one per country)
palette_colours = [:steelblue, :firebrick, :forestgreen, :darkorchid,
                   :darkorange, :teal, :hotpink, :saddlebrown,
                   :navy, :olive, :crimson]
country_colours = Dict(zip(countries, palette_colours))

# ------------------------------------------------------------
#  1. Dual-axis panel per country: TFR (top) + WTFE (bottom)
# ------------------------------------------------------------
for cntry in countries
    sub_wtfe = filter(:iso3 => ==(cntry), wtfe_base)
    sub_tfr  = filter(:iso3 => ==(cntry), tfr_panel)
    isempty(sub_wtfe) && continue
    cname = first(sub_wtfe.name)

    p_tfr = plot(sub_tfr.year, sub_tfr.tfr,
                 lw=2, colour=country_colours[cntry],
                 ylabel="TFR", legend=false,
                 title="$cname — TFR and WTFE")
    hline!(p_tfr, [2.1], colour=:grey50, linestyle=:dot)

    p_wtfe = plot(sub_wtfe.year, sub_wtfe.wtfe,
                  lw=2, colour=country_colours[cntry],
                  xlabel="Year", ylabel="WTFE", legend=false,
                  fillrange=0, fillalpha=0.15,
                  fillcolour=country_colours[cntry])
    hline!(p_wtfe, [0.0], colour=:grey50, linestyle=:dot)

    p = plot(p_tfr, p_wtfe, layout=(2,1), size=(800,500))
    fname = joinpath(fig_dir, "country_$(lowercase(cntry)).pdf")
    savefig(p, fname)
    println("Saved: $fname")
end

# ------------------------------------------------------------
#  2. Multi-country WTFE overlay (baseline)
# ------------------------------------------------------------
p_all = plot(title="Rolling WTFE — all countries (baseline: m=2, τ=1, w=20)",
             xlabel="Year", ylabel="WTFE", size=(1000, 550), legend=:topright)

for cntry in countries
    sub = filter(:iso3 => ==(cntry), wtfe_base)
    isempty(sub) && continue
    cname = first(sub.name)
    plot!(p_all, sub.year, sub.wtfe,
          lw=1.8, label=cname, colour=country_colours[cntry])
end

savefig(p_all, joinpath(fig_dir, "wtfe_all_countries.pdf"))
savefig(p_all, joinpath(fig_dir, "wtfe_all_countries.png"))
println("Saved: output/figures/wtfe_all_countries.pdf")

# ------------------------------------------------------------
#  3. Sensitivity: WTFE for one country across all parameter sets
#    (Sweden — expect rich cyclical structure)
# ------------------------------------------------------------
cntry_sens = "SWE"
sub_sens   = filter(:iso3 => ==(cntry_sens), wtfe_all)

p_sens = plot(title="WTFE sensitivity — $(cntry_sens) — parameter grid",
              xlabel="Year", ylabel="WTFE", size=(900, 500))

param_combos = unique(sub_sens[!, [:m, :tau, :window]])
for row in eachrow(param_combos)
    sub_p = filter(r -> r.m == row.m && r.tau == row.tau &&
                        r.window == row.window, sub_sens)
    lbl = "m=$(row.m), τ=$(row.tau), w=$(row.window)"
    plot!(p_sens, sub_p.year, sub_p.wtfe, label=lbl, lw=1.5)
end

savefig(p_sens, joinpath(fig_dir, "wtfe_sensitivity_$(cntry_sens).pdf"))
println("Saved: wtfe_sensitivity_$(cntry_sens).pdf")

# ------------------------------------------------------------
#  4. Entropy vs. max-persistence scatter (baseline, all countries)
# ------------------------------------------------------------
p_scatter = scatter(wtfe_base.entropy, wtfe_base.max_pers,
                    group=wtfe_base.name,
                    xlabel="Persistent entropy H(t)",
                    ylabel="Max persistence ℓ*(t)",
                    title="Entropy vs. maximal persistence",
                    markersize=2, alpha=0.5, size=(700, 500))
savefig(p_scatter, joinpath(fig_dir, "entropy_vs_maxpers.pdf"))
println("Saved: entropy_vs_maxpers.pdf")

println("\nAll plots complete.")
