import xarray as xr
import numpy as np
from pathlib import Path

base = Path(__file__).resolve().parents[1]

grid_path = base / "runs" / "gom_hr_grid.nc"

# ---- CHANGE THIS to your HYCOM file path ----
hycom_path = Path("/scratch/iffat/data/hycom/hycom_snapshot.nc")

out_path = base / "runs" / "hycom_init_gom.nc"

print("Grid file:", grid_path)
print("HYCOM file:", hycom_path)

# 1) Load model grid
g = xr.open_dataset(grid_path)
lon_t = g["lon"].values
lat_t = g["lat"].values
z_t   = g["z"].values

# 2) Load HYCOM snapshot
ds = xr.open_dataset(hycom_path)

print("HYCOM variables:", list(ds.variables))

# ---- ADJUST THESE NAMES if your HYCOM file differs ----
# Common possibilities: "water_temp", "salinity", "temperature", "lon", "lat", "depth"
Tvar_name = "temperature"
Svar_name = "salinity"
lon_name  = "lon"
lat_name  = "lat"
z_name    = "depth"

T = ds[Tvar_name]
S = ds[Svar_name]

# If there is time dimension, take the first snapshot
if "time" in T.dims:
    T = T.isel(time=0)
if "time" in S.dims:
    S = S.isel(time=0)

# 3) Interpolate onto model grid
# Ensure coordinate names match dataset
T = T.rename({lon_name: "lon", lat_name: "lat", z_name: "depth"})
S = S.rename({lon_name: "lon", lat_name: "lat", z_name: "depth"})

T_on = T.interp(lon=lon_t, lat=lat_t, depth=z_t)
S_on = S.interp(lon=lon_t, lat=lat_t, depth=z_t)

# 4) Force ordering: (z, lat, lon)
T_on = T_on.transpose("depth", "lat", "lon")
S_on = S_on.transpose("depth", "lat", "lon")

# 5) Save in the exact format Julia expects
out = xr.Dataset(
    {
        "T_init": T_on.astype(np.float32),
        "S_init": S_on.astype(np.float32),
    },
    coords={
        "lon": ("lon", lon_t),
        "lat": ("lat", lat_t),
        "z":   ("z",   z_t),
    }
)

out.to_netcdf(out_path)
print("Wrote:", out_path)
print("T_init shape:", out["T_init"].shape)
print("S_init shape:", out["S_init"].shape)
print("T range:", float(out["T_init"].min()), float(out["T_init"].max()))
print("S range:", float(out["S_init"].min()), float(out["S_init"].max()))
