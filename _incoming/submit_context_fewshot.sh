#!/bin/bash -l
#SBATCH --job-name=contextstudy-fewshot
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

# Optional: load modules if your cluster needs them
# module purge
# module load java
# module load maven

export MAVEN_HOME="/scratch/mjk76/$USER/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"

module load Java/23.0.2

# optional sanity print (very useful)
echo "JAVA: $(which java)"
echo "MVN: $(which mvn)"

export ACCOUNT="mjk76"
export OPENAI_API_KEY="REDACTED"

export ROOT="$PWD"
export DPP_DIR="$ROOT/daikonplusplus"
export HUDI_DIR="$ROOT/hudi"

# Better: export before sbatch, or source from a protected file
# source ~/.openai_key
# export OPENAI_API_KEY

./run_context_study_fewshot.sh
