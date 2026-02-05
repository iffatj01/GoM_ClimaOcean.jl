#!/usr/bin/env julia

# Animate 1-day GoM outputs from JLD2OutputWriter
# Produces:
#   figures/gom_hr_1day_eta.gif
#   figures/gom_hr_1day_Tsurf.gif

ENV["GKSwstype"] = "100"  # headless-friendly

using JLD2
using Plots
using Plots.PlotMeasures
using Printf

using Oceananigans
using Oceananigans.Fields: interior
using Oceananigans.Grids: LatitudeLongitudeGrid
import ClimaOcean

finite_extrema(A) = begin
    vals = filter(isfinite, vec(A))
    isempty(vals) ? (0.0, 0.0) : (minimum(vals), maximum(vals))
end

finite_maxabs(A) = begin
    vals = filter(isfinite, vec(A))
    isempty(vals) ? 0.0 : maximum(abs, vals)
end

function pick_time_dim(sz, time_len)
    if time_len === nothing
        return length(sz)
    end
    idx = findfirst(==(time_len), sz)
    return idx === nothing ? length(sz) : idx
end

function eta_frame(η, t_idx; time_dim)
    A = selectdim(η, time_dim, t_idx)
    return dropdims(A; dims = findall(==(1), size(A)))
end

function T_surface_frame(T, t_idx; time_dim, z_dim)
    Tt = selectdim(T, time_dim, t_idx)
    z_dim_after = z_dim > time_dim ? z_dim - 1 : z_dim
    Ts = selectdim(Tt, z_dim_after, size(T, z_dim))
    return dropdims(Ts; dims = findall(==(1), size(Ts)))
end

# ------------------------------------------------------------------ #
# Paths
# ------------------------------------------------------------------ #

output_dir = joinpath(@__DIR__, "..", "runs", "gom_hr_output")
fig_dir = joinpath(@__DIR__, "..", "figures")
mkpath(fig_dir)

files = filter(f -> startswith(f, "gom_hr_1day_timeseries") && endswith(f, ".jld2"),
               readdir(output_dir))
isempty(files) && error("No timeseries file found in $output_dir")
jld2_path = joinpath(output_dir, files[1])

@info "Opening timeseries file" jld2_path
file = jldopen(jld2_path, "r")

# JLD2Writer stores time series under "timeseries" as groups per time
ts_group = file["timeseries"]
η_group = ts_group["η"]
T_group = ts_group["T"]

function time_keys(g)
    keys_num = Float64[]
    keys_str = String[]
    for k in keys(g)
        k == "serialized" && continue
        try
            push!(keys_num, parse(Float64, k))
            push!(keys_str, k)
        catch
        end
    end
    order = sortperm(keys_num)
    return keys_str[order], keys_num[order]
end

η_keys, η_iters = time_keys(η_group)
T_keys, _ = time_keys(T_group)

# JLD2Writer stores times under "timeseries/t/<iter>" while field groups use iter keys.
# Prefer true model times when available.
times = Float64[]
if haskey(ts_group, "t")
    t_group = ts_group["t"]
    t_keys, _ = time_keys(t_group)
    times = [Float64(t_group[k]) for k in t_keys]
else
    times = η_iters
end

time_len = length(η_keys)

# Determine horizontal dimensions from η
# Use first time slice to infer sizes (may include halos)
η0 = Array(η_group[η_keys[1]])
T0 = Array(T_group[T_keys[1]])

η_sz = size(η0)
T_sz = size(T0)

Nx = η_sz[1]
Ny = η_sz[2]
Nz = T_sz[3]

# ------------------------------------------------------------------ #
# Rebuild lon/lat grid + bathymetry for coastline
# ------------------------------------------------------------------ #

lon_min, lon_max = -98.0, -80.0
lat_min, lat_max =  18.0,  31.0

lon = range(lon_min, lon_max; length = 480)
lat = range(lat_min, lat_max; length = 360)

base_grid = LatitudeLongitudeGrid(CPU();
    size      = (length(lon), length(lat), 50),
    longitude = (lon_min, lon_max),
    latitude  = (lat_min, lat_max),
    z         = (-5000.0, 0.0),
)

