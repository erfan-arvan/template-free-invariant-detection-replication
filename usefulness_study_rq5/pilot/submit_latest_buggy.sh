#!/bin/bash
#SBATCH --job-name=latest-buggy
#SBATCH --output=%x.%A_%a.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=200G
#SBATCH --time=72:00:00
#SBATCH --array=0-15

set -euo pipefail
: "${OCA_JAR:?}" "${DAIKON_JAR:?}" "${JUNIT_JAR:?}" "${OPENAI_API_KEY:?}"
PROJECTS=(Cli Closure Codec Collections Compress Csv Gson JacksonCore JacksonDatabind JacksonXml Jsoup JxPath Lang Math Mockito Time)
PROJECT="${PROJECTS[$SLURM_ARRAY_TASK_ID]}"
python3 run_oca.py "$PROJECT" --version b
python3 run_daikon.py "$PROJECT" --version b
