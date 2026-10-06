#!/bin/bash -l

#SBATCH --job-name=contextstudy-fewshot-qfrelaxed-all
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
# SANITY CHECK
########################################

echo "======================================"
echo "SLURM JOB ID: ${SLURM_JOB_ID:-unknown}"
echo "HOST: $(hostname)"
echo "START TIME: $(date)"
echo "WORKING DIRECTORY: $PWD"
echo "JAVA: $(which java)"
echo "JAVA VERSION:"
java -version
echo "MVN: $(which mvn)"
echo "MVN VERSION:"
mvn -version
echo "======================================"

########################################
# ACCOUNT / API KEY
########################################

export ACCOUNT="mjk76"

export OPENAI_API_KEY="$(
  tr -d '[:space:]' < /project/mjk76/ea442/OPENAI_API_KEY.txt
)"

########################################
# PROJECT PATHS
########################################

export ROOT="$PWD"
export DPP_DIR="$ROOT/daikonplusplus"

########################################
# RUN FULL CONTEXT STUDY
########################################

echo "Starting full few-shot relaxed-QF context study..."
echo "ROOT: $ROOT"
echo "SCRIPT: $ROOT/resultsOfContextStudyFewshotQfRelaxedAll.sh"
echo

bash "$ROOT/resultsOfContextStudyFewshotQfRelaxedAll.sh"

echo
echo "======================================"
echo "CONTEXT STUDY JOB FINISHED"
echo "FINISH TIME: $(date)"
echo "======================================"
