#!/bin/bash -l

#SBATCH --job-name=token-cost-classdoc
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00
#SBATCH --mem=64G

set -euo pipefail

export MAVEN_HOME="/scratch/mjk76/$USER/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"

module load Java/23.0.2

export ACCOUNT=mjk76
export ROOT="/project/mjk76/ea442/promptstudy"
export DPP_DIR="/scratch/mjk76/$USER/daikonplusplus-token-cost"

cd "$ROOT"

echo "======================================"
echo "SLURM JOB ID: ${SLURM_JOB_ID:-unknown}"
echo "HOST: $(hostname)"
echo "START: $(date)"
echo "ROOT: $ROOT"
echo "DPP_DIR: $DPP_DIR"
echo "JAVA: $(which java)"
echo "======================================"

bash "$ROOT/run_token_cost_fewshot_class_doc.sh"
