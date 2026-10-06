#!/bin/bash -l
#SBATCH --job-name=io-examples-libgdx
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=08:00:00

set -euo pipefail
cd /project/mjk76/ea442/promptstudy
source ./lib_io_examples_common.sh

IO_JAR="/project/mjk76/ea442/promptstudy/io-examples-tool.jar"
OUT_DIR="/scratch/mjk76/ea442/promptstudy"

run_io_examples "libgdx-s5" "$OUT_DIR/libgdx-s5-chicory/gdx/src" "$OUT_DIR/libgdx-s5-chicory-out/dtrace.gz" "$OUT_DIR" "Java/17.0.15" "$IO_JAR"
