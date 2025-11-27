using JLD2
using Plots

# Path to snapshot
snapshot_file = joinpath(@__DIR__, "..", "runs", "gom_hr_output", "gom_hr_10days_snapshot.jld2")

@info "Opening snapshot" snapshot_file
data = jldopen(snapshot_file, "r") do f
    (; η = f["η"], T = f["T"], S = f["S"])
end

η = data.η   # size (Nx, Ny, 1) or (Ny, Nx, 1)
@info "η size" size(η)

# Assume η is (Nx, Ny, 1); take surface (first/only time or z index)
η2d = dropdims(η, dims=3)   # now (Nx, Ny)

# Simple plot
plt = heatmap(
    η2d',
    aspect_ratio = :equal,
    xlabel = "x index",
    ylabel = "y index",
    title = "GoM high-res η (day 10 snapshot)",
    colorbar = true,
)

# Save figure
fig_dir = joinpath(@__DIR__, "..", "figures")
mkpath(fig_dir)
png_path = joinpath(fig_dir, "gom_hr_eta_day10.png")

@info "Saving figure to" png_path
savefig(plt, png_path)
@info "Done."
