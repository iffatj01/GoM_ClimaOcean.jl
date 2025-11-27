using Oceananigans
using Oceananigans.Units
using Dates
using CUDA
import ClimaOcean
using Oceananigans.Fields: set!

"""
    build_gom_hr_ocean_seaice_model(; arch = GPU(), use_ecco = false)

Build a high-resolution Gulf of Mexico OceanSeaIce model.

If `use_ecco = false`, initializes T and S as simple constants (20°C, 35 psu).
Later we can switch to `use_ecco = true` once ECCO credentials are set.
"""
function build_gom_hr_ocean_seaice_model(; arch = GPU(), use_ecco::Bool = false)

    # Domain limits (can be adjusted later)
    lon_min, lon_max = -98, -80
    lat_min, lat_max =  18,  31

    # Roughly ~1/25°: adjust sizes if memory becomes a problem
    grid = LatitudeLongitudeGrid(arch;
        size      = (480, 360, 50),   # (Nx, Ny, Nz)
        halo      = (7, 7, 7),
        longitude = (lon_min, lon_max),
        latitude  = (lat_min, lat_max),
        z         = (-5000, 0)
    )

    @info "Building high-resolution GoM grid" size = size(grid)

    # Real bathymetry on this grid
    bathymetry = ClimaOcean.regrid_bathymetry(grid)
    grid = ImmersedBoundaryGrid(grid, GridFittedBottom(bathymetry))

    # Build hydrostatic ocean model
    ocean = ClimaOcean.ocean_simulation(grid)

    if use_ecco
        @info "Initializing T,S from ECCO (requires ECCO_USERNAME and ECCO_WEBDAV_PASSWORD)"
        start_date = DateTime(1993, 1, 1)
        set!(ocean.model;
             T = ClimaOcean.Metadatum(:temperature; date = start_date,
                                       dataset = ClimaOcean.ECCO2Daily()),
             S = ClimaOcean.Metadatum(:salinity;    date = start_date,
                                       dataset = ClimaOcean.ECCO2Daily()))
    else
        @info "Initializing T,S as simple constants (no ECCO)"
        set!(ocean.model.tracers.T, 20.0)   # 20°C
        set!(ocean.model.tracers.S, 35.0)   # 35 psu
    end

    # Atmosphere forcing (public)
    atmosphere = ClimaOcean.JRA55PrescribedAtmosphere(arch)

    # Coupled ocean-only model
    coupled_model = ClimaOcean.OceanSeaIceModel(ocean; atmosphere)

    return coupled_model
end
