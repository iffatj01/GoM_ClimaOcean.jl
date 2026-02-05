#!/usr/bin/env python

import numpy as np
import xarray as xr
import os

# -------------------------------------------------------------------
# 1. Paths
# -------------------------------------------------------------------
proj_dir = os.path.dirname(os.path.abspath(__file__))  # .../GoM_ClimaOcean.jl/scripts
proj_dir = os.path.dirname(proj_dir)                   # .../GoM_ClimaOcean.jl

grid_path  = os.path.join(proj_dir, "runs", "gom_hr_grid.nc")
hycom_3d_path = os.path.join(proj_dir, "data", "hycom", "gomb4_daily_2015_001_3z.nc")
hycom_2d_path = os.path.join(proj_dir, "data", "hycom", "gomb4_daily_2020_001_2d.nc")
out_path   = os.path.join(proj_dir, "runs", "hycom_init_gom.nc")

print("Reading model grid:", grid_path)
print("Reading HYCOM 3D file (T/S):", hycom_3d_path)
print("Reading HYCOM 2D file (SSH):", hycom_2d_path)

# -------------------------------------------------------------------
# 2. Read model grid (from dump_gom_grid.jl)
#    NOTE: lon, lat in this file are ALREADY in degrees
# -------------------------------------------------------------------
grid = xr.open_dataset(grid_path)

lon_tgt = grid["lon"].values  # degrees East (negative = West)
lat_tgt = grid["lat"].values  # degrees North
z_m     = grid["z"].values    # negative depth in meters (Oceananigans)

Nx = lon_tgt.size
Ny = lat_tgt.size
Nz = z_m.size

depth_tgt = -z_m   # positive depth, meters

print(f"Model grid: Nx={Nx}, Ny={Ny}, Nz={Nz}")
print(f"lon_tgt range: {lon_tgt.min():.2f} to {lon_tgt.max():.2f} deg")
print(f"lat_tgt range: {lat_tgt.min():.2f} to {lat_tgt.max():.2f} deg")
print(f"depth_tgt range: {depth_tgt.min():.1f} to {depth_tgt.max():.1f} m")

# -------------------------------------------------------------------
# 3. Read HYCOM regional GoM files and rename coordinates
# -------------------------------------------------------------------
ds3_raw = xr.open_dataset(hycom_3d_path)
print(ds3_raw)

ds2_raw = xr.open_dataset(hycom_2d_path)
print(ds2_raw)

# Rename HYCOM coordinates to simpler names
# MT -> time, Depth -> depth, Latitude -> lat, Longitude -> lon
def rename_coords(ds):
    rename_dict = {}
    if "MT" in ds.coords:
        rename_dict["MT"] = "time"
    if "Depth" in ds.coords:
        rename_dict["Depth"] = "depth"
    if "Latitude" in ds.coords:
        rename_dict["Latitude"] = "lat"
    if "Longitude" in ds.coords:
        rename_dict["Longitude"] = "lon"
    return ds.rename(rename_dict)

ds3 = rename_coords(ds3_raw)
ds2 = rename_coords(ds2_raw)

def mask_fill_values(da):
    fill = da.attrs.get("_FillValue", None)
    if fill is None:
        fill = da.attrs.get("missing_value", None)
    if fill is None:
        fill = da.encoding.get("_FillValue", None)
    if fill is None:
        fill = da.encoding.get("missing_value", None)

    da = da.where(np.isfinite(da))
    if fill is not None:
        da = da.where(da != fill)

    # Catch extreme sentinel values that sometimes slip through
    da = da.where(np.abs(da) < 1.0e20)
    return da

# -------------------------------------------------------------------
# 4. Extract coordinates and T/S variables
# -------------------------------------------------------------------
if "lon" not in ds3.coords or "lat" not in ds3.coords or "depth" not in ds3.coords:
    raise ValueError("After renaming, expected coords 'lon', 'lat', 'depth' not found in 3D file.")

lon_src = ds3["lon"]
lat_src = ds3["lat"]
depth_src = ds3["depth"]

# Temperature / salinity variables
if "temperature" in ds3:
    T_src = ds3["temperature"]
elif "water_temp" in ds3:
    T_src = ds3["water_temp"]
else:
    raise ValueError("Cannot find temperature variable ('temperature' or 'water_temp') in HYCOM file.")

if "salinity" in ds3:
    S_src = ds3["salinity"]
elif "salt" in ds3:
    S_src = ds3["salt"]
else:
    raise ValueError("Cannot find salinity variable ('salinity' or 'salt') in HYCOM file.")

# Use the first (and only) time index if 'time' dim exists
if "time" in T_src.dims:
    T_src = T_src.isel(time=0)
    S_src = S_src.isel(time=0)

print("HYCOM T shape:", T_src.shape)
print("HYCOM S shape:", S_src.shape)

# Optional sea-surface height / elevation variable
eta_candidates = [
    "ssh", "SSH", "eta", "η", "sea_surface_height",
    "surf_el", "elevation", "zos"
]
eta_src = None
for name in eta_candidates:
    if name in ds2:
        eta_src = ds2[name]
        print(f"Using SSH variable: {name}")
        break

T_src = mask_fill_values(T_src)
S_src = mask_fill_values(S_src)

