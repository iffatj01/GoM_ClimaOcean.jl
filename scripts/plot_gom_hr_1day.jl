#!/usr/bin/env julia

# Professional 1-day GoM plotting
# - Uses lon/lat axes
# - Masks land using ClimaOcean bathymetry
# - Adds coastline outline for correct GoM bowl shape
# - Symmetric color scale for η
# - Bathymetry panel for the basin shape

using JLD2
using Plots
using Plots.PlotMeasures
using Statistics

using Oceananigans
using Oceananigans.Fields: interior
using Oceananigans.Grids: LatitudeLongitudeGrid
import ClimaOcean

# ------------------------------------------------------------------ #
# Helpers
# ------------------------------------------------------------------ #

finite_extrema(A) = begin
    vals = filter(isfinite, vec(A))
    if isempty(vals)
        return (0.0, 0.0)
    end
    return (minimum(vals), maximum(vals))
end

finite_maxabs(A) = begin
    vals = filter(isfinite, vec(A))
    if isempty(vals)
        return 0.0
    end
    return maximum(abs, vals)
end

nan_pct(A) = begin
    n_total = length(A)
    n_finite = count(isfinite, A)
    return 100 * (1 - n_finite / n_total)
end

function log_field_stats(name, A; expected_min = nothing, expected_max = nothing)
    vals = filter(isfinite, vec(A))
    if isempty(vals)
        @warn "$name has no finite values"
        return
    end
    @info "$name stats" min = minimum(vals) max = maximum(vals) nan_pct = nan_pct(A)
    if expected_min !== nothing && minimum(vals) < expected_min
        @warn "$name below expected minimum" expected_min
    end
    if expected_max !== nothing && maximum(vals) > expected_max
        @warn "$name above expected maximum" expected_max
    end
end

# ------------------------------------------------------------------ #
# 1) Load snapshot
# ------------------------------------------------------------------ #

snapshot_file = joinpath(@__DIR__, "..", "runs", "gom_hr_output",
                         "gom_hr_1day_init_snapshot_hycom.jld2")

@info "Opening 1-day snapshot" snapshot_file

data = jldopen(snapshot_file, "r") do f
    η = read(f, "η")   # (Nx, Ny, 1)
    T = read(f, "T")   # (Nx, Ny, Nz)
    S = read(f, "S")   # (Nx, Ny, Nz)
    (; η, T, S)
end

η = data.η
T = data.T

# η: remove singleton vertical dimension → (Nx, Ny)
η2d = ndims(η) == 3 ? dropdims(η; dims = 3) : η

Nx, Ny = size(η2d)
_, _, Nz = size(T)

@info "Field sizes from snapshot" Nx = Nx Ny = Ny Nz = Nz

# Surface temperature (top level assumed last index)
T_surf = T[:, :, end]

# ------------------------------------------------------------------ #
# 2) Rebuild lon/lat grid + bathymetry for coastline
# ------------------------------------------------------------------ #

# Must match gom_config_hr.jl domain
lon_min, lon_max = -98.0, -80.0
lat_min, lat_max =  18.0,  31.0

lon = range(lon_min, lon_max; length = Nx)
lat = range(lat_min, lat_max; length = Ny)

# Rebuild a CPU grid to get bathymetry
base_grid = LatitudeLongitudeGrid(CPU();
    size      = (Nx, Ny, Nz),
    longitude = (lon_min, lon_max),
    latitude  = (lat_min, lat_max),
    z         = (-5000.0, 0.0),
)

@info "Regridding bathymetry from ClimaOcean..."
bathy_field = ClimaOcean.regrid_bathymetry(base_grid)

# Bathymetry as Array, drop z-dimension → (Nx, Ny)
bathy_array = Array(interior(bathy_field))         # (Nx, Ny, 1)
bathy2d     = ndims(bathy_array) == 3 ?
              dropdims(bathy_array; dims = 3) :
              bathy_array

# Land mask: positive or zero bathymetry is land, negative is ocean
land_mask = bathy2d .>= 0.0

# Mask η and T over land for cleaner plots
η_masked   = copy(η2d)
T_masked   = copy(T_surf)
η_masked[land_mask] .= NaN
T_masked[land_mask] .= NaN

