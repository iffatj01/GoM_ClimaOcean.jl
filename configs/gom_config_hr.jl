#### configs/gom_config_hr.jl
####
#### Build a high-resolution Gulf of Mexico OceanSeaIce model.
#### Options:
####   use_hycom = false  → simple constant T/S (20 °C, 35 psu)
####   use_hycom = true   → initialize T/S from runs/hycom_init_gom.nc
####                         (created by scripts/make_hycom_init_gom.py)

using Oceananigans
using Oceananigans.Units
using Oceananigans.Grids: LatitudeLongitudeGrid
using Oceananigans.ImmersedBoundaries: ImmersedBoundaryGrid, GridFittedBottom
using Oceananigans.Fields: set!, interior
using CUDA
using Dates
import ClimaOcean
using NCDatasets

# --------------------------------------------------------------------------- #
# Helper: choose a NetCDF variable from a list of candidate names
# --------------------------------------------------------------------------- #

function pick_nc_var(ds::NCDataset, candidates::Vector{String}, what::String)
    for name in candidates
        if haskey(ds, name)
            var = ds[name]
            @info "Using $what variable" name size = size(var)
            return var
        end
    end

    varnames = collect(keys(ds))
    error("Could not find any $what variables in HYCOM init file.\n" *
          "Tried: $(candidates)\n" *
          "Available variables: $(varnames)")
end

function pick_nc_var_optional(ds::NCDataset, candidates::Vector{String}, what::String)
    for name in candidates
        if haskey(ds, name)
            var = ds[name]
            @info "Using $what variable" name size = size(var)
            return var
        end
    end
    @warn "No $what variable found; skipping initialization" candidates
    return nothing
end

# --------------------------------------------------------------------------- #
# Helper: convert HYCOM array to Float64 and remove missing
# --------------------------------------------------------------------------- #

"""
    to_float64_no_missing(A)

Return a `Float64` array with the same shape as `A`, converting any
values and replacing `missing` with `NaN`.
"""
to_float64_no_missing(A) = map(x -> ismissing(x) ? NaN : Float64(x), A)

# --------------------------------------------------------------------------- #
# Helper: load HYCOM-init T,S from runs/hycom_init_gom.nc into the model
# --------------------------------------------------------------------------- #

