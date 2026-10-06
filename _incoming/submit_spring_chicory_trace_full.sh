#!/bin/bash -l
#SBATCH --job-name=spring-chicory-trace-full
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

# Verified working jar -- built for JDK 25, contains Instrument24.class.
# Do NOT point this back at the old daikon.jar (that was the original bug
# that caused ClassNotFoundException: daikon.chicory.Instrument24).
DAIKON_JAR="/project/mjk76/ea442/promptstudy/daikon-spring-jdk25.jar"
SPRING_DIR="/project/mjk76/ea442/promptstudy/spring-framework"
OUT_DIR="/scratch/mjk76/ea442/promptstudy"
MODULE="${DP_SPRING_MODULE:-spring-core}"
PROJECT_NAME="spring-full"

_now() { date +%s; }
_timing() {
    local label="$1" start="$2" end
    end=$(date +%s)
    printf '[TIMING] %-28s %ds  (%s -> %s)\n' \
        "$label" "$((end - start))" \
        "$(date -d "@$start" +%T)" "$(date -d "@$end" +%T)"
    printf '%s\t%s\t%s\t%ds\t%s\t%s\t%s\n' \
        "$(date -Iseconds)" "$PROJECT_NAME" "${SLURM_JOB_ID:-nojob}" \
        "$((end - start))" "$label" \
        "$(date -d "@$start" -Iseconds)" "$(date -d "@$end" -Iseconds)" \
        >> "${OUT_DIR}/chicory_timing.log"
}
RUN_START=$(_now)
echo "[TIMING] === ${PROJECT_NAME} chicory trace run started $(date -Iseconds) ==="

TRACE_BASE_DIR="${OUT_DIR}/spring-full-chicory-out"
RUN_ID="${SLURM_JOB_ID:-$(date +%Y%m%d-%H%M%S)}"
TRACE_OUT_DIR="${TRACE_BASE_DIR}/${RUN_ID}"
mkdir -p "$TRACE_OUT_DIR"

WORK_DIR="${OUT_DIR}/spring-full-chicory"

# Separate Gradle user home from the -s5 job's, so a concurrent or
# interleaved run can never collide on cache/lock state (this is exactly
# what caused the spurious buildSrc configuration failure during the -s5
# diagnostic run).
GRADLE_HOME_DIR="${OUT_DIR}/spring-full-gradle-home"

mkdir -p "$GRADLE_HOME_DIR"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
rsync -a --delete --exclude='.git' --exclude='/*/build/' --exclude='.gradle' "${SPRING_DIR}/" "${WORK_DIR}/"

# spring-core's Gradle toolchain pins JDK 25, and there's no `module load
# Java/25` on this cluster -- self-provision it the same way the -s5 script
# does (Eclipse Temurin 25 into scratch, one-time, shared across both).
JDK25_DIR="${OUT_DIR}/jdk25"
if [[ ! -x "$JDK25_DIR/bin/javac" ]]; then
  echo ">>> JDK 25 not found at $JDK25_DIR -- downloading Eclipse Temurin 25 (one-time)..."
  rm -rf "$JDK25_DIR"
  EXTRACT_DIR="${OUT_DIR}/jdk25_extract_tmp"
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$JDK25_DIR" "$EXTRACT_DIR"

  JDK25_TAR="${OUT_DIR}/jdk25.tar.gz"
  curl -fL --retry 3 --retry-delay 5 -o "$JDK25_TAR" \
    "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse"

  tar -xzf "$JDK25_TAR" -C "$EXTRACT_DIR"
  rm -f "$JDK25_TAR"

  JAVAC_PATH="$(find "$EXTRACT_DIR" -type f -name javac -path '*/bin/javac' | head -n1)"
  [[ -n "$JAVAC_PATH" ]] || { echo "ERROR: no bin/javac found under extracted JDK archive"; exit 1; }
  JDK_HOME_FOUND="$(dirname "$(dirname "$JAVAC_PATH")")"
  rm -rf "$JDK25_DIR"
  mv "$JDK_HOME_FOUND" "$JDK25_DIR"
  rm -rf "$EXTRACT_DIR"
  chmod -R u+rX "$JDK25_DIR"
  find "$JDK25_DIR/bin" -type f -exec chmod u+x {} +
