#!/bin/bash -l
#SBATCH --job-name=count-daikon
#SBATCH --output=count-daikon.%A_%a.out
#SBATCH --error=count-daikon.%A_%a.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --array=0-5%2

set -euo pipefail
: "${DAIKON_JAR:?set DAIKON_JAR to daikon.jar}"

files=(
  apollo-daikon-out/apollo.inv.gz
  dubbo-s5-daikon-out/dubbo-s5.inv.gz
  netty-s5-daikon-out/netty-s5.inv.gz
  hudi-daikon-out/hudi.inv.gz
  libgdx-s5-daikon-out/libgdx-s5.inv.gz
  spring-daikon-out/spring.inv.gz
)

file="${files[$SLURM_ARRAY_TASK_ID]}"
test -s "$file"

work="${SLURM_TMPDIR:-/tmp}/count-daikon-${SLURM_JOB_ID}"
mkdir -p "$work"
javac -cp "$DAIKON_JAR" -d "$work" "$(dirname "$0")/CountDaikonInvariants.java"
java -Xmx48g -cp "$work:$DAIKON_JAR" CountDaikonInvariants "$file"
