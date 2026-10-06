#!/bin/bash -l

#SBATCH --job-name=multisample-libgdx
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=03-00:00:00
#SBATCH --mem=128G

set -euo pipefail

########################################
# MAVEN
########################################

export MAVEN_HOME="/scratch/mjk76/$USER/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"

########################################
# JAVA
########################################

module load Java/23.0.2

########################################
# ENV
########################################

export ACCOUNT="mjk76"

export OPENAI_API_KEY="$(
  tr -d '[:space:]' < /project/mjk76/ea442/OPENAI_API_KEY.txt
)"

export ROOT="/project/mjk76/ea442/promptstudy"

# IMPORTANT: isolated worktree, NOT original checkout.
export DPP_DIR="/scratch/mjk76/$USER/daikonplusplus-relaxedAll"

########################################
# SANITY
########################################

echo "======================================"
echo "SLURM JOB ID: ${SLURM_JOB_ID:-unknown}"
echo "HOST: $(hostname)"
echo "START TIME: $(date)"
echo "ROOT: $ROOT"
echo "DPP_DIR: $DPP_DIR"
echo "JAVA: $(which java)"
echo "MVN: $(which mvn)"
echo "======================================"

cd "$ROOT"

bash "$ROOT/run_prompt_study_multisample_libgdx_only.sh"

echo
echo "======================================"
echo "RELAXEDALL PROMPT STUDY JOB FINISHED"
echo "FINISH TIME: $(date)"
echo "======================================"