@info "Regridding bathymetry from ClimaOcean..."
bathy_field = ClimaOcean.regrid_bathymetry(base_grid)
bathy_array = Array(interior(bathy_field))
bathy2d     = ndims(bathy_array) == 3 ? dropdims(bathy_array; dims = 3) : bathy_array
land_mask = bathy2d .>= 0.0
bathy_for_plot = bathy2d'

# Precompute color limits
η_maxabs = finite_maxabs(η0)
η_clims = (-η_maxabs, η_maxabs)

T_min, T_max = finite_extrema(T0)

default(
    framestyle = :box,
    guidefont  = font(12, "DejaVu Sans"),
    tickfont   = font(10, "DejaVu Sans"),
    titlefont  = font(12, "DejaVu Sans", :bold),
    dpi        = 220,
    size       = (900, 700),
    left_margin   = 8mm,
    right_margin  = 10mm,
    top_margin    = 10mm,
    bottom_margin = 8mm,
)

# ------------------------------------------------------------------ #
# Animate η
# ------------------------------------------------------------------ #

function trim_halos(A, Nx, Ny, Nz=nothing)
    sx, sy = size(A, 1), size(A, 2)
    hx = max(0, Int((sx - Nx) ÷ 2))
    hy = max(0, Int((sy - Ny) ÷ 2))
    if ndims(A) == 2
        return A[(1+hx):(hx+Nx), (1+hy):(hy+Ny)]
    end
    Axy = A[(1+hx):(hx+Nx), (1+hy):(hy+Ny), :]
    if Nz === nothing
        return Axy
    end
    sz = size(A, 3)
    hz = max(0, Int((sz - Nz) ÷ 2))
    return Axy[:, :, (1+hz):(hz+Nz)]
end

anim_eta = @animate for ti in 1:time_len
    η_raw = Array(η_group[η_keys[ti]])
    η_frame = trim_halos(η_raw, length(lon), length(lat))
    if ndims(η_frame) == 3 && size(η_frame, 3) == 1
        η_frame = dropdims(η_frame; dims = 3)
    end
    η_frame[land_mask] .= NaN
    t_label = isempty(times) ? "t = $ti" : @sprintf("t = %.2f days", times[ti] / 86400)

    plt = heatmap(
        lon, lat, η_frame';
        aspect_ratio   = :equal,
        xlabel         = "Longitude [°W]",
        ylabel         = "Latitude [°N]",
        title          = "GoM free surface η ($t_label)",
        colorbar_title = "η [m]",
        clims          = η_clims,
        color          = cgrad(:balance),
        nan_color      = :white,
    )
    contour!(
        lon, lat, bathy_for_plot;
        levels    = [0.0],
        linewidth = 1.2,
        color     = :black,
        label     = "",
    )
    plt
end

eta_gif = joinpath(fig_dir, "gom_hr_1day_eta.gif")
gif(anim_eta, eta_gif; fps = 8)
@info "Saved η animation" eta_gif

# ------------------------------------------------------------------ #
# Animate surface T
# ------------------------------------------------------------------ #

anim_T = @animate for ti in 1:time_len
    T_raw = Array(T_group[T_keys[ti]])
    T_trim = trim_halos(T_raw, length(lon), length(lat), 50)
    T_frame = T_trim[:, :, end]
    T_frame[land_mask] .= NaN
    t_label = isempty(times) ? "t = $ti" : @sprintf("t = %.2f days", times[ti] / 86400)

    plt = heatmap(
        lon, lat, T_frame';
        aspect_ratio   = :equal,
        xlabel         = "Longitude [°W]",
        ylabel         = "Latitude [°N]",
        title          = "GoM surface temperature ($t_label)",
        colorbar_title = "T [°C]",
        clims          = (T_min, T_max),
        color          = cgrad(:thermal),
        nan_color      = :white,
    )
    contour!(
        lon, lat, bathy_for_plot;
        levels    = [0.0],
        linewidth = 1.2,
        color     = :black,
        label     = "",
    )
    plt
end

T_gif = joinpath(fig_dir, "gom_hr_1day_Tsurf.gif")
gif(anim_T, T_gif; fps = 8)
@info "Saved surface T animation" T_gif

close(file)
