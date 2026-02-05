using JLD2
using Plots

# Set a cleaner, professional default style
default(
    framestyle = :box,
    grid       = false,
    guidefont  = font(12),
    tickfont   = font(10),
    legendfont = font(10),
    size       = (900, 700),
    dpi        = 300,
)

# Path to snapshot
snapshot_file = joinpath(@__DIR__, "..", "runs", "gom_hr_output", "gom_hr_10days_snapshot.jld2")

@info "Opening snapshot" snapshot_file
data = jldopen(snapshot_file, "r") do f
    (; η = f["η"], T = f["T"], S = f["S"])
end

T = data.T       # size (Nx, Ny, Nz)
@info "T size" size(T)

# Take surface level: assuming vertical index end is surface
T_surf = T[:, :, end]   # or T[:, :, 1] depending on orientation

# Professional-looking SST-style heatmap
plt = heatmap(
    T_surf',
    aspect_ratio   = :equal,
    xlabel         = "x index",
    ylabel         = "y index",
    title          = "GoM high-res surface T (day 10 snapshot)",
    titlefont      = font(14),
    c              = :thermal,      # nice sequential colormap for temperature
    colorbar       = true,
    colorbar_title = "Temperature",
)

fig_dir = joinpath(@__DIR__, "..", "figures")
mkpath(fig_dir)
png_path = joinpath(fig_dir, "gom_hr_sst_day10.png")

@info "Saving figure to" png_path
savefig(plt, png_path)
@info "Done."