log_field_stats("Surface T (raw)", T_surf; expected_min = -2.0, expected_max = 40.0)
log_field_stats("Surface T (masked)", T_masked; expected_min = -2.0, expected_max = 40.0)
log_field_stats("Free surface η (masked)", η_masked)
log_field_stats("Bathymetry", bathy2d; expected_min = -7000.0, expected_max = 100.0)

# ------------------------------------------------------------------ #
# 3) Plot styling + output directory
# ------------------------------------------------------------------ #

default(
    framestyle = :box,
    guidefont  = font(12, "Helvetica"),
    tickfont   = font(10, "Helvetica"),
    titlefont  = font(12, "Helvetica", :bold),
    legendfont = font(10, "Helvetica"),
    dpi        = 220,
    size       = (900, 700),
    left_margin   = 8mm,
    right_margin  = 10mm,
    top_margin    = 10mm,
    bottom_margin = 8mm,
)

fig_dir = joinpath(@__DIR__, "..", "figures")
mkpath(fig_dir)

# ------------------------------------------------------------------ #
# 4) Free surface η (symmetric color scale)
# ------------------------------------------------------------------ #

η_for_plot     = η_masked'    # (Ny, Nx) -> (lat, lon)
bathy_for_plot = bathy2d'     # same orientation

η_maxabs = finite_maxabs(η_for_plot)
η_clims  = (-η_maxabs, η_maxabs)

plt_eta = heatmap(
    lon, lat, η_for_plot;
    aspect_ratio   = :equal,
    xlabel         = "Longitude [°W]",
    ylabel         = "Latitude [°N]",
    title          = "GoM free surface η after 0 day (HYCOM init)",
    colorbar_title = "η [m]",
    clims          = η_clims,
    color          = cgrad(:balance),
    nan_color      = :white,
)

# Coastline from 0 m bathymetry contour
contour!(
    lon, lat, bathy_for_plot;
    levels    = [0.0],
    linewidth = 1.5,
    color     = :black,
    label     = "",
)

eta_png = joinpath(fig_dir, "gom_hr_1day_etainit.png")
savefig(plt_eta, eta_png)
@info "Saved η figure with coastline" eta_png

# ------------------------------------------------------------------ #
# 5) Surface temperature T_surf
# ------------------------------------------------------------------ #

T_for_plot = T_masked'
T_min, T_max = finite_extrema(T_for_plot)

plt_Ts = heatmap(
    lon, lat, T_for_plot;
    aspect_ratio   = :equal,
    xlabel         = "Longitude [°W]",
    ylabel         = "Latitude [°N]",
    title          = "GoM surface temperature after 0 day (HYCOM init)",
    colorbar_title = "T [°C]",
    clims          = (T_min, T_max),
    color          = cgrad(:thermal),
    nan_color      = :white,
)

contour!(
    lon, lat, bathy_for_plot;
    levels    = [0.0],
    linewidth = 1.5,
    color     = :black,
    label     = "",
)

Ts_png = joinpath(fig_dir, "gom_hr_1day_Tsurfinit.png")
savefig(plt_Ts, Ts_png)
@info "Saved surface T figure with coastline" Ts_png

# ------------------------------------------------------------------ #
# 6) Bathymetry panel (GoM bowl shape)
# ------------------------------------------------------------------ #

bathy_masked = copy(bathy2d)
bathy_masked[bathy_masked .>= 0.0] .= NaN
bathy_plot = bathy_masked'

bathy_min, bathy_max = finite_extrema(bathy_plot)

plt_bathy = heatmap(
    lon, lat, bathy_plot;
    aspect_ratio   = :equal,
    xlabel         = "Longitude [°W]",
    ylabel         = "Latitude [°N]",
    title          = "GoM bathymetry (ClimaOcean)",
    colorbar_title = "Depth [m]",
    clims          = (bathy_min, bathy_max),
    color          = cgrad(:deep),
    nan_color      = :white,
)

contour!(
    lon, lat, bathy_for_plot;
    levels    = [0.0],
    linewidth = 1.5,
    color     = :black,
    label     = "",
)

bathy_png = joinpath(fig_dir, "gom_hr_1day_bathymetrynew.png")
savefig(plt_bathy, bathy_png)
@info "Saved bathymetry figure with coastline" bathy_png

@info "All professional plots done."
