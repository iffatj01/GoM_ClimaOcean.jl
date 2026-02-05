cat > runs/test_climaocean_global.slurm << 'EOF'
#!/bin/bash
#SBATCH --job-name=test_climao
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --output=logs/test_climao_%j.out
#SBATCH --error=logs/test_climao_%j.err

module load julia/1.12.2
module load cuda/12.2   # adjust to pamd

cd $HOME/GoM_ClimaOcean.jl

julia --project=. scripts/test_climaocean_global.jl
EOF
