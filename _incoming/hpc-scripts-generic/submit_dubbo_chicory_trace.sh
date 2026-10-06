#!/bin/bash -l
#SBATCH --job-name=dubbo-chicory-trace
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=192G
#SBATCH --time=48:00:00

set -euo pipefail
cd /project/mjk76/ea442/promptstudy
source ./lib_chicory_common.sh

DAIKON_JAR="/project/mjk76/ea442/promptstudy/daikon.jar"
DUBBO_DIR="/project/mjk76/ea442/promptstudy/dubbo"
OUT_DIR="/project/mjk76/ea442/promptstudy"

export MAVEN_HOME="/scratch/mjk76/${USER}/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"
export MAVEN_OPTS="-Xmx16g -Dmaven.repo.local=/scratch/mjk76/${USER}/.m2"

# Same module your run_daikonpp_dubbo.sh already targets (dubbo-common by
# default, override via DP_DUBBO_MODULE) -- keeps traced methods aligned
# with what your own pipeline actually processes.
MODULE="${DP_DUBBO_MODULE:-dubbo-common}"

# No project-specific VerifyError classes known yet -- this is dubbo's first
# Chicory run. If you see "Expecting a stack map frame" crashes in the .err
# for a specific dubbo class (same pattern as HoodieFieldOrder/HoodieTableType
# on hudi), add it here (e.g. "SomeClass|OtherClass") and resubmit.
PPT_OMIT_EXTRA=""

# Mirrors dubbo's own compile/test skip flags from run_daikonpp_dubbo.sh.
MVN_SKIP_FLAGS=(
  -Dmaven.test.skip=true
  -Dcheckstyle.skip=true
  -Dcheckstyle.skipExec=true
  -Denforcer.skip=true
  -Drat.skip=true
  -Dmaven.javadoc.skip=true
  -Dlicense.skip=true
  -Dspotless.check.skip=true
)

run_chicory_trace \
  "dubbo" "$DUBBO_DIR" "$MODULE" "Java/17.0.15" \
  "$DAIKON_JAR" "$OUT_DIR" "$PPT_OMIT_EXTRA" \
  "${MVN_SKIP_FLAGS[@]}"
