# ============================================================
#  03_simulation.jl
#  Proof-of-concept: show WTFE behaves correctly on three
#  synthetic series:
#    (a) Pure monotone decline
#    (b) AR(1) with noise (no genuine cycles)
#    (c) Damped oscillation with a rebound
#
#  Run:  julia --project=julia julia/03_simulation.jl
# ============================================================

using Pkg; Pkg.activate(joinpath(@__DIR__))

include("02_wtfe_functions.jl")

using CSV, DataFrames, Random, Plots

Random.seed!(42)

out_dir = "output/figures"
mkpath(out_dir)
tbl_dir = "output/tables"
mkpath(tbl_dir)

T = 60   # simulate 60 years

# ------------------------------------------------------------
#  Generate synthetic series
# ------------------------------------------------------------

# (a) Monotone decline: linear from 3.0 to 1.1
series_a = collect(range(3.0, 1.1, length=T)) .+
           0.05 .* randn(T)

# (b) AR(1) noise around a declining trend (φ=0.6)
trend_b = collect(range(2.8, 1.3, length=T))
noise_b = zeros(T)
noise_b[1] = 0.05 * randn()
for t in 2:T
    noise_b[t] = 0.6 * noise_b[t-1] + 0.05 * randn()
end
series_b = trend_b .+ noise_b

# (c) Damped oscillation with genuine rebound
#     Decline → partial rebound → decline again
t_vec = 1:T
series_c = 2.8 .- 0.02 .* t_vec .+
           0.4 .* sin.(2π .* t_vec ./ 18) .*
           exp.(-0.03 .* t_vec) .+
           0.05 .* randn(T)
series_c = max.(series_c, 0.8)   # floor at 0.8

years = collect(1960:(1960+T-1))

# ------------------------------------------------------------
#  Compute rolling WTFE for each series
# ------------------------------------------------------------
params = (window=20, m=2, τ=1)

res_a = rolling_wtfe(years, series_a; params...)
res_b = rolling_wtfe(years, series_b; params...)
res_c = rolling_wtfe(years, series_c; params...)

# ------------------------------------------------------------
#  Summary table
# ------------------------------------------------------------
summary_df = DataFrame(
    Series      = ["(a) Monotone decline",
                   "(b) AR(1) + trend",
                   "(c) Damped oscillation"],
    Mean_WTFE   = [mean(res_a.wtfe), mean(res_b.wtfe), mean(res_c.wtfe)],
    Max_WTFE    = [maximum(res_a.wtfe), maximum(res_b.wtfe), maximum(res_c.wtfe)],
    Mean_H      = [mean(res_a.entropy), mean(res_b.entropy), mean(res_c.entropy)],
    Mean_lstar  = [mean(res_a.max_persistence),
                   mean(res_b.max_persistence),
                   mean(res_c.max_persistence)]
)

println("\n=== Simulation summary ===")
println(summary_df)
CSV.write(joinpath(tbl_dir, "simulation_summary.csv"), summary_df)

# ------------------------------------------------------------
#  Plots
# ------------------------------------------------------------

# Panel 1: raw series
p1 = plot(years, series_a, label="(a) Monotone", lw=2, colour=:firebrick)
plot!(p1, years, series_b, label="(b) AR(1)", lw=2, colour=:darkorange,
      linestyle=:dash)
plot!(p1, years, series_c, label="(c) Oscillatory", lw=2, colour=:steelblue)
hline!(p1, [2.1], colour=:grey, linestyle=:dot, label="Replacement")
xlabel!(p1, "Year"); ylabel!(p1, "Simulated TFR")
title!(p1, "Synthetic fertility series")

# Panel 2: rolling WTFE
p2 = plot(res_a.year, res_a.wtfe, label="(a) Monotone",
          lw=2, colour=:firebrick)
plot!(p2, res_b.year, res_b.wtfe, label="(b) AR(1)",
      lw=2, colour=:darkorange, linestyle=:dash)
plot!(p2, res_c.year, res_c.wtfe, label="(c) Oscillatory",
      lw=2, colour=:steelblue)
xlabel!(p2, "Year (end of window)"); ylabel!(p2, "WTFE")
title!(p2, "Rolling WTFE (window = 20 years)")

p_combined = plot(p1, p2, layout=(2,1), size=(800, 600))
savefig(p_combined, joinpath(out_dir, "simulation_wtfe.pdf"))
savefig(p_combined, joinpath(out_dir, "simulation_wtfe.png"))
println("\nSaved: output/figures/simulation_wtfe.pdf / .png")

println("\nSimulation complete.")
