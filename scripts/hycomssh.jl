using NCDatasets
using Plots

path = "runs/hycom_init_gom.nc"

ds = NCDataset(path, "r")
ssh = haskey(ds, "eta_init") ? ds["eta_init"][:] : ds["η_init"][:]
lon = ds["lon"][:]           # 1D
lat = ds["lat"][:]           # 1D
close(ds)

# Plot (lon, lat, ssh)
plt = heatmap(
    lon, lat, ssh';
    aspect_ratio = :equal,
    xlabel = "Longitude [°W]",
    ylabel = "Latitude [°N]",
    title = "HYCOM SSH (init)",
    colorbar_title = "SSH [m]",
    color = cgrad(:balance),
)

savefig(plt, "figures/hycom_ssh_check.png")