if eta_src is not None:
    eta_src = mask_fill_values(eta_src)
    if "time" in eta_src.dims:
        eta_src = eta_src.isel(time=0)

# -------------------------------------------------------------------
# 5. Subset HYCOM to our box (slightly larger than target box)
# -------------------------------------------------------------------
lon_min = float(lon_tgt.min()) - 0.5
lon_max = float(lon_tgt.max()) + 0.5
lat_min = float(lat_tgt.min()) - 0.5
lat_max = float(lat_tgt.max()) + 0.5

# If lon_src is 0..360, convert target; else use degrees directly
if float(lon_src.max()) > 180.0:
    lon_tgt_mod = (lon_tgt + 360.0) % 360.0
    lon_min = float(lon_tgt_mod.min()) - 0.5
    lon_max = float(lon_tgt_mod.max()) + 0.5
else:
    lon_tgt_mod = lon_tgt

T_sub = T_src.sel(lon=slice(lon_min, lon_max), lat=slice(lat_min, lat_max))
S_sub = S_src.sel(lon=slice(lon_min, lon_max), lat=slice(lat_min, lat_max))
eta_sub = None
if eta_src is not None:
    eta_sub = eta_src.sel(lon=slice(lon_min, lon_max), lat=slice(lat_min, lat_max))

print("Subset T shape:", T_sub.shape)
print("Subset lon range:", float(T_sub.lon.min()), "to", float(T_sub.lon.max()))
print("Subset lat range:", float(T_sub.lat.min()), "to", float(T_sub.lat.max()))

# -------------------------------------------------------------------
# 6. Interpolate HYCOM → model grid
#    Order: depth, lat, lon
# -------------------------------------------------------------------
print("Interpolating in 3D to model grid... this may take a bit.")

T_interp = T_sub.interp(
    depth=depth_tgt,
    lat=lat_tgt,
    lon=lon_tgt_mod,
)
S_interp = S_sub.interp(
    depth=depth_tgt,
    lat=lat_tgt,
    lon=lon_tgt_mod,
)
eta_interp = None
if eta_sub is not None:
    eta_interp = eta_sub.interp(
        lat=lat_tgt,
        lon=lon_tgt_mod,
    )

print("Interpolated T shape:", T_interp.shape)

# -------------------------------------------------------------------
# 7. SAFETY: clean up T/S before writing (avoid NaNs & crazy values)
# -------------------------------------------------------------------
T_values = T_interp.values.astype("float32")
S_values = S_interp.values.astype("float32")

eta_values = None
if eta_interp is not None:
    eta_values = eta_interp.values.astype("float32")

print(f"Raw T range (with NaNs): min={np.nanmin(T_values):.3f}, max={np.nanmax(T_values):.3f}")
print(f"Raw S range (with NaNs): min={np.nanmin(S_values):.3f}, max={np.nanmax(S_values):.3f}")
if eta_values is not None:
    print(f"Raw SSH range (with NaNs): min={np.nanmin(eta_values):.3f}, max={np.nanmax(eta_values):.3f}")

# Replace non-finite values (NaN, Inf) by reasonable background
T_background = 10.0  # °C, typical mid-depth GoM
S_background = 35.0  # PSU, typical open-ocean salinity
eta_background = 0.0  # m, reference sea level

T_values = np.where(np.isfinite(T_values), T_values, T_background).astype("float32")
S_values = np.where(np.isfinite(S_values), S_values, S_background).astype("float32")
if eta_values is not None:
    eta_values = np.where(np.isfinite(eta_values), eta_values, eta_background).astype("float32")

# Clip to physically reasonable ranges
T_values = np.clip(T_values, -2.0, 40.0)  # seawater range
S_values = np.clip(S_values, 0.0, 42.0)   # practical salinity range
if eta_values is not None:
    eta_values = np.clip(eta_values, -5.0, 5.0)  # SSH range in meters

print(f"Sanitized T range: min={T_values.min():.3f}, max={T_values.max():.3f}")
print(f"Sanitized S range: min={S_values.min():.3f}, max={S_values.max():.3f}")
if eta_values is not None:
    print(f"Sanitized SSH range: min={eta_values.min():.3f}, max={eta_values.max():.3f}")

# -------------------------------------------------------------------
# 8. Save as hycom_init_gom.nc
# -------------------------------------------------------------------
out = xr.Dataset(
    coords={
        "depth": ("depth", depth_tgt),
        "lat":   ("lat",   lat_tgt),
        "lon":   ("lon",   lon_tgt),
    },
    data_vars={
        "T_init": (("depth", "lat", "lon"), T_values),
        "S_init": (("depth", "lat", "lon"), S_values),
    },
)

if eta_values is not None:
    # Save both ASCII and Unicode names for compatibility
    out["eta_init"] = (("lat", "lon"), eta_values)
    out["η_init"] = (("lat", "lon"), eta_values)

out.attrs["source"] = "HYCOM GOMb0.04 gomb4_daily_2015_001_3z.nc regridded to GoM Oceananigans grid"
out.attrs["note"]   = "depth positive downward, lon/lat in degrees; T,S sanitized (no NaNs, clipped ranges); SSH optional"

print("Writing:", out_path)
os.makedirs(os.path.dirname(out_path), exist_ok=True)
out.to_netcdf(out_path)

print("Done. hycom_init_gom.nc ready.")
