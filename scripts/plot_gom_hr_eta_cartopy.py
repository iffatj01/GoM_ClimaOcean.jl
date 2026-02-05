import h5py
import numpy as np
import matplotlib.pyplot as plt
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import os

# --- 1. Open snapshot --------------------------------------------------------
base_dir = os.path.dirname(os.path.abspath(__file__))
snapshot_file = os.path.join(base_dir, "..", "runs",
                             "gom_hr_output", "gom_hr_10days_snapshot.jld2")

print("Reading:", snapshot_file)
with h5py.File(snapshot_file, "r") as f:
    eta = f["η"][...]

print("eta shape (raw):", eta.shape)

# Handle possible shapes
if eta.ndim == 3:
    # We saw (1, 360, 480): (time, lat, lon)
    if eta.shape[0] == 1:
        eta2d = eta[0, :, :]      # (Ny, Nx) = (lat, lon)
    elif eta.shape[2] == 1:
        eta2d = eta[:, :, 0]      # (Ny, Nx) or (Nx, Ny) depending…
    else:
        raise ValueError(f"Unexpected 3D shape for eta: {eta.shape}")
elif eta.ndim == 2:
    eta2d = eta
else:
    raise ValueError(f"Unexpected number of dims for eta: {eta.ndim}")

Ny, Nx = eta2d.shape
print("eta2d (Ny, Nx):", Ny, Nx)

# --- 2. Reconstruct lon/lat from gom_config_hr.jl ----------------------------

lon_min, lon_max = -98.0, -80.0
lat_min, lat_max =  18.0,  31.0

lon = np.linspace(lon_min, lon_max, Nx)   # x-direction
lat = np.linspace(lat_min, lat_max, Ny)   # y-direction

LON, LAT = np.meshgrid(lon, lat, indexing="xy")   # (Ny, Nx)

# No transpose now: eta2d is already (Ny, Nx)
eta_plot = eta2d

# --- 3. Make a clean GoM map with Cartopy -----------------------------------

proj = ccrs.PlateCarree()

fig = plt.figure(figsize=(9, 6))
ax = plt.axes(projection=proj)

# Match the model domain closely
ax.set_extent([-98, -80, 18, 31], crs=proj)

# Draw η
pcm = ax.pcolormesh(
    LON, LAT, eta_plot,
    transform=proj,
    cmap="RdBu_r",
    vmin=-0.2, vmax=0.2
)

# Land / coast styling
ax.add_feature(cfeature.OCEAN, facecolor="white", zorder=0)         # ocean background
ax.add_feature(cfeature.LAND, facecolor="lightgray", zorder=1)      # land
ax.coastlines(resolution="50m", linewidth=1.0, zorder=2)

# (Optional) borders if you like
# ax.add_feature(cfeature.BORDERS, linewidth=0.5, zorder=3)

# Colorbar
cb = plt.colorbar(pcm, ax=ax, orientation="vertical", label="η [m]")

ax.set_title("GoM high-res η (day 10 snapshot)")
ax.set_xlabel("Longitude (°E)")
ax.set_ylabel("Latitude (°N)")

plt.tight_layout()

fig_dir = os.path.join(base_dir, "..", "figures")
os.makedirs(fig_dir, exist_ok=True)
out_png = os.path.join(fig_dir, "gom_hr_eta_cartopy.png")
print("Saving to:", out_png)
plt.savefig(out_png, dpi=300)
plt.close(fig)