function initialize_TS_from_hycom!(ocean_model;
                                   hy_filename::String = "hycom_init_gom.nc")

    hy_path = joinpath(@__DIR__, "..", "runs", hy_filename)
    @info "Reading HYCOM init file" hy_path = hy_path

    ds = NCDataset(hy_path, "r")

    # Choose variables (NCDatasets.Variable objects)
    T_var = pick_nc_var(ds,
                        ["T", "T_init", "temp", "temperature", "water_temp", "thetao", "THETA"],
                        "temperature")
    S_var = pick_nc_var(ds,
                        ["S", "S_init", "salt", "salinity", "SALT"],
                        "salinity")
    η_var = pick_nc_var_optional(ds,
                                 ["eta_init", "η_init", "η", "eta", "ssh", "SSH",
                                  "sea_surface_height", "surf_el", "elevation", "zos"],
                                 "sea surface height")

    # Convert to regular Julia arrays (may be Union{Missing, Float32})
    T_raw = Array(T_var)
    S_raw = Array(S_var)
    η_raw = η_var === nothing ? nothing : Array(η_var)

    close(ds)

    @info "HYCOM init T raw size" size(T_raw)
    @info "HYCOM init S raw size" size(S_raw)
    η_raw !== nothing && @info "HYCOM init η raw size" size(η_raw)

    # Model grid size (Nx, Ny, Nz)
    Nx, Ny, Nz = size(ocean_model.grid)
    n_expected = Nx * Ny * Nz

    # ------------------------------------------------------------
    # Handle shapes and reshape/permute into (Nx, Ny, Nz)
    # ------------------------------------------------------------

    if ndims(T_raw) == 3 && size(T_raw) == (Nx, Ny, Nz)
        # Current case: already (Nx, Ny, Nz)
        @info "HYCOM T,S already in (Nx, Ny, Nz) order" grid_size = (Nx, Ny, Nz)
        T_xyz = T_raw
        S_xyz = S_raw

    elseif ndims(T_raw) == 3 && size(T_raw) == (Nz, Ny, Nx)
        # Case: stored as (Nz, Ny, Nx) → permute to (Nx, Ny, Nz)
        @info "HYCOM T,S stored as (Nz, Ny, Nx); permuting to (Nx, Ny, Nz)"
        T_xyz = permutedims(T_raw, (3, 2, 1))
        S_xyz = permutedims(S_raw, (3, 2, 1))

    elseif ndims(T_raw) == 1 && length(T_raw) == n_expected
        # Case: flattened vector → reshape to (Nx, Ny, Nz)
        @info "HYCOM T,S are 1D; reshaping to (Nx, Ny, Nz)" n_expected = n_expected
        T_xyz = reshape(T_raw, (Nx, Ny, Nz))
        S_xyz = reshape(S_raw, (Nx, Ny, Nz))

    else
        error("Unsupported HYCOM shapes for T,S.\n" *
              "  model grid (Nx, Ny, Nz)     = ($Nx, $Ny, $Nz)\n" *
              "  size(T_raw) = $(size(T_raw))\n" *
              "  size(S_raw) = $(size(S_raw))")
    end

    @info "After reshaping, T size (Nx, Ny, Nz)" size(T_xyz)
    @info "After reshaping, S size (Nx, Ny, Nz)" size(S_xyz)

    if size(T_xyz) != (Nx, Ny, Nz) || size(S_xyz) != (Nx, Ny, Nz)
        error("HYCOM-init array sizes do not match model grid.\n" *
              "  model grid:  (Nx, Ny, Nz) = ($Nx, $Ny, $Nz)\n" *
              "  T_xyz size: $(size(T_xyz))\n" *
              "  S_xyz size: $(size(S_xyz))")
    end

    # ------------------------------------------------------------
    # Convert to Float64 and handle missing values on CPU
    # ------------------------------------------------------------
    @info "Converting HYCOM T,S to Float64 and replacing missing with NaN"

    T_f = to_float64_no_missing(T_xyz)
    S_f = to_float64_no_missing(S_xyz)

    η_f = nothing
    if η_raw !== nothing
        η_arr = to_float64_no_missing(η_raw)
        if ndims(η_arr) == 3 && size(η_arr, 3) == 1
            η_arr = dropdims(η_arr; dims = 3)
        end
        if size(η_arr) == (Ny, Nx)
            η_arr = permutedims(η_arr, (2, 1))
        end
        if size(η_arr) != (Nx, Ny)
            @warn "SSH size does not match model grid; skipping SSH init" size(η_arr) grid = (Nx, Ny)
        else
            η_f = η_arr
        end
    end

    # ------------------------------------------------------------
    # Sanity-clean T and S to avoid TEOS-10 sqrt domain errors
    # ------------------------------------------------------------
    T_min_raw = minimum(T_f)
    T_max_raw = maximum(T_f)
    S_min_raw = minimum(S_f)
    S_max_raw = maximum(S_f)
    @info "HYCOM init min/max BEFORE cleaning" T_min_raw T_max_raw S_min_raw S_max_raw

    # Background values for non-finite entries
    T_bg = 10.0   # °C
    S_bg = 35.0   # psu

    # Replace non-finite values and clamp to physical ranges
    # Temperature: [-2, 40] °C
    # Salinity   : (0, 42] psu; enforce strictly positive lower bound
    T_f .= map(x -> begin
        y = !isfinite(x) ? T_bg : x
        clamp(y, -2.0, 40.0)
    end, T_f)

    S_f .= map(x -> begin
        y = !isfinite(x) ? S_bg : x
        clamp(y, 1e-6, 42.0)
    end, S_f)

    if η_f !== nothing
        η_f .= map(x -> begin
            y = !isfinite(x) ? 0.0 : x
            clamp(y, -5.0, 5.0)
        end, η_f)
        @info "HYCOM init η min/max AFTER cleaning" minimum(η_f) maximum(η_f)
    end

    T_min_clean = minimum(T_f)
    T_max_clean = maximum(T_f)
    S_min_clean = minimum(S_f)
    S_max_clean = maximum(S_f)
    @info "HYCOM init min/max AFTER cleaning" T_min_clean T_max_clean S_min_clean S_max_clean

    # ------------------------------------------------------------
    # Copy cleaned arrays into model tracers (CPU or GPU)
    # ------------------------------------------------------------
    @info "Setting model tracers T,S from HYCOM fields"
    set!(ocean_model.tracers.T, T_f)
    set!(ocean_model.tracers.S, S_f)

    if η_f !== nothing
        @info "Setting free surface η from HYCOM SSH"
        set!(ocean_model.free_surface.η, η_f)
    end

    return nothing
