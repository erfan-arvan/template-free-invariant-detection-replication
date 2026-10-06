#!/usr/bin/env bash
set -uo pipefail

########################################
# PATHS
########################################
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="${ROOT:-$SCRIPT_DIR}"
NETTY_DIR="${NETTY_DIR:-$ROOT/netty}"
DPP_DIR="${DPP_DIR:-$ROOT/daikonplusplus}"

# ASSUMPTION: targeting "common" (foundational, low-dependency module --
# analogous to dubbo-common; good first pipeline smoke test). Note netty's
# modules are NOT prefixed with "netty-" on disk (it's just "common",
# "buffer", "transport", etc). Override DP_NETTY_MODULE to point at a
# different module (e.g. buffer, transport, codec-http) if needed.
MODULE="${DP_NETTY_MODULE:-common}"
MAIN_SRC="$MODULE/src/main/java"
TEST_SRC="$MODULE/src/test/java"

########################################
# HPC scratch
########################################
ACCOUNT="${ACCOUNT:-mjk76}"
SCRATCH_ROOT="/scratch/${ACCOUNT}/${USER}"
SCRATCH_BASE="${SCRATCH_ROOT}/promptstudy"

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

# Note: do NOT `module load` a specific Java version here. The mvn
# compile/test steps below load whatever JDK Netty needs themselves, inside
# their own heredoc scripts. The Daikon++ jar must run under whatever Java
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
[[ -d "$NETTY_DIR" ]] || { echo "ERROR: Netty repo not found: $NETTY_DIR"; exit 1; }
[[ -x "$DPP_DIR/gradlew" ]] || { echo "ERROR: Daikon++ repo not found: $DPP_DIR"; exit 1; }
[[ -d "$NETTY_DIR/$MODULE" ]] || { echo "ERROR: Module '$MODULE' not found under $NETTY_DIR"; exit 1; }

########################################
# Use pre-built jar
########################################
DAIKONPP_JAR="${DP_DAIKONPP_JAR:?ERROR: DP_DAIKONPP_JAR not set}"

########################################
# External COMPILE script (IDENTICAL to laptop)
########################################
COMPILE_SCRIPT="$SCRATCH_BASE/netty_${MODULE}_compile.sh"

cat > "$COMPILE_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# ASSUMPTION: Netty's current main branch build requires JDK 17. Adjust the
# module version below if you're targeting an older Netty branch/tag
# (e.g. the 4.1.x maintenance line, which builds fine under JDK 8/11).
module load Java/17.0.15

cd "\$DP_PROJECT_ROOT"

# Netty's pom (verified against netty/netty on 2026-08-06) has no
# Spotless, CheckerFramework, Apache RAT, animal-sniffer, or japicmp -- those
# flags below are no-ops here, kept only for parity with the Dubbo script.
# The plugins that DO run early enough to choke on injected/unformatted
# invariant code are:
#   - checkstyle:    bound to the "validate" phase (before compile)
#   - forbiddenapis: bound directly to the "compile" phase
#   - revapi:        not bound by default, but some profiles gate it on
#                     revapi.skip -- skip defensively
mvn \\
  -pl $MODULE \\
  -am \\
  -DskipTests \\
  -Dmaven.test.skip=true \\
  -Dcheckstyle.skip=true \\
  -Dcheckstyle.skipExec=true \\
  -Denforcer.skip=true \\
  -Dmaven.javadoc.skip=true \\
  -Dforbiddenapis.skip=true \\
  -Drevapi.skip=true \\
  compile
EOF

chmod +x "$COMPILE_SCRIPT"

export DP_COMPILE_MAIN_SCRIPT="$COMPILE_SCRIPT"
export DP_COMPILE_TEST_SCRIPT="$COMPILE_SCRIPT"

########################################
# External TEST runner (IDENTICAL to laptop)
########################################
RUNNER="$SCRATCH_BASE/netty_${MODULE}_run_tests.sh"

cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
set -e

module load Java/17.0.15

mvn -q \\
  -pl $MODULE \\
  -am \\
  -DskipITs \\
  -Duser.timezone=UTC \\
  -Dcheckstyle.skip=true \\
  -Dcheckstyle.skipExec=true \\
  -Denforcer.skip=true \\
  -Dmaven.javadoc.skip=true \\
  -Dforbiddenapis.skip=true \\
  -Drevapi.skip=true \\
  test
EOF

chmod +x "$RUNNER"

export DP_EXTERNAL_CMD="$RUNNER"

########################################
# Minimal classpath (IDENTICAL to laptop)
########################################
export DP_EXTERNAL_COMPILE_CP="$NETTY_DIR/$MODULE/target/classes"

########################################
# Project Root
########################################
export DP_PROJECT_ROOT="$NETTY_DIR"

# Call sites
export DP_CALL_SITES_INDEX="/project/${ACCOUNT}/${USER}/promptstudy/netty_callsites.json"
export DP_IO_EXAMPLES_INDEX="/project/mjk76/ea442/promptstudy/netty-s5_io_examples.json"

########################################
# Run Daikon++ (IDENTICAL to laptop)
########################################
echo ">>> Running Daikon++"

cd "$NETTY_DIR"

CMD=(
  java -jar "$DAIKONPP_JAR"
  --external-project
  --project-root "$NETTY_DIR"
  --main-src "$MAIN_SRC"
  --test-src "$TEST_SRC"
  --runner-script "$RUNNER"
  "$MAXK"
)

echo ">>> CMD: ${CMD[*]}"
"${CMD[@]}"

echo ">>> Done."
