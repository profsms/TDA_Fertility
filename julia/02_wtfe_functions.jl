# ============================================================
#  02_wtfe_functions.jl
#  Core functions for computing the Weighted Topological
#  Fertility Entropy (WTFE) indicator.
#
#  Include this file from other scripts:
#    include("julia/02_wtfe_functions.jl")
# ============================================================

using Ripserer
using PersistenceDiagrams
using Distances
using StatsBase
using LinearAlgebra

# ------------------------------------------------------------
#  1. Takens / delay embedding
# ------------------------------------------------------------

"""
    delay_embedding(x::AbstractVector{<:Real}; m::Int=2, τ::Int=1)

Embed scalar time series `x` into ℝᵐ via delay embedding with
dimension `m` and lag `τ`.  Returns a matrix of size (N, m) where
N = length(x) - (m-1)*τ.
"""
function delay_embedding(x::AbstractVector{<:Real}; m::Int=2, τ::Int=1)
    N = length(x) - (m - 1) * τ
    N > 0 || error("Series too short for m=$m, τ=$τ")
    cloud = Matrix{Float64}(undef, N, m)
    for i in 1:N
        for j in 1:m
            cloud[i, j] = x[i + (j - 1) * τ]
        end
    end
    return cloud
end

# ------------------------------------------------------------
#  2. Normalise point cloud to unit diameter
# ------------------------------------------------------------

"""
    normalise_cloud(cloud::Matrix{<:Real})

Normalise a point cloud to unit diameter (maximum pairwise distance = 1).
Returns (normalised_cloud, diameter).
"""
function normalise_cloud(cloud::Matrix{<:Real})
    dists = pairwise(Euclidean(), cloud, dims=1)
    diam  = maximum(dists)
    diam > 0 || return cloud, 0.0
    return cloud ./ diam, diam
end

# ------------------------------------------------------------
#  3. Compute H₁ persistence diagram via Vietoris-Rips
# ------------------------------------------------------------

"""
    h1_diagram(cloud::Matrix{<:Real}; threshold::Real=Inf)

Compute the H₁ (1-dimensional) persistence diagram of the point
cloud using the Vietoris-Rips filtration (via Ripserer.jl).
Returns a vector of (birth, death) pairs, excluding infinite bars.
"""
function h1_diagram(cloud::Matrix{<:Real}; threshold::Real=Inf)
    # Ripserer expects points as a vector of tuples or a matrix
    pts = [Tuple(cloud[i, :]) for i in 1:size(cloud, 1)]
    result = ripserer(pts; dim_max=1, threshold=threshold)
    # result[2] is the H₁ diagram (0-indexed: result[1] = H₀)
    diagram = result[2]
    # Extract finite pairs only
    pairs = [(birth(p), death(p)) for p in diagram if isfinite(death(p))]
    return pairs
end

# ------------------------------------------------------------
#  4. Persistent entropy H(t)
# ------------------------------------------------------------

"""
    persistent_entropy(pairs::Vector)

Compute the persistent entropy of a set of (birth, death) pairs.
Returns 0.0 if there are no finite pairs.
"""
function persistent_entropy(pairs::Vector)
    isempty(pairs) && return 0.0
    lifetimes = [d - b for (b, d) in pairs]
    L = sum(lifetimes)
    L ≈ 0 && return 0.0
    p = lifetimes ./ L
    return -sum(pi * log(pi) for pi in p if pi > 0)
end

# ------------------------------------------------------------
#  5. Maximal persistence ℓ*(t)
# ------------------------------------------------------------

"""
    max_persistence(pairs::Vector)

Return the maximum lifetime among all (birth, death) pairs.
Returns 0.0 if empty.
"""
function max_persistence(pairs::Vector)
    isempty(pairs) && return 0.0
    return maximum(d - b for (b, d) in pairs)
end

# ------------------------------------------------------------
#  6. WTFE for a single window
# ------------------------------------------------------------

