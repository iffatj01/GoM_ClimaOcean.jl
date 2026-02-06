# GoM_ClimaOcean.jl
# Gulf of Mexico ClimaOcean Scripts

Complete workflow documentation for running high-resolution Gulf of Mexico ocean simulations with ClimaOcean.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Detailed Workflow](#detailed-workflow)
  - [Phase 1: Initial Setup](#phase-1-initial-setup)
  - [Phase 2: HYCOM Data Preparation](#phase-2-hycom-data-preparation)
  - [Phase 3: Run Simulation](#phase-3-run-simulation)
  - [Phase 4: Visualization](#phase-4-visualization)
- [File Organization](#file-organization)
- [Script Reference](#script-reference)
- [Configuration Options](#configuration-options)
- [Troubleshooting](#troubleshooting)

---

## Overview

This repository contains scripts for running regional ocean simulations of the Gulf of Mexico using ClimaOcean. The workflow supports:

- **High-resolution grid**: 480 × 360 × 50 (≈ 1/25° horizontal resolution)
- **Domain**: Longitude -98° to -80°, Latitude 18° to 31°
- **Initialization**: From HYCOM reanalysis data
- **Forcing**: JRA55 prescribed atmosphere
- **Bathymetry**: ETOPO2022 dataset

---

## Quick Start

**If HYCOM initialization is already prepared:**

```bash
# Run 1-day simulation
julia --project scripts/run_gom_hr_1day.jl

# Visualize results
julia --project scripts/plot_gom_hr_1day.jl
julia --project scripts/animate_gom_hr_1day.jl
```

**Starting from scratch:** Follow the [Detailed Workflow](#detailed-workflow) below.

---

## Detailed Workflow

### Phase 1: Initial Setup

**One-time setup** to install dependencies and verify the environment.

#### 1.1 Install Julia Packages

From the project root directory:

```bash
julia --project -e "using Pkg; Pkg.instantiate()"
```

This installs all dependencies specified in `Project.toml`:
- Oceananigans (ocean model)
- ClimaOcean (realistic ocean simulations)
- CUDA (GPU support, if available)
- NCDatasets, JLD2 (data I/O)
- Plots, CairoMakie (visualization)

#### 1.2 Verify Architecture

Check if GPU is available:

```julia
using CUDA
println(CUDA.has_cuda() ? "GPU available" : "CPU only")
```

---

### Phase 2: HYCOM Data Preparation

**One-time or periodic** - Create model grid and interpolate HYCOM initialization data.

#### 2.1 Prepare HYCOM Source Data

Download HYCOM Gulf of Mexico data and place in `data/hycom/`:

```
data/hycom/
  ├── gomb4_daily_2015_001_3z.nc   # 3D fields: temperature, salinity
  └── gomb4_daily_2020_001_2d.nc   # 2D fields: sea surface height
```

**HYCOM data sources:**
- [HYCOM Gulf of Mexico](https://www.hycom.org/)
- Regional model: `gomb4` (Gulf of Mexico)
- Variables needed: `water_temp`, `salinity`, `surf_el` (SSH)

#### 2.2 Generate Model Grid File

Creates a NetCDF file with model grid coordinates for Python interpolation:

```bash
julia scripts/dump_gom_grid.jl
```

**Output:** `runs/gom_hr_grid.nc`

**Grid specifications:**
- Nx = 480, Ny = 360, Nz = 50
- Longitude: -98° to -80° E
- Latitude: 18° to 31° N
- Depth: -5000 to 0 m

#### 2.3 Interpolate HYCOM Data to Model Grid

```bash
python scripts/make_hycom_init_gom.py
```

**Input files:**
- `runs/gom_hr_grid.nc` (model grid)
- `data/hycom/gomb4_daily_2015_001_3z.nc` (HYCOM 3D)
- `data/hycom/gomb4_daily_2020_001_2d.nc` (HYCOM 2D)

**Output:** `runs/hycom_init_gom.nc`

**This file contains:**
- `T_init`: Temperature (Nx × Ny × Nz)
- `S_init`: Salinity (Nx × Ny × Nz)
- `eta_init`: Sea surface height (Nx × Ny)

**Note:** The script handles coordinate transformations, missing values, and vertical interpolation automatically.

---

### Phase 3: Run Simulation

#### 3.1 Available Run Scripts

| Script | Duration | Timestep | Description |
|--------|----------|----------|-------------|
| `run_gom_hr_1day.jl` | 1 day | 20s | Quick test run |
| `run_gom_hr_2days.jl` | 2 days | 20s | Medium test |
| `run_gom_hr_10days.jl` | 10 days | 20s | Extended simulation |

#### 3.2 Run 1-Day Simulation

```bash
julia --project scripts/run_gom_hr_1day.jl
```

**What happens:**
1. Loads model configuration from `configs/gom_config_hr.jl`
2. Downloads ETOPO2022 bathymetry (cached in `~/.julia/datadeps/`)
3. Regrids bathymetry onto model grid
4. Creates `ImmersedBoundaryGrid` with land mask
5. Initializes ocean model with T/S from `runs/hycom_init_gom.nc`
6. Sets up JRA55 atmospheric forcing
7. Runs simulation for 1 day (20s timestep = 4320 iterations)
8. Saves output every hour

**Expected runtime:**
- **GPU (Nvidia A100/H100)**: ~10-30 minutes
- **CPU**: ~several hours 
**Progress output:**
```
Progress: t = 0.042 days (4.2% of 1 day), iter = 50
Progress: t = 0.083 days (8.3% of 1 day), iter = 100
...
```

#### 3.3 Output Files

Saved to `runs/gom_hr_output/`:

```
gom_hr_1day_init_snapshot_hycom.jld2       # Initial state (t=0)
  ├── η: Sea surface height (480 × 360)
  ├── T: Temperature (480 × 360 × 50)
  └── S: Salinity (480 × 360 × 50)

gom_hr_1day_timeseries.jld2               # Hourly snapshots
  ├── iterations: [0, 180, 360, ...]
  ├── η: Sea surface height at each hour
  └── T: Surface temperature at each hour

gom_hr_1dayssh_snapshot_hycom.jld2         # Final state (t=1day)
  ├── η: Sea surface height (480 × 360)
  ├── T: Temperature (480 × 360 × 50)
  └── S: Salinity (480 × 360 × 50)
```

---

### Phase 4: Visualization

#### 4.1 Static Plots

**Main plotting script (recommended):**

```bash
julia --project scripts/plot_gom_hr_1day.jl
```

**Generates** (`figures/` directory):
- `gom_hr_1day_bathymetry.png` - Basin bathymetry
- `gom_hr_1day_etainit.png` - Initial SSH (t=0)
- `gom_hr_1day_eta.png` - Final SSH (t=1 day)
- `gom_hr_1day_Tsurfinit.png` - Initial surface temperature
- `gom_hr_1day_Tsurf.png` - Final surface temperature

**Features:**
- Land masking using bathymetry
- Coastline overlay for correct Gulf shape
- Symmetric color scales for SSH
- Physical units and coordinate labels


#### 4.2 Animations

**Create hourly SSH animation:**

```bash
julia --project scripts/animate_gom_hr_1day.jl
```

**Output:** `figures/gom_hr_1day_eta.gif`

**Animation details:**
- 25 frames (hourly snapshots)
- Shows SSH evolution over 1 day
- Includes colorbar and time labels
- Land masked with bathymetry

#### 4.3 Diagnostic Plots

**Quick SSH inspection:**
```bash
julia --project scripts/peek_gom_hr_ssh.jl
```

**Temperature/Salinity profiles:**
```bash
julia --project scripts/plot_gom_hr_TS.jl
```

**HYCOM initialization verification:**
```bash
julia --project scripts/plot_hycom_TS.jl
```

---

## File Organization

```
GoM_ClimaOcean.jl/
├── configs/
│   ├── gom_config_hr.jl              # High-res model configuration
│   └── gom_config_coarse.jl          # Coarse model (for testing)
│
├── scripts/
│   ├── dump_gom_grid.jl              # [SETUP] Generate grid file
│   ├── make_hycom_init_gom.py        # [SETUP] Interpolate HYCOM data
│   │
│   ├── run_gom_hr_1day.jl            # [RUN] 1-day simulation
│   ├── run_gom_hr_2days.jl           # [RUN] 2-day simulation
│   ├── run_gom_hr_10days.jl          # [RUN] 10-day simulation
│   │
│   ├── plot_gom_hr_1day.jl           # [VIZ] Main plotting script
│   ├── plot_gom_hr_1day_pro.jl       # [VIZ] Alternative plotting
│   ├── animate_gom_hr_1day.jl        # [VIZ] Create animations
│   ├── peek_gom_hr_ssh.jl            # [VIZ] Quick SSH check
│   ├── plot_gom_hr_TS.jl             # [VIZ] T/S profiles
│   ├── plot_hycom_TS.jl              # [VIZ] HYCOM verification
│   
│
├── runs/
│   ├── gom_hr_grid.nc                # [GENERATED] Model grid
│   ├── hycom_init_gom.nc             # [GENERATED] Interpolated HYCOM
│   └── gom_hr_output/                # [GENERATED] Simulation output
│       ├── gom_hr_1day_init_snapshot_hycom.jld2
│       ├── gom_hr_1day_timeseries.jld2
│       └── gom_hr_1dayssh_snapshot_hycom.jld2
│
├── data/
│   └── hycom/                        # [USER PROVIDED] HYCOM source data
│       ├── gomb4_daily_2015_001_3z.nc
│       └── gomb4_daily_2020_001_2d.nc
│
├── figures/                          # [GENERATED] Plots and animations
│   ├── gom_hr_1day_*.png
│   └── gom_hr_1day_*.gif
│
├── Project.toml                      # Julia dependencies
├── Manifest.toml                     # Locked dependency versions
└── README.md                         # Main project documentation
```

---

## Script Reference

### Setup Scripts

#### `dump_gom_grid.jl`
Generates NetCDF file with model grid coordinates for Python interpolation.

**Usage:** `julia scripts/dump_gom_grid.jl`

**Output:** `runs/gom_hr_grid.nc`

---

#### `make_hycom_init_gom.py`
Interpolates HYCOM reanalysis data onto model grid.

**Usage:** `python scripts/make_hycom_init_gom.py`

**Requirements:**
- Python packages: `numpy`, `xarray`, `scipy`
- Input files: HYCOM source data + model grid

**Output:** `runs/hycom_init_gom.nc`

**Key features:**
- Handles coordinate transformations (longitude wrapping, depth sign)
- Vertical interpolation from HYCOM levels to model levels
- Missing value handling and quality checks
- Nearest-neighbor filling for coastal points

---

### Simulation Scripts

#### `run_gom_hr_1day.jl`
Main 1-day simulation script with HYCOM initialization.

**Configuration:**
- Timestep: 20 seconds (4320 iterations/day)
- Output: Hourly snapshots (25 frames total)
- Initial & final snapshots saved

**Key parameters:**
```julia
use_hycom = true              # Use HYCOM initialization
Δt = 20.0                     # seconds
stop_time = 86400.0           # 1 day
output_interval = 3600.0      # 1 hour
```

**Modify simulation length:**
```julia
stop_time_sim = 2 * 86400.0   # 2 days
```

---

#### `run_gom_hr_2days.jl`, `run_gom_hr_10days.jl`
Extended simulation scripts. Same structure as 1-day run.

---

### Visualization Scripts

#### `plot_gom_hr_1day.jl`
Professional plotting with land masking and coastlines.

**Features:**
- Reads bathymetry from ClimaOcean
- Creates land mask (bathymetry >= 0)
- Symmetric colorscales for SSH
- Physical coordinate labels (lon/lat)

**Generated plots:**
- Bathymetry
- Initial & final SSH
- Initial & final surface temperature

---

#### `animate_gom_hr_1day.jl`
Creates GIF animation from hourly timeseries.

**Output:** `figures/gom_hr_1day_eta.gif`

**Customization:**
```julia
fps = 5                       # frames per second
dpi = 150                     # resolution
clims = (-0.5, 0.5)          # SSH colorbar limits (m)
```

---

#### `peek_gom_hr_ssh.jl`
Quick diagnostic script to inspect SSH fields.

**Usage:** When you need to quickly check simulation output without full plotting.

---

### Debug Scripts

#### `check_vertical_mismatch.jl` / `check_vertical_mismatch.py`
Diagnose vertical coordinate issues in HYCOM interpolation.

**When to use:**
- NaN values in T/S after initialization
- Vertical profile discontinuities
- Bathymetry-related issues

---

## Configuration Options

### Model Configuration (`configs/gom_config_hr.jl`)

#### Grid Resolution

```julia
base_grid = LatitudeLongitudeGrid(arch;
    size      = (480, 360, 50),      # (Nx, Ny, Nz)
    longitude = (-98, -80),           # degrees
    latitude  = (18, 31),             # degrees
    z         = (-5000, 0),           # meters
    halo      = (7, 7, 7),
)
```

**For testing/debugging:**
- Reduce to `(240, 180, 25)` for faster runs
- Reduce to `(120, 90, 25)` for very quick tests

#### Bathymetry Options

```julia
bathymetry = ClimaOcean.regrid_bathymetry(base_grid,
    dataset = ETOPO2022(),           # or ETOPO1()
    interpolation_passes = 1,        # 1 = sharp, 10 = smooth
    minimum_depth = 10,              # meters (minimum ocean depth)
    major_basins = 1,                # keep only main basin
)
```

**Smoothing bathymetry:**
- `interpolation_passes = 10` for moderate smoothing
- `interpolation_passes = 40` for very smooth bathymetry
- More passes reduce steep gradients but change total volume

#### Initialization Options

**Option 1: HYCOM initialization (realistic)**
```julia
coupled_model = build_gom_hr_ocean_seaice_model(
    arch = arch,
    use_hycom = true,
)
```

**Option 2: Simple constant initialization (for testing)**
```julia
coupled_model = build_gom_hr_ocean_seaice_model(
    arch = arch,
    use_hycom = false,    # T=20°C, S=35 psu everywhere
)
```

---

## Troubleshooting

### Issue: CUDA/GPU not found

**Symptoms:** Simulation runs on CPU (very slow)

**Solution:**
```bash
# Check GPU availability
nvidia-smi

# Test CUDA.jl
julia -e "using CUDA; CUDA.versioninfo()"
```

If GPU exists but not detected, reinstall CUDA.jl:
```julia
using Pkg
Pkg.rm("CUDA")
Pkg.add("CUDA")
Pkg.build("CUDA")
```

---

### Issue: NaN values in T/S after initialization

**Symptoms:** Warning messages about NaNs in temperature/salinity

**Common causes:**
1. Vertical coordinate mismatch between HYCOM and model
2. Missing HYCOM data in coastal regions
3. Bathymetry inconsistencies

**Debug steps:**
```bash
# Check HYCOM initialization file
julia scripts/check_vertical_mismatch.jl

# Verify HYCOM data coverage
julia scripts/plot_hycom_TS.jl
```

**Solutions:**
- Ensure HYCOM vertical levels span model depth range
- Check `make_hycom_init_gom.py` coordinate transformations
- Increase `minimum_depth` in bathymetry config (e.g., 10m)
- Verify HYCOM source files have correct variables

---

### Issue: Simulation crashes with "domain error" in TEOS10

**Symptoms:** `DomainError` related to sqrt in seawater equation of state

**Cause:** Non-physical T/S values (negative salinity, extreme temperatures)

**Solution:**
The config already includes sanity checks. If still occurring:
```julia
# In initialize_TS_from_hycom! function:
T_f .= clamp.(T_f, -2.0, 40.0)     # °C
S_f .= clamp.(S_f, 1e-6, 42.0)     # psu (strictly positive)
```

---

### Issue: "File not found" errors

**Check these paths:**
```bash
# HYCOM initialization file exists?
ls -lh runs/hycom_init_gom.nc

# Output directory exists?
ls -ld runs/gom_hr_output/

# HYCOM source data exists?
ls -lh data/hycom/
```

**Fix:**
```bash
# Create directories if missing
mkdir -p runs data/hycom figures

# Re-run HYCOM preparation
julia scripts/dump_gom_grid.jl
python scripts/make_hycom_init_gom.py
```

---

### Issue: Out of memory (OOM) on GPU

**Symptoms:** CUDA out of memory error

**Solutions:**

1. **Reduce grid size** (in `configs/gom_config_hr.jl`):
   ```julia
   size = (240, 180, 25)  # Half resolution
   ```

2. **Reduce output frequency:**
   ```julia
   schedule = TimeInterval(7200.0)  # Every 2 hours
   ```

3. **Use CPU (slower):**
   ```julia
   arch = CPU()
   ```

---

### Issue: Plots have wrong geography

**Symptoms:** Gulf of Mexico shape looks incorrect

**Check:**
1. Longitude/latitude ranges in `dump_gom_grid.jl` match `gom_config_hr.jl`
2. Bathymetry is correctly regridded
3. Coordinate order is (longitude, latitude) not (latitude, longitude)

**Verify:**
```bash
julia scripts/plot_gom_hr_1day.jl
# Check bathymetry panel - should show Gulf bowl shape
```

---

### Issue: Animation fails to generate

**Common causes:**
1. Missing timeseries file
2. Plots.jl backend issues

**Solutions:**
```bash
# Verify timeseries exists
ls -lh runs/gom_hr_output/gom_hr_1day_timeseries.jld2

# Try different backend
export GKSwstype=100  # For headless systems

# Or use different plotting
julia --project scripts/plot_gom_hr_1day.jl  # Static plots only
```

---

## Performance Tips

### GPU Optimization

- **Batch size:** Default 20s timestep is optimized for stability
- **Output frequency:** Hourly output is a good balance
- **Memory:** Monitor with `nvidia-smi` during runs

### CPU Runs (Not Recommended)

If you must run on CPU:
- Reduce grid size: `(120, 90, 25)`
- Increase timestep: `Δt = 30.0` (less stable)
- Reduce output frequency
- Expect 10-100x slower than GPU

### Multi-day Runs

For longer simulations:
- Save daily instead of hourly: `TimeInterval(86400.0)`
- Use checkpointing for restarts
- Monitor for drift in conservation properties

---

## Additional Resources

### ClimaOcean Documentation
- [ClimaOcean.jl GitHub](https://github.com/CliMA/ClimaOcean.jl)
- [Oceananigans Documentation](https://clima.github.io/OceananigansDocumentation/stable/)

### Data Sources
- [HYCOM Gulf of Mexico](https://www.hycom.org/)
- [ETOPO2022 Bathymetry](https://www.ncei.noaa.gov/products/etopo-global-relief-model)
- [JRA55 Atmospheric Reanalysis](https://jra.kishou.go.jp/JRA-55/index_en.html)

### Citations

**ClimaOcean:**
> Wagner, G. L. et al. (2025). CliMA/ClimaOcean.jl. Zenodo. https://doi.org/10.5281/zenodo.7677442

**Oceananigans:**
> Wagner, G. L. et al. (2025). "High-level, high-resolution ocean modeling at all scales with Oceananigans." arXiv:2502.14148

---

## Contact & Support

For issues specific to this Gulf of Mexico configuration, check:
1. This README troubleshooting section
2. ClimaOcean.jl GitHub issues
3. Oceananigans Discussions

**Common workflow questions:**
- "How do I change the domain?" → Edit `configs/gom_config_hr.jl` and re-run `dump_gom_grid.jl`
- "Can I use different initialization?" → Set `use_hycom = false` or modify `initialize_TS_from_hycom!`
- "How do I run longer?" → Edit `stop_time_sim` in run script

---

*Last updated: 2026-02-06*
