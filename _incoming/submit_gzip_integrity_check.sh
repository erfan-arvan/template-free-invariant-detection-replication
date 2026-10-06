#!/bin/bash -l
#SBATCH --job-name=gzip-integrity-check
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=04:00:00

set -uo pipefail

echo "=== dubbo ==="
gzip -t /scratch/mjk76/ea442/promptstudy/dubbo-chicory-out/1280625/dtrace.gz
echo "dubbo exit: $?"

echo "=== libgdx ==="
gzip -t /scratch/mjk76/ea442/promptstudy/libgdx-full-chicory-out/1280644/dtrace.gz
echo "libgdx exit: $?"
