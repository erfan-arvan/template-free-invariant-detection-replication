#!/bin/bash -l
#SBATCH --job-name=libgdx-full-io-examples
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=02:00:00

set -euo pipefail
cd /project/mjk76/ea442/promptstudy
source ./lib_io_examples_full_common.sh

OUT_DIR="/scratch/mjk76/ea442/promptstudy"

# job 1280644's full trace script DOES update "latest" on success (unlike
# netty/hudi's crashed old runs), so this is safe to use once that job
# finishes.
run_io_examples_full \
  "libgdx-full" \
  "${OUT_DIR}/libgdx-full-chicory-out/latest/dtrace.gz" \
  "${OUT_DIR}/libgdx-full-chicory/gdx/src" \
  "${OUT_DIR}" \
  "Java/17.0.15" \
  "/project/mjk76/ea442/promptstudy/io-examples-tool.jar"
