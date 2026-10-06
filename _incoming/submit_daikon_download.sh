#!/bin/bash -l
#SBATCH --job-name=daikon-download
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:15:00

set -euo pipefail
cd /project/mjk76/ea442/promptstudy

curl -fSL -o daikon.jar https://plse.cs.washington.edu/daikon/download/daikon.jar

echo ">>> Downloaded daikon.jar:"
ls -la daikon.jar
