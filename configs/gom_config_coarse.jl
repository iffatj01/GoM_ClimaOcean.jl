cat > configs/gom_config_coarse.jl << 'EOF'
using Oceananigans
using Oceananigans.Units
using Dates
using CUDA
import ClimaOcean

function build_gom_ocean_seaice_model(; arch = GPU())

    # Gulf of Mexico box (adjust later if you want)
    lon_min, lon_max = -98, -80
    lat_min, lat_max =  18,  31

    grid = LatitudeLongitudeGrid(arch;
        size      = (72, 52, 30),        # ~0.25° horizontally, 30 vertical levels
        halo      = (7, 7, 7),
        longitude = (lon_min, lon_max),
        latitude  = (lat_min, lat_max),
        z         = (-4000, 0)
    )

    # Realistic bathymetry on this grid
    bathymetry = ClimaOcean.regrid_bathymetry(grid)
    grid = ImmersedBoundaryGrid(grid, GridFittedBottom(bathymetry))

    # Realistic hydrostatic ocean simulation
    ocean = ClimaOcean.ocean_simulation(grid)

    # Initial T, S from ECCO at some start date
    start_date = DateTime(1993, 1, 1)
    set!(ocean.model;
         T = ClimaOcean.Metadatum(:temperature; date = start_date,
                                   dataset = ClimaOcean.ECCO2Daily()),
         S = ClimaOcean.Metadatum(:salinity;    date = start_date,
                                   dataset = ClimaOcean.ECCO2Daily()))

    # Prescribed atmosphere from JRA55
    atmosphere = ClimaOcean.JRA55PrescribedAtmosphere(arch)

    # Coupled ocean-only model (no prognostic sea ice in GoM)
    coupled_model = ClimaOcean.OceanSeaIceModel(ocean; atmosphere)

    return coupled_model
end
EOF
