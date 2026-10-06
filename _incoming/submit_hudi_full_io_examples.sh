#!/bin/bash -l
#SBATCH --job-name=hudi-full-io-examples
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

# job 1260714's run crashed at the (now-removed) combine step before reaching
# the "ln -sfn latest" line, so use the real job dir directly. Also note: this
# lives under "hudi-chicory-out" (not "hudi-full-chicory-out") -- a naming
# bug in the full trace script's TRACE_BASE_DIR found earlier, harmless since
# the job-ID subfolder still makes it unique from the sampled run.
run_io_examples_full \
  "hudi-full" \
  "/scratch/mjk76/ea442/promptstudy/hudi-chicory-out/1260714/dtrace.gz" \
  "/project/mjk76/ea442/promptstudy/hudi/hudi-client/hudi-java-client/src/main/java" \
  "/project/mjk76/ea442/promptstudy" \
  "Java/17.0.15" \
  "/project/mjk76/ea442/promptstudy/io-examples-tool.jar"
