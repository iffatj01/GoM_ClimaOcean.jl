#!/usr/bin/env julia

# Professional 1-day GoM plotting script
#
# - Reads:  runs/gom_hr_output/gom_hr_1day_snapshot_hycom.jld2
# - Rebuilds a LatitudeLongitudeGrid with correct lon/lat
# - Uses ClimaOcean bathymetry for coastline / land mask
# - Produces:
#     figures/gom_hr_1day_eta_pro.png
#     figures/gom_hr_1day_Tsurf_pro.png

using JLD2
using Plots
using Statistics

using Oceananigans
using Oceananigans.Fields: interior
using Oceananigans.Grids: LatitudeLongitudeGrid
import ClimaOcean

# ------------------------------------------------------------------ #
# 1. Load snapshot
# ------------------------------------------------------------------ #

snapshot_file = joinpath(@__DIR__, "..", "runs", "gom_hr_output",
                         "gom_hr_1day_snapshot_hycom.jld2")

@info "Opening 1-day snapshot" snapshot_file

data = jldopen(snapshot_file, "r") do f
    η = read(f, "η")   # (Nx, Ny, 1)
    T = read(f, "T")   # (Nx, Ny, Nz)
    S = read(f, "S")   # (Nx, Ny, Nz)
    (; η, T, S)
end

η = data.η
T = data.T
S = data.S

# η: remove singleton vertical dimension → (Nx, Ny)
η2d = ndims(η) == 3 ? dropdims(η; dims = 3) : η

Nx, Ny = size(η2d)
_, _, Nz = size(T)

@info "Field sizes from snapshot" Nx = Nx Ny = Ny Nz = Nz

# Surface temperature (top level assumed last index)
T_surf = T[:, :, end]

# ------------------------------------------------------------------ #
# 2. Rebuild lon/lat grid + bathymetry for coastline
# ------------------------------------------------------------------ #

# Must match your gom_config_hr.jl domain exactly
lon_min, lon_max = -98.0, -80.0
lat_min, lat_max =  18.0,  31.0

# Longitude / latitude coordinates (centered on cell centers)
lon = range(lon_min, lon_max; length = Nx)
lat = range(lat_min, lat_max; length = Ny)

# Rebuild a CPU grid with same geometry to get bathymetry
base_grid = LatitudeLongitudeGrid(CPU();
    size      = (Nx, Ny, Nz),
    longitude = (lon_min, lon_max),
    latitude  = (lat_min, lat_max),
    z         = (-5000.0, 0.0),
)

@info "Regridding bathymetry from ClimaOcean..."
bathy_field = ClimaOcean.regrid_bathymetry(base_grid)

# Bathymetry as a plain Array, drop z-dimension → (Nx, Ny)
bathy_array = Array(interior(bathy_field))         # (Nx, Ny, 1)
bathy2d     = ndims(bathy_array) == 3 ?
              dropdims(bathy_array; dims = 3) :
              bathy_array                           # (Nx, Ny)

@info "Bathymetry stats" minimum = minimum(bathy2d) maximum = maximum(bathy2d)

# Land mask: positive or zero bathymetry is land, negative is ocean
land_mask = bathy2d .>= 0.0

# Mask η and T over land for cleaner plots
η_masked  = copy(η2d)
T_s_masked = copy(T_surf)

η_masked[land_mask]   .= NaN
T_s_masked[land_mask] .= NaN

# ------------------------------------------------------------------ #
# 3. Global plotting style
# ------------------------------------------------------------------ #

default(
    framestyle = :box,
    guidefont  = font(12, "Helvetica"),
    tickfont   = font(10, "Helvetica"),
    titlefont  = font(14, "Helvetica", :bold),
    legendfont = font(10, "Helvetica"),
    dpi        = 200,
)

fig_dir = joinpath(@__DIR__, "..", "figures")
mkpath(fig_dir)

# ------------------------------------------------------------------ #
# 4. Plot free surface η
# ------------------------------------------------------------------ #

# Plots.jl expects z size (length(lat), length(lon)) = (Ny, Nx)
η_for_plot = η_masked'        # (Ny, Nx), so (lat, lon)
bathy_for_plot = bathy2d'     # same orientation

η_min = minimum(skipmissing(vec(η_for_plot)))
η_max = maximum(skipmissing(vec(η_for_plot)))

plt_eta = heatmap(
    lon, lat, η_for_plot;
    aspect_ratio   = :equal,
    xlabel         = "Longitude [°E]",
    ylabel         = "Latitude [°N]",
    title          = "GoM free surface η after 1 day (HYCOM init)",
    colorbar_title = "η [m]",
    clims          = (η_min, η_max),
)

# Add coastline as 0 m bathymetry contour (land/ocean boundary)
contour!(
    lon, lat, bathy_for_plot;
    levels    = [0.0],
    linewidth = 1.5,
    color     = :black,
    label     = "",
)

eta_png = joinpath(fig_dir, "gom_hr_1day_eta_pro.png")
savefig(plt_eta, eta_png)
@info "Saved η figure with coastline" eta_png

# ------------------------------------------------------------------ #
# 5. Plot surface temperature T_surf
# ------------------------------------------------------------------ #

T_for_plot = T_s_masked'  # (Ny, Nx)

T_min = minimum(skipmissing(vec(T_for_plot)))
T_max = maximum(skipmissing(vec(T_for_plot)))

plt_Ts = heatmap(
    lon, lat, T_for_plot;
    aspect_ratio   = :equal,
    xlabel         = "Longitude [°E]",
    ylabel         = "Latitude [°N]",
    title          = "GoM surface temperature after 1 day (HYCOM init)",
    colorbar_title = "T [°C]",
    clims          = (T_min, T_max),
)

# Coastline overlay again
contour!(
    lon, lat, bathy_for_plot;
    levels    = [0.0],
    linewidth = 1.5,
    color     = :black,
    label     = "",
)

Ts_png = joinpath(fig_dir, "gom_hr_1day_Tsurf_pro.png")
savefig(plt_Ts, Ts_png)
@info "Saved surface T figure with coastline" Ts_png

@info "All professional plots done."