fi
[[ -x "$JDK25_DIR/bin/javac" ]] || { echo "ERROR: JDK 25 not available at $JDK25_DIR"; exit 1; }
echo ">>> Using JDK 25 at: $JDK25_DIR"

GRADLE_TOOLCHAIN_ARGS=(
  -Porg.gradle.java.installations.paths="$JDK25_DIR"
  -Porg.gradle.java.installations.auto-detect=false
  -Porg.gradle.java.installations.auto-download=false
)

# Full-power variant of the proven -s5 script: --sample-start=0 instead of
# 5, so Chicory records EVERY call/return forever instead of decaying after
# the first 5 per program point. This may produce a very large trace --
# watch dtrace.gz's growth rate early rather than waiting the full 72h to
# find out.
AGENT_FLAG="-javaagent:${DAIKON_JAR}=--output_dir=${TRACE_OUT_DIR} --ppt-select-pattern=^org\.springframework\.core\.convert\..* --ppt-omit-pattern=com\.google\.protobuf --boot-classes=^(?!org\.springframework\.).* --sample-start=0 --nesting-depth=0"
AGENT_FLAG_GROOVY="${AGENT_FLAG//\\/\\\\}"

INIT_GRADLE="${WORK_DIR}/daikon-agent-init-full.gradle"
cat > "$INIT_GRADLE" <<EOF
gradle.projectsEvaluated {
    def target = rootProject.findProject(':${MODULE}')
    if (target != null) {
        target.tasks.withType(Test).configureEach {
            jvmArgs += ['${AGENT_FLAG_GROOVY}', '-Xmx48g']
            ignoreFailures = true
        }
    }
}
EOF

cd "$WORK_DIR"
echo ">>> Stopping any leaked Gradle daemons from prior runs on this GRADLE_USER_HOME"
./gradlew --stop --gradle-user-home "$GRADLE_HOME_DIR" || true

echo "[TIMING] === gradle compileJava (warm build, no agent) STARTING $(date -Iseconds) ==="
t0=$(_now)

./gradlew --no-daemon --console=plain --gradle-user-home "$GRADLE_HOME_DIR" \
  "${GRADLE_TOOLCHAIN_ARGS[@]}" \
  ":${MODULE}:compileJava"

_timing "gradle compileJava (warm build, no agent)" "$t0"

echo "[TIMING] === gradle test (Chicory instrumented) STARTING $(date -Iseconds) ==="
t0=$(_now)

./gradlew --no-daemon --console=plain --gradle-user-home "$GRADLE_HOME_DIR" \
  --init-script "$INIT_GRADLE" \
  "${GRADLE_TOOLCHAIN_ARGS[@]}" \
  ":${MODULE}:test" || true

_timing "gradle test (Chicory instrumented)" "$t0"

./gradlew --no-daemon --gradle-user-home "$GRADLE_HOME_DIR" --stop || true

echo ">>> Chicory trace output directory:"
ls -la "$TRACE_OUT_DIR"

# NOTE: no combine/decompress step here on purpose. Daikon reads
# gzip-compressed dtrace files natively -- decompressing into a plain-text
# combined file was never necessary, and doing so for a large unlimited
# trace can require many times the original file's size. That exact step
# exhausted /scratch and killed the netty and hudi_full runs. The original
# Chicory-generated dtrace.gz in TRACE_OUT_DIR is the only file needed.

# Update "latest" only after successful completion, so a failed/partial run
# never becomes the pointer to look at.
ln -sfn "$TRACE_OUT_DIR" "${TRACE_BASE_DIR}/latest"

_timing "TOTAL (${PROJECT_NAME})" "$RUN_START"
echo "[TIMING] === ${PROJECT_NAME} chicory trace run finished $(date -Iseconds) ==="

echo
echo ">>> Original Chicory-generated dtrace.gz files preserved in:"
echo ">>> $TRACE_OUT_DIR"
echo ">>> Convenient newest-run path:"
echo ">>> ${TRACE_BASE_DIR}/latest"
