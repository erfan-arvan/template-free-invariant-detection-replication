#!/bin/bash -l
#SBATCH --job-name=prompt-csv
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:05:00
#SBATCH --mem=1G

set -euo pipefail

# Directory from which sbatch was executed
cd "$SLURM_SUBMIT_DIR"

echo "Host: $(hostname)"
echo "Start time: $(date)"
echo "Python: $(which python)"
python --version
echo "Working directory: $PWD"

python create_prompt_results_csv.py \
    "$SLURM_SUBMIT_DIR" \
    --output "$SLURM_SUBMIT_DIR/prompt_study_results.csv" \
    --compact-output "$SLURM_SUBMIT_DIR/prompt_study_results_compact.csv" \
    --exclude-project rxjava

echo "Created: $SLURM_SUBMIT_DIR/prompt_study_results.csv"
echo "End time: $(date)"