"""
    wtfe_window(x::AbstractVector{<:Real}; m::Int=2, τ::Int=1,
                threshold_frac::Real=1.0)

Compute WTFE for a single time series window `x`.
`threshold_frac` sets the Rips filtration cutoff as a fraction of
the normalised diameter (default 1.0 = full diameter).

Returns a NamedTuple: (wtfe, entropy, max_pers, n_cycles, diameter)
"""
function wtfe_window(x::AbstractVector{<:Real};
                     m::Int=2, τ::Int=1,
                     threshold_frac::Real=1.0)
    length(x) < m * τ + 2 && return (wtfe=0.0, entropy=0.0,
                                      max_pers=0.0, n_cycles=0,
                                      diameter=0.0)

    cloud, diam = normalise_cloud(delay_embedding(x; m=m, τ=τ))
    diam ≈ 0 && return (wtfe=0.0, entropy=0.0, max_pers=0.0,
                        n_cycles=0, diameter=0.0)

    pairs = h1_diagram(cloud; threshold=threshold_frac)
    H     = persistent_entropy(pairs)
    lstar = max_persistence(pairs)

    # WTFE = H(t) * ℓ*(t) / C_t
    # Since cloud is already normalised (diameter = 1 after
    # normalise_cloud), ℓ*(t)/C_t = lstar / 1 = lstar.
    # The original diameter is preserved separately for reference.
    wtfe = H * lstar

    return (wtfe     = wtfe,
            entropy  = H,
            max_pers = lstar,
            n_cycles = length(pairs),
            diameter = diam)
end

# ------------------------------------------------------------
#  7. Rolling WTFE over a full TFR series
# ------------------------------------------------------------

"""
    rolling_wtfe(years::AbstractVector{<:Int},
                 tfr::AbstractVector{<:Real};
                 window::Int=20, m::Int=2, τ::Int=1,
                 step::Int=1)

Compute WTFE in a rolling window of width `window` years over the
TFR series.  Returns a DataFrame-compatible NamedTuple of vectors
aligned to the *last year* of each window.

Arguments:
  years   -- integer year vector (length T)
  tfr     -- TFR values (length T, same order as years)
  window  -- rolling window width in years
  m, τ    -- embedding parameters
  step    -- step size between windows (1 = annual rolling)
"""
function rolling_wtfe(years::AbstractVector{<:Int},
                      tfr::AbstractVector{<:Real};
                      window::Int=20, m::Int=2, τ::Int=1,
                      step::Int=1)
    T = length(tfr)
    @assert length(years) == T

    out_year    = Int[]
    out_wtfe    = Float64[]
    out_entropy = Float64[]
    out_maxp    = Float64[]
    out_ncycles = Int[]

    for t in window:step:T
        win_idx = (t - window + 1):t
        res = wtfe_window(tfr[win_idx]; m=m, τ=τ)

        push!(out_year,    years[t])
        push!(out_wtfe,    res.wtfe)
        push!(out_entropy, res.entropy)
        push!(out_maxp,    res.max_pers)
        push!(out_ncycles, res.n_cycles)
    end

    return (year    = out_year,
            wtfe    = out_wtfe,
            entropy = out_entropy,
            max_persistence = out_maxp,
            n_cycles = out_ncycles)
end

# ------------------------------------------------------------
#  8. Mutual information lag selection (simple discretised version)
# ------------------------------------------------------------

"""
    mi_lag_select(x::AbstractVector{<:Real}; max_τ::Int=10, bins::Int=10)

Select the delay lag τ as the first local minimum of the
time-delayed mutual information, up to `max_τ`.
Falls back to τ=1 if no local minimum is found.
"""
function mi_lag_select(x::AbstractVector{<:Real};
                       max_τ::Int=10, bins::Int=10)
    mi_vals = Float64[]
    for τ in 1:max_τ
        n   = length(x) - τ
        xi  = x[1:n]
        xτ  = x[(1+τ):(n+τ)]
        # Discretise into `bins` equal-width bins
        edges = range(minimum(x), maximum(x), length=bins+1)
        h = fit(Histogram, (xi, xτ), (edges, edges))
        pij = h.weights ./ sum(h.weights)
        pi_ = sum(pij, dims=2)
        pj_ = sum(pij, dims=1)
        mi  = 0.0
        for i in 1:bins, j in 1:bins
            pij[i,j] > 0 && pi_[i] > 0 && pj_[j] > 0 || continue
            mi += pij[i,j] * log(pij[i,j] / (pi_[i] * pj_[j]))
        end
        push!(mi_vals, mi)
    end
    # First local minimum
    for i in 2:(length(mi_vals)-1)
        if mi_vals[i] < mi_vals[i-1] && mi_vals[i] < mi_vals[i+1]
            return i
        end
    end
    return 1  # fallback
end

println("WTFE functions loaded.")
