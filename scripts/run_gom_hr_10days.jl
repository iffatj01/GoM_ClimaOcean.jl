using Oceananigans
using Oceananigans.Units
using Oceananigans.Fields: interior
using Dates
using CUDA
using JLD2

# Bring in the builder function
include(joinpath(@__DIR__, "..", "configs", "gom_config_hr.jl"))

# Choose architecture
arch = CUDA.has_cuda() ? GPU() : CPU()
@info "Using architecture" arch

# For now, use_ecco = false (simple T/S). We'll turn this on later.
coupled_model = build_gom_hr_ocean_seaice_model(; arch = arch, use_ecco = false)

# Simulation: 10 days at 5-minute time step
simulation = Simulation(coupled_model;
                        Δt = 5minutes,
                        stop_time = 10days)

@info "Starting high-resolution GoM simulation for 10 days..."
run!(simulation)
@info "Finished high-resolution GoM simulation."

# ---- Save a final snapshot with JLD2 (no OutputWriter) ----------------

output_dir = joinpath(@__DIR__, "..", "runs", "gom_hr_output")
mkpath(output_dir)

snapshot_file = joinpath(output_dir, "gom_hr_10days_snapshot.jld2")

ocean_model = coupled_model.ocean.model

# Safely get the interior (non-halo) data and move to CPU
η_data = Array(interior(ocean_model.free_surface.η))   # 2D: (y, x) or (x, y)
T_data = Array(interior(ocean_model.tracers.T))        # 3D: (x, y, z)
S_data = Array(interior(ocean_model.tracers.S))        # 3D: (x, y, z)

@info "η_data size" size(η_data)
@info "T_data size" size(T_data)
@info "S_data size" size(S_data)

# Save to JLD2 file
@info "Saving final snapshot to $snapshot_file"
jldsave(snapshot_file; η = η_data, T = T_data, S = S_data)
@info "Snapshot saved."
