#!/usr/bin/env julia

using Oceananigans
using Oceananigans.Units
using Oceananigans.Fields: interior
using Dates
using CUDA
using JLD2
using Printf

# Load the high-resolution GoM model builder
include(joinpath(@__DIR__, "..", "configs", "gom_config_hr.jl"))
include(joinpath(@__DIR__, "gom_env_utils.jl"))

# --------------------------------------------------------------------------- #
# Choose architecture
# --------------------------------------------------------------------------- #

arch = CUDA.has_cuda() ? GPU() : CPU()
@info "Using architecture" arch

# --------------------------------------------------------------------------- #
# Runtime configuration
# --------------------------------------------------------------------------- #

initialize_hycom_free_surface = parse_env_bool("GOM_HR_INIT_SSH", false)
initialize_hycom_velocity = parse_env_bool("GOM_HR_INIT_VELOCITY", false)
atmosphere_mode = parse_env_symbol("GOM_HR_FORCING_MODE", :jra55, (:none, :jra55))

@info "10-day run configuration" initialize_hycom_free_surface initialize_hycom_velocity atmosphere_mode

# Build coupled ocean–sea ice model with HYCOM initialization
coupled_model = build_gom_hr_ocean_seaice_model(;
    arch = arch,
    use_hycom = true,
    initialize_free_surface = initialize_hycom_free_surface,
    initialize_velocity = initialize_hycom_velocity,
    atmosphere_mode = atmosphere_mode,
)

# --------------------------------------------------------------------------- #
# Time-stepping setup
# --------------------------------------------------------------------------- #

Δt_sim        = 20.0       # time step (seconds)
stop_time_sim = 10days

simulation = Simulation(coupled_model;
                        Δt = Δt_sim,
                        stop_time = stop_time_sim)

# --------------------------------------------------------------------------- #
# Progress callback: print every 500 iterations
#   IMPORTANT: use time(sim) and iteration(sim) instead of sim.clock
# --------------------------------------------------------------------------- #

simulation.callbacks[:progress] = Callback(IterationInterval(500)) do sim
    t_seconds = time(sim)              # current model time [s]
    it        = iteration(sim)         # current iteration
    t_days    = t_seconds / 86400.0
    pct       = 100.0 * t_seconds / stop_time_sim

    @info @sprintf("Progress: t = %.2f days (%.1f%%), iter = %d",
                   t_days, pct, it)
end

@info "Starting 10-day high-resolution GoM simulation" Δt = simulation.Δt stop_time = simulation.stop_time

# Run the simulation
run!(simulation)

@info "Finished 10-day high-resolution GoM simulation."

# --------------------------------------------------------------------------- #
# Save final snapshot
# --------------------------------------------------------------------------- #

output_dir = joinpath(@__DIR__, "..", "runs", "gom_hr_output")
mkpath(output_dir)

snapshot_file = joinpath(output_dir, "gom_hr_10days_snapshot_hycom.jld2")

# Extract ocean model from coupled model
ocean_model = coupled_model.ocean.model

η_data = Array(interior(ocean_model.free_surface.η))   # 2D
T_data = Array(interior(ocean_model.tracers.T))        # 3D
S_data = Array(interior(ocean_model.tracers.S))        # 3D

@info "η_data size" size(η_data)
@info "T_data size" size(T_data)
@info "S_data size" size(S_data)

if any(isnan, η_data)
    @warn "NaNs found in η_data before saving snapshot."
end
if any(isnan, T_data)
    @warn "NaNs found in T_data before saving snapshot."
end
if any(isnan, S_data)
    @warn "NaNs found in S_data before saving snapshot."
end

@info "Saving final 10-day HYCOM-initialized snapshot to $snapshot_file"
jldsave(snapshot_file; η = η_data, T = T_data, S = S_data)
@info "Snapshot saved."
