#!/bin/bash
#SBATCH --job-name=usefulness
#SBATCH --output=%x.%A_%a.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=200G
#SBATCH --time=72:00:00
#SBATCH --array=0-24

set -euo pipefail
: "${OCA_JAR:?}" "${DAIKON_JAR:?}" "${JUNIT_JAR:?}" "${OPENAI_API_KEY:?}"
LINE=$(sed -n "$((SLURM_ARRAY_TASK_ID + 2))p" bugs.csv)
PROJECT="${LINE%%,*}"
BUG="${LINE##*,}"
python3 oca_usefulness.py "$PROJECT" "$BUG"
python3 daikon_usefulness.py "$PROJECT" "$BUG"
