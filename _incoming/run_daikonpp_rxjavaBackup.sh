#!/usr/bin/env bash
set -uo pipefail

########################################
# PATHS
########################################
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="${ROOT:-$SCRIPT_DIR}"
RXJAVA_DIR="${RXJAVA_DIR:-$ROOT/rxjava}"
DPP_DIR="${DPP_DIR:-$ROOT/daikonplusplus}"

MAIN_SRC="src/main/java"
TEST_SRC="src/test/java"

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
[[ -d "$RXJAVA_DIR" ]] || { echo "ERROR: RxJava repo not found: $RXJAVA_DIR"; exit 1; }
[[ -x "$DPP_DIR/gradlew" ]] || { echo "ERROR: Daikon++ repo not found: $DPP_DIR"; exit 1; }

########################################
# Use pre-built jar
########################################
DAIKONPP_JAR="${DP_DAIKONPP_JAR:?ERROR: DP_DAIKONPP_JAR not set}"

########################################
# Helper scripts (SCRATCH)
########################################
COMPILE_SCRIPT="$SCRATCH_BASE/rxjava_compile.sh"
RUNNER="$SCRATCH_BASE/rxjava_run_tests.sh"

########################################
# Compile script
########################################
cat > "$COMPILE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export JDK_EXPERIMENTAL=23

cd "$DP_PROJECT_ROOT"

# Clean + compile ONLY (no tests yet)
./gradlew clean classes --no-daemon --no-build-cache
EOF
chmod +x "$COMPILE_SCRIPT"

########################################
# Runner script (CRITICAL)
# Skips already-executed test classes on reruns via a Gradle init script
# that excludes their .class files.
########################################
cat > "$RUNNER" <<'OUTEREOF'
#!/usr/bin/env bash
set -euo pipefail

export JDK_EXPERIMENTAL=23
export GRADLE_OPTS="${GRADLE_OPTS:-} -Xmx1g"
export _JAVA_OPTIONS="${_JAVA_OPTIONS:-} -Drx4.cached-keep-alive-time=86400"

# CWD is the daikonpp-injected work copy — all paths relative to it.
PASSED_FILE=".daikonpp-passed-tests.txt"
EXCLUDE_SCRIPT=".daikonpp-exclude.gradle"
RESULTS_DIR="build/test-results/test"

cat > "$EXCLUDE_SCRIPT" <<'GRADLEEOF'
allprojects {
    tasks.withType(Test) {
        failOnNoDiscoveredTests = false
        def passedFile = rootProject.file(".daikonpp-passed-tests.txt")
        if (passedFile.exists()) {
            passedFile.readLines().each { cls ->
                exclude cls.replace('.', '/') + '.class'
            }
        }
    }
}
GRADLEEOF

SKIP_COUNT=0
if [[ -f "$PASSED_FILE" ]]; then
    SKIP_COUNT=$(wc -l < "$PASSED_FILE" | tr -d ' ')
fi

if [[ $SKIP_COUNT -eq 0 ]]; then
    echo "[DP] First run — executing full test suite."
else
    echo "[DP] Excluding $SKIP_COUNT already-executed class(es) via Gradle init script."
fi

parse_fully_executed() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    python3 - "$dir" <<'PYEOF'
import sys, os, xml.etree.ElementTree as ET
d = sys.argv[1]
for fn in sorted(os.listdir(d)):
    if not fn.endswith('.xml'):
        continue
    try:
        root = ET.parse(os.path.join(d, fn)).getroot()
        tests = int(root.get('tests', 0))
        name  = root.get('name', '').strip()
        if name and tests > 0:
            print(name)
    except Exception:
        pass
PYEOF
}

./gradlew test --no-daemon --max-workers=1 \
  -Dorg.gradle.jvmargs="-Xmx1g" \
  -PmaxParallelForks=1 \
  --console=plain \
  --info \
  -I "$EXCLUDE_SCRIPT"

GRADLE_EXIT=$?

declare -A ALREADY_PASSED=()
if [[ -f "$PASSED_FILE" ]]; then
    while IFS= read -r cls; do
        [[ -n "$cls" ]] && ALREADY_PASSED["$cls"]=1
    done < "$PASSED_FILE"
fi

while IFS= read -r cls; do
    if [[ -z "${ALREADY_PASSED[$cls]+_}" ]]; then
        echo "[DP] Newly executed: $cls"
        echo "$cls" >> "$PASSED_FILE"
        ALREADY_PASSED["$cls"]=1
    fi
done < <(parse_fully_executed "$RESULTS_DIR")

[[ -f "$PASSED_FILE" ]] && sort -u "$PASSED_FILE" -o "$PASSED_FILE"

exit $GRADLE_EXIT
OUTEREOF
chmod +x "$RUNNER"

export DP_COMPILE_MAIN_SCRIPT="$COMPILE_SCRIPT"
export DP_COMPILE_TEST_SCRIPT="$COMPILE_SCRIPT"
export DP_EXTERNAL_CMD="$RUNNER"

########################################
# Classpath (CRITICAL for Daikon++)
########################################
export DP_EXTERNAL_COMPILE_CP="$RXJAVA_DIR/build/classes/java/main:$RXJAVA_DIR/build/resources/main"

########################################
# Project root
########################################
export DP_PROJECT_ROOT="$RXJAVA_DIR"

########################################
# Scan filtering (STRICT)
########################################
export DP_SCAN_INCLUDES="io.reactivex.rxjava4.internal"


########################################
# Enable test-failure-based invariant filtering
########################################
export DP_TEST_FILTER=true


# call sites
# RxJava
export DP_CALL_SITES_INDEX="/project/mjk76/ea442/promptstudy/rxjava_callsites.json"
########################################
# Run Daikon++
########################################
echo "======================================"
echo ">>> Running Daikon++ on RxJava"
echo "======================================"

CMD=(
  java -jar "$DAIKONPP_JAR"
  --external-project
  --project-root "$RXJAVA_DIR"
  --main-src "$MAIN_SRC"
  --test-src "$TEST_SRC"
  --runner-script "$RUNNER"
  "$MAXK"
)

echo ">>> CMD: ${CMD[*]}"
"${CMD[@]}"

echo ">>> Done."
