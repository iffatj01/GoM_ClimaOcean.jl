using JLD2
using Plots

# Path relative to this file
jld2_path = joinpath(@__DIR__, "..", "runs", "gom_hr_output", "gom_hr_10days.jld2")

@info "Opening " jld2_path
jldopen(jld2_path, "r") do file
    # Our JLD2 writer stores fields + grid
    η = file["η"]   # time, z=1 (surface), y, x or similar
    # We'll just take the last time slice and surface level

    # This may require adjusting depending on the saved dimensionality.
    # Often η is 3D: (x, y, time), but JLD2OutputWriter usually writes it as is.
    # Let's print its size first:
    @show size(η)

    # If it's (Nx, Ny, Nt), last time snapshot might be η[:, :, end]
    # For now just stop here to inspect size; we can refine once we know.
end
