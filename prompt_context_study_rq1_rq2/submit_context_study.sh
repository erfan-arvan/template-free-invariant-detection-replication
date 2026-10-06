#!/bin/bash -l
#SBATCH --job-name=contextstudy
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=03-00:00:00
#SBATCH --mem=128G

set -euo pipefail

echo "JAVA: $(which java)"
echo "MVN: $(which mvn)"

: "${OPENAI_API_KEY:?export OPENAI_API_KEY before submitting}"

export ROOT="$PWD"
export OCA_DIR="$ROOT/oca-artifact"
export HUDI_DIR="$ROOT/hudi"

./run_context_study.sh
