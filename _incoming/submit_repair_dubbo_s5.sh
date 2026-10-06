#!/bin/bash -l
#SBATCH --job-name=repair-dubbo-s5
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=01:00:00

set -euo pipefail
python3 /project/mjk76/ea442/promptstudy/repair_dtrace.py \
    /scratch/mjk76/ea442/promptstudy/dubbo-s5-chicory-out/latest/dtrace.gz \
    /scratch/mjk76/ea442/promptstudy/dubbo-s5-chicory-out/latest/dtrace-repaired.gz
