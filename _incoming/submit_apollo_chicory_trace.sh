#!/bin/bash -l
#SBATCH --job-name=apollo-chicory-trace
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=192G
#SBATCH --time=72:00:00

set -euo pipefail
cd /project/mjk76/ea442/promptstudy
source ./lib_chicory_common.sh

DAIKON_JAR="/project/mjk76/ea442/promptstudy/daikon.jar"
APOLLO_DIR="/project/mjk76/ea442/promptstudy/apollo"
OUT_DIR="/scratch/mjk76/ea442/promptstudy"

export MAVEN_HOME="/scratch/mjk76/${USER}/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"
export MAVEN_OPTS="-Xmx16g -Dmaven.repo.local=/scratch/mjk76/${USER}/.m2"

# Same module your run_daikonpp_apollo_biz.sh already targets.
MODULE="apollo-biz"

# No project-specific VerifyError classes known yet -- this is apollo's
# first Chicory run. If you see "Expecting a stack map frame" crashes in the
# .err for a specific apollo class, add it here (e.g. "SomeClass|OtherClass")
# and resubmit.
PPT_OMIT_EXTRA=""

# Two SEPARATE flag sets copied exactly from run_daikonpp_apollo_biz.sh's two
# scripts. -Dmaven.test.skip=true belongs ONLY on the compile/install step --
# it makes Surefire skip tests unconditionally, so it must NOT appear in
# TEST_SKIP_FLAGS or nothing will ever actually run (this is exactly what
# happened the first time: both sets got merged and the flag leaked into the
# test invocation, silently skipping every test with no error printed).
#
# job 1219430: real tests ran (144 tests, all passing) and Chicory's
# javaagent was visibly attached in the argLine dump, but apollo.dtrace came
# back with only 5 lines / 124 bytes -- essentially nothing captured despite
# genuine test execution. Apollo's pom wires in JaCoCo (code coverage) as a
# javaagent via the jacoco-maven-plugin's prepare-agent goal, which PREPENDS
# its own -javaagent ahead of ours in the same argLine ("-javaagent:.../
# jacoco...=... \"-javaagent:.../daikon.jar=...\" -Xmx48g" -- confirmed in
# the log). JVM instrumentation chains multiple registered
# ClassFileTransformers in registration order, each seeing the PREVIOUS
# one's output -- so Chicory's BCEL-based transformer was operating on
# bytecode JaCoCo had already instrumented, not the original. -Djacoco.skip
# disables jacoco-maven-plugin entirely (its prepare-agent goal becomes a
# no-op), leaving Chicory as the only javaagent, on original bytecode.
INSTALL_SKIP_FLAGS=(
  -Dmaven.test.skip=true
  -Dcheckstyle.skip=true
  -Dcheckstyle.skipExec=true
  -Denforcer.skip=true
  -Drat.skip=true
  -Djacoco.skip=true
)
TEST_SKIP_FLAGS=(
  -Dcheckstyle.skip=true
  -Dcheckstyle.skipExec=true
  -Denforcer.skip=true
  -Drat.skip=true
  -Djacoco.skip=true
)

run_chicory_trace \
  "apollo" "$APOLLO_DIR" "$MODULE" "Java/17.0.15" \
  "$DAIKON_JAR" "$OUT_DIR" "$PPT_OMIT_EXTRA" \
  "${INSTALL_SKIP_FLAGS[@]}" ---TEST--- "${TEST_SKIP_FLAGS[@]}"
