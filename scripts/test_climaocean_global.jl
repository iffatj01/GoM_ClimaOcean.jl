using Oceananigans
using Oceananigans.Units
using Dates
using CUDA
import ClimaOcean

arch = CUDA.has_cuda() ? GPU() : CPU()
@info "Using architecture" arch

grid = LatitudeLongitudeGrid(arch;
    size = (360, 140, 10),       # coarse: ~1 degree
    halo = (7, 7, 7),
    longitude = (0, 360),
    latitude  = (-70, 70),
    z = (-3000, 0)
)

bathymetry = ClimaOcean.regrid_bathymetry(grid)
grid = ImmersedBoundaryGrid(grid, GridFittedBottom(bathymetry))

ocean = ClimaOcean.ocean_simulation(grid)

start_date = DateTime(1993, 1, 1)
set!(ocean.model;
     T = ClimaOcean.Metadatum(:temperature; date = start_date,
                               dataset = ClimaOcean.ECCO2Daily()),
     S = ClimaOcean.Metadatum(:salinity;    date = start_date,
                               dataset = ClimaOcean.ECCO2Daily()))

atmosphere = ClimaOcean.JRA55PrescribedAtmosphere(arch)
coupled_model = ClimaOcean.OceanSeaIceModel(ocean; atmosphere)

simulation = Simulation(coupled_model;
                        Δt = 20minutes,
                        stop_time = 5days)

@info "Starting short global test"
run!(simulation)
@info "Finished short global test"
