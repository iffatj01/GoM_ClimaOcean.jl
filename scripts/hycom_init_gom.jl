# scripts/hycom_init_gom.jl

using NCDatasets
using Oceananigans

"""
    initialize_tracers_from_hycom!(model; hycom_path, T_var="T_init", S_var="S_init")

Read HYCOM initial condition file and safely initialize model.tracers.T and S.

- Ensures array order is (Nx, Ny, Nz).
- Replaces missing/fill values.
- Clips T and S to physically reasonable ranges:
    T ∈ [-2, 40] °C
    S ∈ [0, 42] g/kg (practical salinity units range)
"""
function initialize_tracers_from_hycom!(model;
                                        hycom_path::AbstractString,
                                        T_var::AbstractString = "T_init",
                                        S_var::AbstractString = "S_init")

    @info "Reading HYCOM init file" hy_path = hycom_path

    ds = NCDataset(hycom_path, "r")
    try
        T_raw = ds[T_var][:]
        S_raw = ds[S_var][:]

        # Try to infer dimensions
        sz = size(T_raw)
        @info "HYCOM init T raw size" sizeT = sz
        @info "HYCOM init S raw size" sizeS = size(S_raw)

        # We want (Nx, Ny, Nz). Many HYCOM files are written as (lon, lat, z)
        # or already (Nx, Ny, Nz). We will handle the common cases.
        if length(sz) == 3
            # Assume already (Nx, Ny, Nz) if matches model.grid size
            Nx, Ny, Nz = size(model.grid)
            if sz == (Nx, Ny, Nz)
                @info "HYCOM T,S already in (Nx, Ny, Nz) order" grid_size = (Nx, Ny, Nz)
                T_xyz = Array{Float64}(T_raw)
                S_xyz = Array{Float64}(S_raw)
            elseif sz == (Nz, Ny, Nx)
                @info "Permuting HYCOM T,S from (Nz, Ny, Nx) to (Nx, Ny, Nz)"
                T_xyz = permutedims(Array{Float64}(T_raw), (3, 2, 1))
                S_xyz = permutedims(Array{Float64}(S_raw), (3, 2, 1))
            else
                @warn "Unexpected HYCOM T,S size – attempting generic permute to model grid" sz
                T_xyz = Array{Float64}(reshape(T_raw, size(model.grid)))
                S_xyz = Array{Float64}(reshape(S_raw, size(model.grid)))
            end
        else
            error("HYCOM T,S arrays must be 3D, got size = $(sz)")
        end

        @info "After reshaping, T size (Nx, Ny, Nz)" sizeT = size(T_xyz)
        @info "After reshaping, S size (Nx, Ny, Nz)" sizeS = size(S_xyz)

        # Replace missing / fill values with NaN then with defaults
        # Handle both missing and NaN consistently
        T_arr = T_xyz
        S_arr = S_xyz

        # Convert missing to NaN if needed
        if eltype(T_arr) <: Union{Missing, Real}
            T_arr = Float64.(coalesce.(T_arr, NaN))
        end
        if eltype(S_arr) <: Union{Missing, Real}
            S_arr = Float64.(coalesce.(S_arr, NaN))
        end

        # Replace NaN with reasonable background values
        T_arr = ifelse.(isfinite.(T_arr), T_arr, 10.0)  # 10°C as generic mid-depth value
        S_arr = ifelse.(isfinite.(S_arr), S_arr, 35.0)  # typical open-ocean salinity

        # HARD SAFETY CLIP:
        # This is what prevents TEOS-10 from ever seeing insane values.
        T_min, T_max = -2.0, 40.0
        S_min, S_max =  0.0, 42.0

        T_arr = clamp.(T_arr, T_min, T_max)
        S_arr = clamp.(S_arr, S_min, S_max)

        @info "HYCOM T range after sanitization" Tmin = minimum(T_arr) Tmax = maximum(T_arr)
        @info "HYCOM S range after sanitization" Smin = minimum(S_arr) Smax = maximum(S_arr)

        # Finally set model tracers
        @info "Setting model tracers T,S from HYCOM fields"
        set!(model.tracers.T, T_arr)
        set!(model.tracers.S, S_arr)

    finally
        close(ds)
    end

    return nothing
end
