ENV["GKSwstype"] = "100"  # headless-friendly

using NCDatasets
using Plots

path = "runs/hycom_init_gom.nc"

ds = NCDataset(path, "r")
T_var = ds["T_init"]
S_var = ds["S_init"]
lon = Array(ds["lon"][:])
lat = Array(ds["lat"][:])
T = Array(T_var)
S = Array(S_var)
@info "T size" size(T) "S size" size(S) "lon/lat" (length(lon), length(lat))
close(ds)

function surface_slice(A, lon, lat)
    nd = ndims(A)
    if nd == 2
        return A
    elseif nd != 3
        error("Unexpected number of dims: $nd")
    end

    sz = size(A)
    lon_dim = findfirst(==(length(lon)), sz)
    lat_dim = findfirst(==(length(lat)), sz)
    if lon_dim === nothing || lat_dim === nothing || lon_dim == lat_dim
        error("Cannot identify lon/lat dims: size=$(sz), lon=$(length(lon)), lat=$(length(lat))")
    end
    depth_dim = first(filter(d -> d != lon_dim && d != lat_dim, 1:3))
    return selectdim(A, depth_dim, sz[depth_dim])
end

T_surf = surface_slice(T, lon, lat)
S_surf = surface_slice(S, lon, lat)

function match_xy(z, lon, lat)
    if size(z) == (length(lat), length(lon))
        return z
    elseif size(z) == (length(lon), length(lat))
        return z'
    else
        error("z size does not match lon/lat: z=$(size(z)) lon=$(length(lon)) lat=$(length(lat))")
    end
end

T_plot = match_xy(T_surf, lon, lat)
S_plot = match_xy(S_surf, lon, lat)

function finite_quantiles(A, qs)
    vals = filter(isfinite, vec(A))
    isempty(vals) && error("No finite values to compute quantiles.")
    sort!(vals)
    n = length(vals)
    return [vals[clamp(round(Int, q * (n - 1)) + 1, 1, n)] for q in qs]
end

T_clims = finite_quantiles(T_plot, (0.01, 0.99))
S_clims = finite_quantiles(S_plot, (0.01, 0.99))

pltT = heatmap(
    lon, lat, T_plot;
    aspect_ratio = :equal,
    xlabel = "Longitude [°W]",
    ylabel = "Latitude [°N]",
    title = "HYCOM T (surface)",
    colorbar_title = "T [°C]",
    color = cgrad(:turbo),
    clims = (T_clims[1], T_clims[2]),
    nan_color = :white,
)
savefig(pltT, "figures/hycom_Tsurf_check.png")

pltS = heatmap(
    lon, lat, S_plot;
    aspect_ratio = :equal,
    xlabel = "Longitude [°W]",
    ylabel = "Latitude [°N]",
    title = "HYCOM S (surface)",
    colorbar_title = "S [PSU]",
    color = cgrad(:viridis),
    clims = (S_clims[1], S_clims[2]),
    nan_color = :white,
)
savefig(pltS, "figures/hycom_Ssurf_check.png")