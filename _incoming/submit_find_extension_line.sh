#!/bin/bash -l
#SBATCH --job-name=find-extension-line
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=00:30:00

set -euo pipefail

TRACE=/scratch/mjk76/ea442/promptstudy/spring-full-chicory-out/latest/dtrace.gz

echo ">>> searching for malformed 'parent' decl lines containing 'extension'"
zgrep -B3 -A1 "^parent.*extension" "$TRACE" | head -60

echo
echo ">>> also checking overall count"
zgrep -c "^parent.*extension" "$TRACE" || true
