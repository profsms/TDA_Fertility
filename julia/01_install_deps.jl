# ============================================================
#  01_install_deps.jl
#  Instantiate the Julia project and pre-compile all packages.
#  Run once before any other Julia script:
#    julia --project=julia julia/01_install_deps.jl
# ============================================================

using Pkg

# Activate the project environment (Project.toml lives in julia/)
Pkg.activate(joinpath(@__DIR__))

# Install all packages declared in Project.toml
Pkg.instantiate()
Pkg.precompile()

println("All Julia dependencies installed and precompiled.")
