#!/usr/bin/env julia

using NCDatasets
using Printf

# --------------------------------------------------
# 1. Grid size (matches your high-res GoM run)
# --------------------------------------------------
const Nx = 480
const Ny = 360
const Nz = 50

# --------------------------------------------------
# 2. Physical domain extents (Gulf of Mexico)
#    Adjust here if your config uses slightly
#    different bounds.
# --------------------------------------------------
const lon_min = -98.0   # degrees East
const lon_max = -80.0   # degrees East

const lat_min =  18.0   # degrees North
const lat_max =  31.0   # degrees North

const z_min   = -5000.0 # meters (bottom)
const z_max   =     0.0 # meters (surface)

# 1D coordinate arrays at T-cell centers
lon = collect(range(lon_min, lon_max, length = Nx))
lat = collect(range(lat_min, lat_max, length = Ny))
z   = collect(range(z_min,   z_max,   length = Nz))

@info "Building coordinate-only GoM grid" Nx Ny Nz
@info "lon range" lon_min lon_max
@info "lat range" lat_min lat_max
@info "z   range" z_min   z_max

# --------------------------------------------------
# 3. Output file
# --------------------------------------------------
grid_file = joinpath(@__DIR__, "..", "runs", "gom_hr_grid.nc")
if isfile(grid_file)
    @info "Overwriting existing grid file" grid_file
end

# --------------------------------------------------
# 4. Write NetCDF with lon, lat, z
# --------------------------------------------------
NCDataset(grid_file, "c") do ds
    # Dimensions
    defDim(ds, "x", Nx)
    defDim(ds, "y", Ny)
    defDim(ds, "z", Nz)

    # Longitude (1D)
    defVar(ds, "lon", lon, ("x",);
           attrib = Dict(
               "long_name" => "longitude of T-cell centers",
               "units"     => "degrees_east"
           ))

    # Latitude (1D)
    defVar(ds, "lat", lat, ("y",);
           attrib = Dict(
               "long_name" => "latitude of T-cell centers",
               "units"     => "degrees_north"
           ))

    # Vertical coordinate (optional, for completeness)
    defVar(ds, "z", z, ("z",);
           attrib = Dict(
               "long_name" => "vertical coordinate",
               "units"     => "m",
               "positive"  => "up"
           ))

    # Global attributes (optional)
    ds.attrib["title"] = "High-resolution GoM grid (lon/lat/z coordinates)"
    ds.attrib["note"]  = "Coordinates used for plotting GoM ClimaOcean high-res run."
end

@info "Finished writing" grid_file
