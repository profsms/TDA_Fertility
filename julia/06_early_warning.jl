# ============================================================
#  06_early_warning.jl
#  Test the early-warning hypothesis: does WTFE decline
#  *before* the structural break in TFR levels?
#
#  Approach:
#  1. Identify structural breaks in TFR using a CUSUM-style
#     test (rolling mean shift detection, simple implementation).
#  2. For each country with a detected break, measure the
#     lag between WTFE peak-to-trough and the TFR break.
#
#  Run:  julia --project=julia julia/06_early_warning.jl
# ============================================================

using Pkg; Pkg.activate(joinpath(@__DIR__))
using CSV, DataFrames, Statistics, Plots

tbl_dir  = "output/tables"
fig_dir  = "output/figures"
proc_dir = "data/processed"
mkpath(tbl_dir); mkpath(fig_dir)

wtfe_base = CSV.read(joinpath(tbl_dir, "wtfe_baseline.csv"), DataFrame)
tfr_panel = CSV.read(joinpath(proc_dir, "tfr_panel.csv"),    DataFrame)
dropmissing!(tfr_panel, :tfr)
sort!(tfr_panel, [:iso3, :year])

# ------------------------------------------------------------
#  Simple structural break detector:
#  Scan all split-points; flag the year with maximum
#  |mean(before) - mean(after)| as the break year.
#  Minimum segment length = 10 years.
# ------------------------------------------------------------
function detect_break(years, vals; min_seg=10)
    T = length(vals)
    T < 2 * min_seg && return missing, NaN
    best_t  = missing
    best_dif = -Inf
    for t in min_seg:(T - min_seg)
        d = abs(mean(vals[1:t]) - mean(vals[(t+1):T]))
        if d > best_dif
            best_dif = d
            best_t   = years[t]
        end
    end
    return best_t, best_dif
end

# ------------------------------------------------------------
#  WTFE decline detector:
#  Find the last year before the TFR break where WTFE was
#  at its rolling 5-year maximum, then measure the
#  window until WTFE falls below 50% of that maximum.
# ------------------------------------------------------------
function wtfe_decline_onset(sub_wtfe, break_year; lookback=15)
    isempty(sub_wtfe) && return missing
    pre = filter(r -> r.year <= break_year &&
                      r.year >= break_year - lookback, sub_wtfe)
    isempty(pre) && return missing
    idx_peak = argmax(pre.wtfe)
    peak_val = pre[idx_peak, :wtfe]
    peak_val ≈ 0 && return missing
    # Find first year after peak where wtfe < 50% of peak
    post_peak = filter(r -> r.year >= pre[idx_peak, :year], pre)
    onset = findfirst(r -> r.wtfe < 0.5 * peak_val, eachrow(post_peak))
    isnothing(onset) && return missing
    return post_peak[onset, :year]
end

# ------------------------------------------------------------
#  Run analysis
# ------------------------------------------------------------
countries = sort(unique(wtfe_base.iso3))
rows = []

for cntry in countries
    sub_tfr  = filter(:iso3 => ==(cntry), tfr_panel)
    sub_wtfe = filter(:iso3 => ==(cntry), wtfe_base)
    sort!(sub_tfr,  :year)
    sort!(sub_wtfe, :year)
    isempty(sub_tfr) || isempty(sub_wtfe) && continue

    cname = first(sub_wtfe.name)

    break_yr, break_strength = detect_break(sub_tfr.year, sub_tfr.tfr)
    wtfe_onset = ismissing(break_yr) ? missing :
                 wtfe_decline_onset(sub_wtfe, break_yr)

    lead = (ismissing(break_yr) || ismissing(wtfe_onset)) ? missing :
           break_yr - wtfe_onset

    push!(rows, (
        iso3           = cntry,
        name           = cname,
        tfr_break_year = break_yr,
        break_strength = round(break_strength, digits=3),
        wtfe_decline_onset = wtfe_onset,
        lead_years     = lead
    ))
end

results_df = DataFrame(rows)
println("\n=== Early-warning results ===")
println(results_df)
CSV.write(joinpath(tbl_dir, "early_warning.csv"), results_df)
println("Saved: output/tables/early_warning.csv")

# ------------------------------------------------------------
#  Plot: for each country, show TFR with break line and
#  WTFE with decline onset line
# ------------------------------------------------------------
for row in eachrow(results_df)
    ismissing(row.tfr_break_year) && continue
    cntry    = row.iso3
    sub_tfr  = filter(:iso3 => ==(cntry), tfr_panel)
    sub_wtfe = filter(:iso3 => ==(cntry), wtfe_base)
    sort!(sub_tfr, :year); sort!(sub_wtfe, :year)

    p_tfr = plot(sub_tfr.year, sub_tfr.tfr, lw=2, colour=:steelblue,
                 ylabel="TFR", legend=false,
                 title="$(row.name) — early warning test")
    vline!(p_tfr, [row.tfr_break_year], colour=:firebrick, lw=1.5,
           linestyle=:dash, label="TFR break")

    p_w = plot(sub_wtfe.year, sub_wtfe.wtfe, lw=2, colour=:steelblue,
               xlabel="Year", ylabel="WTFE", legend=false,
               fillrange=0, fillalpha=0.12, fillcolour=:steelblue)
    vline!(p_w, [row.tfr_break_year], colour=:firebrick, lw=1.5,
           linestyle=:dash, label="TFR break")
    if !ismissing(row.wtfe_decline_onset)
        vline!(p_w, [row.wtfe_decline_onset], colour=:darkorange, lw=1.5,
               linestyle=:dot, label="WTFE onset")
    end

    p = plot(p_tfr, p_w, layout=(2,1), size=(800, 500))
    savefig(p, joinpath(fig_dir, "early_warning_$(lowercase(cntry)).pdf"))
end

println("\nEarly-warning analysis complete.")
