#!/bin/bash -l
#SBATCH --job-name=dubbo-full-io-examples
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

MODULE="${DP_DUBBO_MODULE:-dubbo-common}"

run_io_examples_full \
  "dubbo-full" \
  "/scratch/mjk76/ea442/promptstudy/dubbo-chicory-out/latest/dtrace.gz" \
  "/project/mjk76/ea442/promptstudy/dubbo/${MODULE}/src/main/java" \
  "/project/mjk76/ea442/promptstudy" \
  "Java/17.0.15" \
  "/project/mjk76/ea442/promptstudy/io-examples-tool.jar"
