#!/usr/bin/env julia

using JLD2
using NCDatasets
using Plots

# ---------------------------------------------------------------
# Paths
# ---------------------------------------------------------------
snap_file = joinpath(@__DIR__, "..", "runs", "gom_hr_output", "gom_hr_10days_snapshot.jld2")
grid_file = joinpath(@__DIR__, "..", "runs", "gom_hr_grid.nc")

@info "Opening snapshot" snap_file

# ---------------------------------------------------------------
# Read η from snapshot
# ---------------------------------------------------------------
η = jldopen(snap_file, "r") do f
    f["η"]
end

@info "η size" size(η)

# η has shape (Nx, Ny, 1); drop the vertical dimension
η2d = dropdims(η, dims = 3)
@info "η2d size" size(η2d)

# Plots.heatmap(x, y, z) expects z to have size (length(y), length(x))
η_for_plot = permutedims(η2d, (2, 1))
@info "η_for_plot size" size(η_for_plot)

Nx, Ny = size(η2d)

# ---------------------------------------------------------------
# Read lon/lat from grid file
# ---------------------------------------------------------------
@info "Opening grid file" grid_file

ds = NCDataset(grid_file, "r")

has_lon = haskey(ds, "lon")
has_lat = haskey(ds, "lat")

lon = has_lon ? vec(ds["lon"][:]) : collect(1:Nx)
lat = has_lat ? vec(ds["lat"][:]) : collect(1:Ny)

close(ds)

if has_lon
    @info "Using lon from grid file" size(lon)
else
    @warn "No lon in grid file; using 1:Nx"
end

if has_lat
    @info "Using lat from grid file" size(lat)
else
    @warn "No lat in grid file; using 1:Ny"
end

@info "lon length = $(length(lon)), lat length = $(length(lat))"

# Safety check: make sure sizes match the data
if length(lon) != Nx || length(lat) != Ny
    @warn "lon/lat lengths do not match η2d size; using index coordinates instead"
    lon = collect(1:Nx)
    lat = collect(1:Ny)
end

# ---------------------------------------------------------------
# Plot
# ---------------------------------------------------------------
default(size = (600, 400), dpi = 150, framestyle = :box)

p = heatmap(
    lon,
    lat,
    η_for_plot;
    xlabel = "longitude (°E)",
    ylabel = "latitude (°N)",
    title = "GoM surface η (day 10 snapshot, HYCOM init)",
    colorbar_title = "η [m]",
    aspect_ratio = :equal,
)

# ---------------------------------------------------------------
# Save figure
# ---------------------------------------------------------------
fig_dir = joinpath(@__DIR__, "..", "figures")
mkpath(fig_dir)
png_path = joinpath(fig_dir, "gom_hr_eta_hycom_init_day10.png")

@info "Saving figure to" png_path
savefig(p, png_path)
@info "Done."
