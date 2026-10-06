#!/bin/bash -l
#SBATCH --job-name=netty-full-io-examples
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=04:00:00

set -euo pipefail
cd /project/mjk76/ea442/promptstudy
source ./lib_io_examples_full_common.sh

MODULE="${DP_NETTY_MODULE:-common}"

# job 1260712's run crashed at the (now-removed) combine step before reaching
# the "ln -sfn latest" line, so "latest" doesn't point at it -- use the real
# job dir directly. dtrace.gz itself (the actual Chicory output) is intact.
run_io_examples_full \
  "netty-full" \
  "/scratch/mjk76/ea442/promptstudy/netty-chicory-out/1260712/dtrace.gz" \
  "/project/mjk76/ea442/promptstudy/netty/${MODULE}/src/main/java" \
  "/project/mjk76/ea442/promptstudy" \
  "Java/17.0.15" \
  "/project/mjk76/ea442/promptstudy/io-examples-tool.jar"
