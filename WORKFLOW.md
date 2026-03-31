## Data and Workflow shortly

### `data/`
This directory stores the external input data, primarily the HYCOM ocean files used to construct the model initial condition.

### `scripts/dump_gom_grid.jl` https://github.com/iffatj01/GoM_ClimaOcean.jl/blob/main/scripts/dump_gom_grid.jl
This script generates the model grid file `runs/gom_hr_grid.nc`, which contains the target longitude, latitude, and vertical coordinate (`z`) values for the Gulf of Mexico domain. This grid defines the target geometry used by the rest of the workflow.

### `scripts/make_hycom_init_gom.py` https://github.com/iffatj01/GoM_ClimaOcean.jl/blob/main/scripts/make_hycom_init.py
This script reads the HYCOM source data from `data/`, interpolates it onto the model grid defined in `gom_hr_grid.nc`, and writes the result to `runs/hycom_init_gom.nc`. The output file contains the Oceananigans initial fields, including temperature (`T`), salinity (`S`), sea surface height (`η`), and, when available, velocity components (`u`, `v`).

### `scripts/run_gom_hr_1day.jl` https://github.com/iffatj01/GoM_ClimaOcean.jl/blob/main/scripts/run_gom_hr_1day.jl
This script builds the Oceananigans/ClimaOcean model, reads `hycom_init_gom.nc` for initialization, applies the current extended-domain sponge configuration together with atmospheric forcing, runs the simulation for 1 day, and writes model outputs to `runs/gom_hr_output/`.

### One-line workflow summary
HYCOM data in `data/` are regridded onto the Gulf of Mexico model grid using `dump_gom_grid.jl` and `make_hycom_init_gom.py`; then `run_gom_hr_1day.jl` uses that initialized state to run the 1-day Oceananigans simulation and save diagnostics and output files.
