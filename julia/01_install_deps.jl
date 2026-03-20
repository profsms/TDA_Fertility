# ============================================================
#  01_install_deps.jl
#  Explicitly add and precompile all required packages.
#  Run once before any other Julia script:
#    julia --project=julia julia/01_install_deps.jl
# ============================================================

using Pkg

Pkg.activate(joinpath(@__DIR__))

# Explicitly add every package by name to ensure resolution
required = [
    "CSV",
    "DataFrames",
    "Distances",
    "Plots",
    "Ripserer",
    "PersistenceDiagrams",
    "StatsBase",
    "DotEnv",
    "Random",
    "Statistics",
    "LinearAlgebra",
]

println("Checking and adding packages...")
for pkg in required
    if !haskey(Pkg.project().dependencies, pkg)
        println("  Adding: ", pkg)
        Pkg.add(pkg)
    else
        println("  Already present: ", pkg)
    end
end

println("\nInstantiating project...")
Pkg.instantiate()

println("\nPrecompiling...")
Pkg.precompile()

println("\nAll Julia dependencies installed and precompiled.")