end

# --------------------------------------------------------------------------- #
# Helper: log basic stats for model T,S after initialization
# --------------------------------------------------------------------------- #

function log_TS_sanity(ocean_model; label::String = "T,S sanity")
    T_arr = Array(interior(ocean_model.tracers.T))
    S_arr = Array(interior(ocean_model.tracers.S))

    T_vals = filter(isfinite, vec(T_arr))
    S_vals = filter(isfinite, vec(S_arr))

    T_nan_pct = 100 * (1 - length(T_vals) / length(T_arr))
    S_nan_pct = 100 * (1 - length(S_vals) / length(S_arr))

    @info "$label (T)" min = minimum(T_vals) max = maximum(T_vals) nan_pct = T_nan_pct
    @info "$label (S)" min = minimum(S_vals) max = maximum(S_vals) nan_pct = S_nan_pct

    if minimum(T_vals) < -2.0 || maximum(T_vals) > 40.0
        @warn "Temperature out of expected range [-2, 40] °C"
    end
    if minimum(S_vals) <= 0.0 || maximum(S_vals) > 42.0
        @warn "Salinity out of expected range (0, 42] psu"
    end

    return nothing
end

# --------------------------------------------------------------------------- #
# Main builder
# --------------------------------------------------------------------------- #

"""
    build_gom_hr_ocean_seaice_model(; arch = default_architecture(), use_hycom = false)

Build a high-resolution Gulf of Mexico `OceanSeaIceModel`.

Arguments
---------
- `arch`      : `GPU()` (default if CUDA is available) or `CPU()`
- `use_hycom` : if `true`, initialize T,S from `runs/hycom_init_gom.nc`;
                otherwise use simple constants (20 °C, 35 psu).

Returns
-------
- `coupled_model::ClimaOcean.OceanSeaIceModel`
"""
function build_gom_hr_ocean_seaice_model(; arch = default_architecture(),
                                         use_hycom::Bool = false)

    # ---------------- Domain and grid ---------------- #

    lon_min, lon_max = -98, -80
    lat_min, lat_max =  18,  31

    # ≈ 1/25° horizontal; adjust size if this is too heavy
    base_grid = LatitudeLongitudeGrid(arch;
        size      = (480, 360, 50),   # (Nx, Ny, Nz)
        halo      = (7, 7, 7),
        longitude = (lon_min, lon_max),
        latitude  = (lat_min, lat_max),
        z         = (-5000, 0),
    )

    @info "Building high-resolution GoM grid" size = size(base_grid)

    # ---------------- Bathymetry from ClimaOcean ---------------- #

    bathymetry = ClimaOcean.regrid_bathymetry(base_grid)
    grid = ImmersedBoundaryGrid(base_grid, GridFittedBottom(bathymetry))

    bmin = minimum(bathymetry)
    bmax = maximum(bathymetry)
    @info "Bathymetry min/max (m)" bmin bmax
    if bmin < -7000
        @warn "Bathymetry min is deeper than -7000 m; check domain or source"
    end

    # ---------------- Build hydrostatic ocean model ---------------- #

    ocean_simulation = ClimaOcean.ocean_simulation(grid)
    ocean_model = ocean_simulation.model

    # ---------------- Initialize T,S ---------------- #

    if use_hycom
        @info "Initializing T,S from HYCOM reanalysis (hycom_init_gom.nc)"
        initialize_TS_from_hycom!(ocean_model)
        log_TS_sanity(ocean_model; label = "HYCOM init")
    else
        @info "Initializing T,S as simple constants"
        set!(ocean_model.tracers.T, 20.0)  # 20 °C
        set!(ocean_model.tracers.S, 35.0)  # 35 psu
        log_TS_sanity(ocean_model; label = "Constant init")
    end

    # ---------------- Atmosphere and coupling ---------------- #

    atmosphere = ClimaOcean.JRA55PrescribedAtmosphere(arch)

    # Couple ocean + atmosphere into an OceanSeaIceModel
    coupled_model = ClimaOcean.OceanSeaIceModel(ocean_simulation; atmosphere)

    return coupled_model
end

# Helper so scripts can query default architecture
function default_architecture()
    CUDA.has_cuda() ? GPU() : CPU()
end
