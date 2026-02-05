#!/usr/bin/env julia

##############################################################################
# plothycom.jl
#
# Plot model free-surface height η from gom_hr_10days_snapshot.jld2
# using x/y coordinates from gom_hr_grid.nc.
##############################################################################

using JLD2
using NCDatasets
using Plots

# --------------------------------------------------------------------------- #
# 0. Plot style
# --------------------------------------------------------------------------- #
default(
    framestyle = :box,
    grid       = false,
    guidefont  = font(12),
    tickfont   = font(10),
    legendfont = font(10),
    size       = (900, 700),
    dpi        = 300,
)

# --------------------------------------------------------------------------- #
# 1. File paths
# --------------------------------------------------------------------------- #
snapshot_file = joinpath(@__DIR__, "..", "runs", "gom_hr_output", "gom_hr_10days_snapshot.jld2")
grid_file     = joinpath(@__DIR__, "..", "runs", "gom_hr_grid.nc")

@info "Opening snapshot" snapshot_file

# --------------------------------------------------------------------------- #
# 2. Load η from JLD2
# --------------------------------------------------------------------------- #
η_raw = jldopen(snapshot_file, "r") do f
    f["η"]
end

@info "η_raw size" size(η_raw)

# Make η2d robustly 2D
η2d = begin
    nd = ndims(η_raw)

    if nd == 3
        # Find singleton dims (size == 1)
        single = findall(d -> size(η_raw, d) == 1, 1:3)

        if length(single) == 1
            dropdims(η_raw; dims = single[1])
        elseif length(single) == 0
            @warn "No singleton dims in η_raw; taking slice η_raw[:, :, 1]"
            η_raw[:, :, 1]
        else
            dropdims(η_raw; dims = Tuple(single))
        end

    elseif nd == 2
        η_raw
    else
        error("Unexpected η_raw dimensions: $(size(η_raw))")
    end
end

@info "η2d size" size(η2d)

# --------------------------------------------------------------------------- #
# 3. Read horizontal coordinates from grid NetCDF (no do-block; very explicit)
# --------------------------------------------------------------------------- #
@info "Opening grid file" grid_file
ds = NCDataset(grid_file, "r")

# ----- X / longitude-like coordinate -----
if haskey(ds, "lon")
    lon = ds["lon"][:]
    @info "Found lon in grid file" size = size(lon)
elseif haskey(ds, "xC")
    xC = ds["xC"][:]
    if ndims(xC) == 2
        lon = xC[1, :]              # (Nx,)
    else
        lon = xC[:]
    end
    @info "Using xC as x coordinate" size = size(lon)
else
    close(ds)
    error("Cannot find 'lon' or 'xC' in $grid_file")
end

# ----- Y / latitude-like coordinate -----
if haskey(ds, "lat")
    lat = ds["lat"][:]
    @info "Found lat in grid file" size = size(lat)
elseif haskey(ds, "yC")
    yC = ds["yC"][:]
    if ndims(yC) == 2
        lat = yC[:, 1]              # (Ny,)
    else
        lat = yC[:]
    end
    @info "Using yC as y coordinate" size = size(lat)
else
    close(ds)
    error("Cannot find 'lat' or 'yC' in $grid_file")
end

close(ds)

@info "lon type" typeof(lon)
@info "lat type" typeof(lat)

Nx_target = length(lon)
Ny_target = length(lat)

@info "Nx_target = length(lon)" Nx_target
@info "Ny_target = length(lat)" Ny_target

# --------------------------------------------------------------------------- #
# 4. Make η match (Ny, Nx) orientation
# --------------------------------------------------------------------------- #
n1, n2 = size(η2d)

η_for_plot = begin
    if n1 == Ny_target && n2 == Nx_target
        @info "η2d matches (Ny, Nx) = ($Ny_target, $Nx_target)"
        η2d
    elseif n1 == Nx_target && n2 == Ny_target
        @info "η2d is (Nx, Ny); transposing to (Ny, Nx)"
        η2d'
    else
        error("η2d shape $(size(η2d)) does not match lon/lat lengths Ny=$Ny_target, Nx=$Nx_target")
    end
end

@info "η_for_plot size" size(η_for_plot)

# --------------------------------------------------------------------------- #
# 5. Plot η on x/y axes
# --------------------------------------------------------------------------- #
plt = heatmap(
    lon,                # x axis (Nx)
    lat,                # y axis (Ny)
    η_for_plot,         # (Ny, Nx)
    aspect_ratio   = :equal,
    xlabel         = "x coordinate (model grid)",
    ylabel         = "y coordinate (model grid)",
    title          = "GoM free-surface height η (day 10, HYCOM-init run)",
    titlefont      = font(14),
    c              = :balance,
    colorbar       = true,
    colorbar_title = "η [m]",
)

# --------------------------------------------------------------------------- #
# 6. Save figure
# --------------------------------------------------------------------------- #
fig_dir = joinpath(@__DIR__, "..", "figures")
mkpath(fig_dir)

png_path = joinpath(fig_dir, "gom_hr_eta_hycom_init_day10.png")

@info "Saving figure to" png_path
savefig(plt, png_path)
@info "Done saving figure."
