# ============================================================
#  07_multivariate_asfr.jl
#  Extension: compute WTFE on the age-specific fertility rate
#  (ASFR) vector directly, without delay embedding.
#
#  Each year is represented as a point in ℝ⁷ (7 five-year
#  age groups 15-19, ..., 45-49).  The point cloud is the
#  sequence of these vectors over a rolling window.
#  H₁ of this cloud captures cyclical evolution of the
#  fertility AGE PROFILE — tempo dynamics, not just level.
#
#  Run:  julia --project=julia julia/07_multivariate_asfr.jl
# ============================================================

using Pkg; Pkg.activate(joinpath(@__DIR__))

include("02_wtfe_functions.jl")

using CSV, DataFrames, Plots, Statistics

proc_dir = "data/processed"
tbl_dir  = "output/tables"
fig_dir  = "output/figures"
mkpath(tbl_dir); mkpath(fig_dir)

# ------------------------------------------------------------
#  Load ASFR panel
# ------------------------------------------------------------
asfr_path = joinpath(proc_dir, "asfr_panel.csv")
if !isfile(asfr_path)
    println("asfr_panel.csv not found — skipping multivariate analysis.")
    println("Run R/01_download_hfd.R and R/04_clean_harmonise.R first.")
    exit(0)
end

asfr_panel = CSV.read(asfr_path, DataFrame)
dropmissing!(asfr_panel, :asfr)
sort!(asfr_panel, [:iso3, :year, :age_group])

age_groups = ["15-19","20-24","25-29","30-34","35-39","40-44","45-49"]

countries = sort(unique(asfr_panel.iso3))
println("Countries with ASFR data: ", join(countries, ", "))

# ------------------------------------------------------------
#  Helper: pivot ASFR to wide format (one row per year,
#  7 columns for age groups)
# ------------------------------------------------------------
function asfr_matrix(sub_asfr::DataFrame, age_groups::Vector{String})
    # Coerce year and asfr to concrete numeric types defensively
    # parse with NA handling
    parse_float(s) = (strip(string(s)) in ("NA","NaN","","missing")) ? NaN : parse(Float64, string(s))
    parse_int(s)   = parse(Int, string(s))
    sub_asfr = transform(sub_asfr,
        :year      => (x -> parse_int.(x))   => :year,
        :asfr      => (x -> parse_float.(x)) => :asfr,
        :age_group => (x -> string.(x))       => :age_group
    )
    years_all = sort(unique(sub_asfr.year))
    mat = Matrix{Float64}(undef, length(years_all), length(age_groups))
    fill!(mat, NaN)
    for (i, yr) in enumerate(years_all)
        yr_rows = filter(:year => ==(yr), sub_asfr)
        for (j, ag) in enumerate(age_groups)
            ag_rows = filter(:age_group => ==(ag), yr_rows)
            mat[i, j] = isempty(ag_rows) ? NaN : Float64(first(ag_rows.asfr))
        end
    end
    return years_all, mat
end

# ------------------------------------------------------------
#  Rolling WTFE on multivariate point cloud (no delay embedding)
# ------------------------------------------------------------
function rolling_wtfe_mv(years::Vector, cloud_full::Matrix;
                          window::Int=20, step::Int=1)
    T = size(cloud_full, 1)
    out_year    = Int[]
    out_wtfe    = Float64[]
    out_entropy = Float64[]
    out_maxp    = Float64[]
    out_ncycles = Int[]

    for t in window:step:T
        win_idx = (t - window + 1):t
        cloud_w = cloud_full[win_idx, :]

        # Drop rows with any NaN
        valid = [!any(isnan.(cloud_w[i, :])) for i in 1:size(cloud_w, 1)]
        cloud_clean = cloud_w[valid, :]
        size(cloud_clean, 1) < 4 && continue

        cloud_norm, diam = normalise_cloud(cloud_clean)
        diam ≈ 0 && continue

        pairs = h1_diagram(cloud_norm)
        H     = persistent_entropy(pairs)
        lstar = max_persistence(pairs)
        wtfe  = H * lstar

        push!(out_year,    years[t])
        push!(out_wtfe,    wtfe)
        push!(out_entropy, H)
        push!(out_maxp,    lstar)
        push!(out_ncycles, length(pairs))
    end

    return (year=out_year, wtfe=out_wtfe, entropy=out_entropy,
            max_persistence=out_maxp, n_cycles=out_ncycles)
end

# ------------------------------------------------------------
#  Compute for all countries
# ------------------------------------------------------------
all_mv = DataFrame()
windows = [15, 20, 25]

for cntry in countries
    sub = filter(:iso3 => ==(cntry), asfr_panel)
    cname = first(sub.name)
    years_vec, mat = asfr_matrix(sub, age_groups)

    println("$cntry ($(length(years_vec)) years of ASFR)")

    for w in windows
        length(years_vec) < w && continue
        res = rolling_wtfe_mv(years_vec, mat; window=w)
        n = length(res.year)
        n == 0 && continue

        df = DataFrame(
            iso3     = fill(cntry, n),
            name     = fill(cname, n),
            year     = res.year,
            wtfe_mv  = res.wtfe,
            entropy  = res.entropy,
            max_pers = res.max_persistence,
            n_cycles = res.n_cycles,
            window   = fill(w, n)
        )
        append!(all_mv, df)
    end
end

CSV.write(joinpath(tbl_dir, "wtfe_multivariate.csv"), all_mv)
println("Saved: output/tables/wtfe_multivariate.csv  (",
        nrow(all_mv), " rows)")

# ------------------------------------------------------------
#  Plot: compare scalar WTFE vs. multivariate WTFE per country
# ------------------------------------------------------------
wtfe_scalar = CSV.read(joinpath(tbl_dir, "wtfe_baseline.csv"), DataFrame)

for cntry in countries
    sub_mv  = filter(r -> r.iso3 == cntry && r.window == 20, all_mv)
    sub_sc  = filter(:iso3 => ==(cntry), wtfe_scalar)
    (isempty(sub_mv) || isempty(sub_sc)) && continue
    cname = first(sub_sc.name)

    p = plot(sub_sc.year, sub_sc.wtfe,
             label="Scalar WTFE (TFR)", lw=2, colour=:steelblue)
    plot!(p, sub_mv.year, sub_mv.wtfe_mv,
          label="Multivariate WTFE (ASFR)", lw=2,
          colour=:firebrick, linestyle=:dash)
    xlabel!(p, "Year"); ylabel!(p, "WTFE")
    title!(p, "$cname — scalar vs. multivariate WTFE")

    savefig(p, joinpath(fig_dir,
            "wtfe_mv_vs_scalar_$(lowercase(cntry)).pdf"))
end
println("Saved multivariate comparison plots.")

# ------------------------------------------------------------
#  ASFR profile heatmaps per country
#  (shows how age profile shifts — motivates the extension)
# ------------------------------------------------------------
for cntry in countries
    sub = filter(:iso3 => ==(cntry), asfr_panel)
    cname = first(sub.name)
    years_vec, mat = asfr_matrix(sub, age_groups)
    any(isnan.(mat)) && (mat[isnan.(mat)] .= 0.0)

    p = heatmap(years_vec, age_groups, mat',
                xlabel="Year", ylabel="Age group",
                title="$cname — ASFR heatmap",
                colour=:YlOrRd, size=(800, 350))
    savefig(p, joinpath(fig_dir,
            "asfr_heatmap_$(lowercase(cntry)).pdf"))
end
println("Saved ASFR heatmaps.")

println("\nMultivariate ASFR analysis complete.")
