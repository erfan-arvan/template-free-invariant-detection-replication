#!/usr/bin/env bash
set -uo pipefail   # same as your working Hudi script

########################################
# PATHS
########################################
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="${ROOT:-$SCRIPT_DIR}"
LIBGDX_DIR="${LIBGDX_DIR:-$ROOT/libgdx}"
DPP_DIR="${DPP_DIR:-$ROOT/daikonplusplus}"

MODULE="gdx"
MAIN_SRC="$MODULE/src"
TEST_SRC="tests/gdx-tests/src"

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
# LLM / Cassette config
########################################
export DP_LLM_CASSETTES="${DP_LLM_CASSETTES:-$DPP_DIR/src/test/cassettes}"

########################################
# Other Configs
########################################
MAXK="${MAXK:-5}"

########################################
# Sanity checks
########################################
[[ -d "$LIBGDX_DIR" ]] || { echo "ERROR: libGDX repo not found: $LIBGDX_DIR"; exit 1; }
[[ -x "$DPP_DIR/gradlew" ]] || { echo "ERROR: Daikon++ repo not found: $DPP_DIR"; exit 1; }

########################################
# Use pre-built jar
########################################
DAIKONPP_JAR="${DP_DAIKONPP_JAR:?ERROR: DP_DAIKONPP_JAR not set}"

########################################
# Helper scripts (SCRATCH, NOT /tmp)
########################################
COMPILE_SCRIPT="$SCRATCH_BASE/libgdx_compile.sh"
RUNNER="$SCRATCH_BASE/libgdx_run_tests.sh"

cat > "$COMPILE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "$DP_PROJECT_ROOT"

./gradlew clean :gdx:compileJava --no-daemon
EOF
chmod +x "$COMPILE_SCRIPT"

cat > "$RUNNER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

./gradlew :gdx:test --no-daemon --info
EOF
chmod +x "$RUNNER"

export DP_COMPILE_MAIN_SCRIPT="$COMPILE_SCRIPT"
export DP_COMPILE_TEST_SCRIPT="$COMPILE_SCRIPT"
export DP_EXTERNAL_CMD="$RUNNER"

########################################
# Classpath (IMPORTANT)
########################################
export DP_EXTERNAL_COMPILE_CP="$LIBGDX_DIR/gdx/build/classes/java/main:$LIBGDX_DIR/gdx/build/resources/main"

########################################
# Project Root
########################################
export DP_PROJECT_ROOT="$LIBGDX_DIR"

########################################
# Scan filtering (STRICT)
# Restrict invariant generation to JVM-safe, test-heavy core packages
# Avoids platform-specific modules (graphics, backends, GWT, Android)
########################################

export DP_SCAN_INCLUDES="com.badlogic.gdx.utils,com.badlogic.gdx.math"

# call sites
# LibGDX
export DP_CALL_SITES_INDEX="/project/mjk76/ea442/promptstudy/libgdx_callsites.json"
export DP_IO_EXAMPLES_INDEX="/project/mjk76/ea442/promptstudy/libgdx-s5_io_examples.json"
########################################
# Run Daikon++
########################################
echo "======================================"
echo ">>> Running Daikon++ on libGDX"
echo "======================================"

CMD=(
  java -jar "$DAIKONPP_JAR"
  --external-project
  --project-root "$LIBGDX_DIR"
  --main-src "$MAIN_SRC"
  --test-src "$TEST_SRC"
  --runner-script "$RUNNER"
  "$MAXK"
)

echo ">>> CMD: ${CMD[*]}"
"${CMD[@]}"

echo ">>> Done."
