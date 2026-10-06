#!/usr/bin/env bash
set -uo pipefail  

########################################
# PATHS
########################################
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="${ROOT:-$SCRIPT_DIR}"
HUDI_DIR="${HUDI_DIR:-$ROOT/hudi}"
DPP_DIR="${DPP_DIR:-$ROOT/daikonplusplus}"

MODULE="hudi-client/hudi-java-client"
MAIN_SRC="$MODULE/src/main/java"
TEST_SRC="$MODULE/src/test/java"

########################################
# HPC scratch
########################################
ACCOUNT="${ACCOUNT:-mjk76}"
SCRATCH_ROOT="/scratch/${ACCOUNT}/${USER}"
SCRATCH_BASE="${SCRATCH_ROOT}/token_cost_fewshot_class_doc"

mkdir -p "$SCRATCH_BASE"

export TMPDIR="${SCRATCH_BASE}/tmp"
export GRADLE_USER_HOME="${SCRATCH_BASE}/.gradle"
export DP_WORKDIR="${SCRATCH_BASE}/daikonpp_work"

mkdir -p "$TMPDIR" "$GRADLE_USER_HOME" "$DP_WORKDIR"

export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.io.tmpdir=${TMPDIR}"

########################################
# Maven config 
########################################
export MAVEN_HOME="/scratch/${ACCOUNT}/${USER}/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"
export MAVEN_OPTS="-Dmaven.repo.local=${SCRATCH_ROOT}/.m2"

echo "JAVA: $(which java)"
echo "MVN: $(which mvn)"

########################################
# LLM / Cassette config
########################################
export DP_LLM_CASSETTES="${DP_LLM_CASSETTES:-$DPP_DIR/src/test/cassettes}"

########################################
# Other configs
########################################
MAXK="${MAXK:-5}"

########################################
# Sanity checks
########################################
[[ -d "$HUDI_DIR" ]] || { echo "ERROR: Hudi repo not found: $HUDI_DIR"; exit 1; }
[[ -x "$DPP_DIR/gradlew" ]] || { echo "ERROR: Daikon++ repo not found: $DPP_DIR"; exit 1; }

########################################
# Use pre-built jar
########################################
DAIKONPP_JAR="${DP_DAIKONPP_JAR:?ERROR: DP_DAIKONPP_JAR not set}"

########################################
# External COMPILE script (IDENTICAL to laptop)
########################################
COMPILE_SCRIPT="$SCRATCH_BASE/hudi_compile.sh"

cat > "$COMPILE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

module load Java/17.0.15

cd "$DP_PROJECT_ROOT"

mvn \
  -pl hudi-client/hudi-java-client \
  -am \
  -DskipTests \
  -Dmaven.test.skip=true \
  -Dcheckstyle.skip=true \
  -Dcheckstyle.skipExec=true \
  -Denforcer.skip=true \
  -Drat.skip=true \
  compile
EOF

chmod +x "$COMPILE_SCRIPT"

export DP_COMPILE_MAIN_SCRIPT="$COMPILE_SCRIPT"
export DP_COMPILE_TEST_SCRIPT="$COMPILE_SCRIPT"

########################################
# External TEST runner (IDENTICAL to laptop)
########################################
RUNNER="$SCRATCH_BASE/hudi_run_tests.sh"

cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
set -e

module load Java/17.0.15

mvn -q \
  -pl hudi-client/hudi-java-client \
  -DskipITs \
  -Duser.timezone=UTC \
  -Dcheckstyle.skip=true \
  -Dcheckstyle.skipExec=true \
  -Denforcer.skip=true \
  -Drat.skip=true \
  test
EOF

chmod +x "$RUNNER"

export DP_EXTERNAL_CMD="$RUNNER"

########################################
# Minimal classpath (IDENTICAL to laptop)
########################################
export DP_EXTERNAL_COMPILE_CP="$HUDI_DIR/$MODULE/target/classes"

# Call sites
export DP_CALL_SITES_INDEX="/project/mjk76/ea442/promptstudy/hudi_callsites.json"

# I/O examples (few-shot examples rendered into the LLM prompt context)
export DP_IO_EXAMPLES_INDEX="/project/mjk76/ea442/promptstudy/hudi-s5_io_examples.json"

########################################
# Enable test-failure-based invariant filtering
########################################
#export DP_TEST_FILTER=true

########################################
# Run Daikon++ (IDENTICAL to laptop)
########################################
echo ">>> Running Daikon++"

cd "$HUDI_DIR"

CMD=(
  java -jar "$DAIKONPP_JAR"
  --external-project
  --project-root "$HUDI_DIR"
  --main-src "$MAIN_SRC"
  --test-src "$TEST_SRC"
  --runner-script "$RUNNER"
  "$MAXK"
)

echo ">>> CMD: ${CMD[*]}"
"${CMD[@]}"

echo ">>> Done."
