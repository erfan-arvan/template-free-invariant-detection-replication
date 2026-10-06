#!/bin/bash -l
#SBATCH --job-name=count-daikon
#SBATCH --output=count-daikon.%A_%a.out
#SBATCH --error=count-daikon.%A_%a.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --array=0-5%2

set -euo pipefail
cd /project/mjk76/ea442/promptstudy
module load Java/23.0.2

files=(
  apollo-daikon-out/apollo.inv.gz
  dubbo-s5-daikon-quickfix-out/dubbo-s5-quickfix.inv.gz
  netty-s5-daikon-quickfix-out/netty-s5-quickfix.inv.gz
  hudi-daikon-out/hudi.inv.gz
  libgdx-s5-daikon-out/libgdx-s5.inv.gz
  spring-daikon-out/spring.inv.gz
)

file="${files[$SLURM_ARRAY_TASK_ID]}"
test -s "$file"

work="${SLURM_TMPDIR:-/tmp}/count-daikon-${SLURM_JOB_ID}"
mkdir -p "$work"
javac -cp daikon.jar -d "$work" CountDaikonInvariants.java
java -Xmx48g -cp "$work:daikon.jar" CountDaikonInvariants "$file"
