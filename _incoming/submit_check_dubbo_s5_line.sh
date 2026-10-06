#!/bin/bash -l
#SBATCH --job-name=check-dubbo-s5-line
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=00:30:00

set -uo pipefail

TRACE=/scratch/mjk76/ea442/promptstudy/dubbo-s5-chicory-out/latest/dtrace.gz

echo ">>> lines 46759620-46759645 (around the reported error)"
zcat "$TRACE" | sed -n '46759620,46759645p'

echo
echo ">>> total line count in file"
zcat "$TRACE" | wc -l
