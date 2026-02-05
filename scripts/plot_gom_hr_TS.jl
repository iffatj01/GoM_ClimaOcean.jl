#!/usr/bin/env julia
#
# plot_gom_hr_TS.jl
#
# Physical surface temperature & salinity maps (and optional anomalies)
# using GMT, in the same GoM map style as the η figure.

using JLD2
using NCDatasets
using GMT
using Statistics

# ---------------------------------------------------------------
# 1. File paths
# ---------------------------------------------------------------
snapshot_file = joinpath(@__DIR__, "..", "runs", "gom_hr_output", "gom_hr_60days_snapshot_hycom.jld2")
grid_file     = joinpath(@__DIR__, "..", "runs", "gom_hr_grid.nc")
fig_dir       = joinpath(@__DIR__, "..", "figures")
isdir(fig_dir) || mkpath(fig_dir)

@info "Opening snapshot" snapshot_file
data = jldopen(snapshot_file, "r") do f
    (; T = f["T"], S = f["S"])
end

T_raw = data.T         # (Nx, Ny, Nz)
S_raw = data.S         # (Nx, Ny, Nz)
@info "T_raw size" size(T_raw)
@info "S_raw size" size(S_raw)

# ---------------------------------------------------------------
# 2. Take surface level and mask land
# ---------------------------------------------------------------
# If vertical index is reversed in your output, change `end` to `1`.
T_surf = T_raw[:, :, end]   # 2-D already; no dropdims
S_surf = S_raw[:, :, end]

# Ocean mask: assume land is NaN already; otherwise you can change this
ocean_mask = .!isnan.(T_surf) .& .!isnan.(S_surf)

T_surf_mask = float(copy(T_surf))
S_surf_mask = float(copy(S_surf))
T_surf_mask[.!ocean_mask] .= NaN
S_surf_mask[.!ocean_mask] .= NaN

Tmin = minimum(T_surf_mask[ocean_mask])
Tmax = maximum(T_surf_mask[ocean_mask])
Smin = minimum(S_surf_mask[ocean_mask])
Smax = maximum(S_surf_mask[ocean_mask])
@info "T_surf ocean-only min/max" Tmin Tmax
@info "S_surf ocean-only min/max" Smin Smax

# Anomalies (optional – we still compute them, in case you want the plots)
Tmean = mean(T_surf_mask[ocean_mask])
Smean = mean(S_surf_mask[ocean_mask])
@info "Tmean, Smean" Tmean Smean

T_anom = T_surf_mask .- Tmean
S_anom = S_surf_mask .- Smean

# ---------------------------------------------------------------
# 3. Lon / lat from grid file
# ---------------------------------------------------------------
@info "Opening grid file" grid_file

# Fix the scoping issue - return values from the do block
lon, lat = NCDataset(grid_file, "r") do ds
    lon_data = vec(ds["lon"][:])
    lat_data = vec(ds["lat"][:])
    return lon_data, lat_data
end

@info "lon range" minimum(lon) maximum(lon)
@info "lat range" minimum(lat) maximum(lat)

region = (minimum(lon), maximum(lon), minimum(lat), maximum(lat))

# Helper: convert field (x,y) to GMT grid (y,x) with lon/lat axes
function to_gmtgrid(field_xy::AbstractMatrix, lon::AbstractVector, lat::AbstractVector)
    field_yx = permutedims(field_xy, (2, 1))   # (Ny, Nx) expected by GMT
    GMT.mat2grid(field_yx, x = lon, y = lat)
end

# ---------------------------------------------------------------
# 4. Generic plotting helper
# ---------------------------------------------------------------
function plot_field(field_xy;
                    lon,
                    lat,
                    clim::Tuple{<:Real,<:Real},
                    cmap,
                    cb_label::String,
                    title::String,
                    png_name::String)

    G    = to_gmtgrid(field_xy, lon, lat)
    cpt  = makecpt(cmap = cmap, range = clim)

    grdimage(
        G,
        region   = region,
        proj     = "M16c",
        cmap     = cpt,
        frame    = (axes = :WSen, title = title),
        coast    = (shore = :thin, land = :lightgray, water = :white),
        colorbar = true,
        fmt      = :png,
        savefig  = png_name,
    )

    @info "Saved" png_name
end

# ---------------------------------------------------------------
# 5. Physical T and S maps: blue–white–red, fixed ranges
# ---------------------------------------------------------------
T_clim = (18.0, 22.0)    # °C
S_clim = (34.0, 36.0)    # psu

plot_field(
    T_surf_mask;
    lon      = lon,
    lat      = lat,
    clim     = T_clim,
    cmap     = :polar,  # blue–white–red  (cold–neutral–warm)
    cb_label = "T [°C]",
    title    = "GoM surface temperature (day 60, HYCOM init)",
    png_name = joinpath(fig_dir, "gom_hr_T_surface_day60_physical_GMT.png"),
)

plot_field(
    S_surf_mask;
    lon      = lon,
    lat      = lat,
    clim     = S_clim,
    cmap     = :polar,
    cb_label = "S [psu]",
    title    = "GoM surface salinity (day 60, HYCOM init)",
    png_name = joinpath(fig_dir, "gom_hr_S_surface_day60_physical_GMT.png"),
)

# ---------------------------------------------------------------
# 6. OPTIONAL: anomaly plots with tight, symmetric colorbars
#     (red = positive anomaly, blue = negative anomaly)
# ---------------------------------------------------------------
T_anom_max = maximum(abs, T_anom[ocean_mask])
S_anom_max = maximum(abs, S_anom[ocean_mask])

plot_field(
    T_anom;
    lon      = lon,
    lat      = lat,
    clim     = (-T_anom_max, T_anom_max),
    cmap     = :vik,    # nice symmetric blue–red
    cb_label = "T' [°C]",
    title    = "GoM surface temperature anomaly (day 60)",
    png_name = joinpath(fig_dir, "gom_hr_T_anom_surface_day60_GMT.png"),
)

plot_field(
    S_anom;
    lon      = lon,
    lat      = lat,
    clim     = (-S_anom_max, S_anom_max),
    cmap     = :vik,
    cb_label = "S' [psu]",
    title    = "GoM surface salinity anomaly (day 60)",
    png_name = joinpath(fig_dir, "gom_hr_S_anom_surface_day60_GMT.png"),
)