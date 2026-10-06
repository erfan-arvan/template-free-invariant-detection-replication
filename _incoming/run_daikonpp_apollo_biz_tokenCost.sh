#!/usr/bin/env bash
set -uo pipefail

########################################
# PATHS
########################################
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="${ROOT:-$SCRIPT_DIR}"
APOLLO_DIR="${APOLLO_DIR:-$ROOT/apollo}"
DPP_DIR="${DPP_DIR:-$ROOT/daikonplusplus}"

MODULE="apollo-biz"
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

# Note: do NOT `module load Java/17.0.15` here. The mvn compile/test steps
# below load Java 17 themselves inside their own heredoc scripts (Apollo's
# build requirement). The Daikon++ jar itself must run under whatever Java
# built it (loaded by the caller, e.g. submit.sh) -- switching java on the
# PATH here would downgrade that final `java -jar` invocation too.
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
[[ -d "$APOLLO_DIR" ]] || { echo "ERROR: Apollo repo not found: $APOLLO_DIR"; exit 1; }
[[ -x "$DPP_DIR/gradlew" ]] || { echo "ERROR: Daikon++ repo not found: $DPP_DIR"; exit 1; }

########################################
# Use pre-built jar
########################################
DAIKONPP_JAR="${DP_DAIKONPP_JAR:?ERROR: DP_DAIKONPP_JAR not set}"

########################################
# External COMPILE script (IDENTICAL to laptop)
########################################
COMPILE_SCRIPT="$SCRATCH_BASE/apollo_biz_compile.sh"

cat > "$COMPILE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

module load Java/17.0.15

cd "$DP_PROJECT_ROOT"

mvn \
  -pl apollo-biz \
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
RUNNER="$SCRATCH_BASE/apollo_biz_run_tests.sh"

cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
set -e

module load Java/17.0.15

mvn -q \
  -pl apollo-biz \
  -am \
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
export DP_EXTERNAL_COMPILE_CP="$APOLLO_DIR/$MODULE/target/classes"

########################################
# Project Root
########################################
export DP_PROJECT_ROOT="$APOLLO_DIR"

# Call sites
export DP_CALL_SITES_INDEX="/project/${ACCOUNT}/${USER}/promptstudy/apollo_callsites.json"
export DP_IO_EXAMPLES_INDEX="/project/mjk76/ea442/promptstudy/apollo-s5_io_examples.json"

########################################
# Run Daikon++ (IDENTICAL to laptop)
########################################
echo ">>> Running Daikon++"

cd "$APOLLO_DIR"

CMD=(
  java -jar "$DAIKONPP_JAR"
  --external-project
  --project-root "$APOLLO_DIR"
  --main-src "$MAIN_SRC"
  --test-src "$TEST_SRC"
  --runner-script "$RUNNER"
  "$MAXK"
)

echo ">>> CMD: ${CMD[*]}"
"${CMD[@]}"

echo ">>> Done."
