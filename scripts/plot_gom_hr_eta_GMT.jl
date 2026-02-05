#!/usr/bin/env julia

# scripts/plot_gom_hr_eta_GMT.jl
#
# Plot GoM free-surface height η on a proper map using GMT.jl.
#
# Output: figures/gom_hr_eta_GMT_day10.png

using JLD2
using GMT
using NCDatasets
using Printf

# ---------------------------------------------------------------------------
# 1. Files
# ---------------------------------------------------------------------------

snap_file = joinpath(@__DIR__, "..", "runs", "gom_hr_output",
                     "gom_hr_10days_snapshot.jld2")
grid_file = joinpath(@__DIR__, "..", "runs", "gom_hr_grid.nc")

fig_dir   = joinpath(@__DIR__, "..", "figures")
png_path  = joinpath(fig_dir, "gom_hr_eta_GMT_day10.png")

mkpath(fig_dir)

@info "Opening snapshot" snap_file

η_raw = jldopen(snap_file, "r") do f
    f["η"]
end

@info "η_raw size" size(η_raw)

# η_raw is (Nx, Ny, 1) = (480, 360, 1).  Drop the singleton 3rd dim.
if ndims(η_raw) == 3 && size(η_raw, 3) == 1
    @info "η_raw has 3 dims; dropping singleton 3rd dim"
    η2d = dropdims(η_raw; dims = 3)        # (Nx, Ny)
elseif ndims(η_raw) == 2
    η2d = η_raw
else
    error("Unexpected η array size: $(size(η_raw))")
end

@info "η2d size" size(η2d)                 # (Nx, Ny) = (480, 360)

# GMT expects matrix with first dim = y (lat), second dim = x (lon),
# so transpose to (Ny, Nx) = (360, 480).
η_for_plot = permutedims(η2d, (2, 1))
@info "η_for_plot size" size(η_for_plot)

# ---------------------------------------------------------------------------
# 2. Grid coordinates (lon, lat)
# ---------------------------------------------------------------------------

@info "Opening grid file" grid_file

# Read lon and lat from the NCDataset - use a function that returns values
lon, lat = NCDataset(grid_file, "r") do ds
    @info "Available variables in NetCDF file:" keys(ds)
    
    # Read the variables and return them as a tuple
    lon_data = ds["lon"][:]
    lat_data = ds["lat"][:]
    
    return lon_data, lat_data
end

@info "lon range" minimum(lon) maximum(lon)
@info "lat range" minimum(lat) maximum(lat)

Nx = length(lon)
Ny = length(lat)
@info "Coordinate lengths" Nx Ny

if size(η_for_plot, 2) != Nx || size(η_for_plot, 1) != Ny
    error("Size mismatch: η_for_plot = $(size(η_for_plot)), " *
          "lon length = $Nx, lat length = $Ny")
end

# Region for GMT (lon_min, lon_max, lat_min, lat_max)
region = (minimum(lon), maximum(lon), minimum(lat), maximum(lat))

# ---------------------------------------------------------------------------
# 3. Build GMT grid from η
# ---------------------------------------------------------------------------

G = mat2grid(η_for_plot, x = lon, y = lat)

# Choose a projection that gives a nice GoM shape.
# Mercator centered at (lon=-90, lat=25), 10 cm map width:
proj_str = "M-90/25/10c"

# ---------------------------------------------------------------------------
# 4. Plot with GMT
# ---------------------------------------------------------------------------

@info "Saving figure to" png_path

# Create the base map with the data
grdimage(
    G,
    region = region,
    proj   = proj_str,
    frame  = (axes="WSen", annot=:auto, grid=:auto),
    cmap   = :vik,
    colorbar = true,
    title  = "GoM surface eta (day 10, HYCOM init)",
)

# Overlay coastlines and land mask
coast!(
    region = region,
    proj   = proj_str,
    land   = :lightgray,
    shore  = :thin,
    fmt    = :png,
    savefig = png_path,
)

@info "Done. Figure saved to: $png_path"