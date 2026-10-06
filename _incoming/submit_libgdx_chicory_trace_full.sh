#!/bin/bash -l
#SBATCH --job-name=libgdx-chicory-trace-full
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
module load Java/17.0.15
cd /project/mjk76/ea442/promptstudy

DAIKON_JAR="/project/mjk76/ea442/promptstudy/daikon.jar"
LIBGDX_DIR="/project/mjk76/ea442/promptstudy/libgdx"
OUT_DIR="/scratch/mjk76/ea442/promptstudy"
PROJECT_NAME="libgdx-full"

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

TRACE_BASE_DIR="${OUT_DIR}/libgdx-full-chicory-out"
RUN_ID="${SLURM_JOB_ID:-$(date +%Y%m%d-%H%M%S)}"
TRACE_OUT_DIR="${TRACE_BASE_DIR}/${RUN_ID}"
mkdir -p "$TRACE_OUT_DIR"

WORK_DIR="${OUT_DIR}/libgdx-full-chicory"
GRADLE_HOME_DIR="${OUT_DIR}/libgdx-full-gradle-home"

mkdir -p "$GRADLE_HOME_DIR"

echo "JAVA: $(which java)"

mkdir -p "$WORK_DIR"

t0=$(_now)
rsync -a --delete --exclude='.git' --exclude='build' --exclude='.gradle' "${LIBGDX_DIR}/" "${WORK_DIR}/"
_timing "rsync copy" "$t0"

AGENT_FLAG="-javaagent:${DAIKON_JAR}=--output_dir=${TRACE_OUT_DIR} --ppt-select-pattern=^com\.badlogic\.gdx\.(utils|math)\..* --ppt-omit-pattern=com\.google\.protobuf --boot-classes=^(?!com\.badlogic\.gdx\.).* --sample-start=0 --nesting-depth=0"
AGENT_FLAG_GROOVY="${AGENT_FLAG//\\/\\\\}"

INIT_GRADLE="${WORK_DIR}/daikon-agent-init-full.gradle"
cat > "$INIT_GRADLE" <<EOF
allprojects {
    tasks.withType(Test).configureEach {
        jvmArgs += ['${AGENT_FLAG_GROOVY}', '-Xmx48g']
        ignoreFailures = true
    }
}
EOF

cd "$WORK_DIR"

echo "[TIMING] === gradle compileJava (warm build, no agent) STARTING $(date -Iseconds) ==="
t0=$(_now)

./gradlew --no-daemon --console=plain --gradle-user-home "$GRADLE_HOME_DIR" \
  clean :gdx:compileJava

_timing "gradle compileJava (warm build, no agent)" "$t0"

echo "[TIMING] === gradle test (Chicory instrumented) STARTING $(date -Iseconds) ==="
t0=$(_now)

echo ">>> gradle test (javaagent attached via init script) -- this is the actual Chicory-instrumented run"
./gradlew --no-daemon --console=plain --gradle-user-home "$GRADLE_HOME_DIR" \
  --init-script "$INIT_GRADLE" \
  :gdx:test --info || true

_timing "gradle test (Chicory instrumented)" "$t0"

./gradlew --no-daemon --gradle-user-home "$GRADLE_HOME_DIR" --stop || true

echo ">>> Chicory trace output directory:"
ls -la "$TRACE_OUT_DIR"

# NOTE: no combine/decompress step here on purpose. Daikon reads
# gzip-compressed dtrace files natively -- decompressing into a plain-text
# combined file was never necessary, and doing so for a large unlimited
# trace can require many times the original file's size. That exact step
# exhausted /scratch and killed the netty and hudi_full runs earlier this
# session. The original Chicory-generated dtrace.gz in TRACE_OUT_DIR is
# the only file needed.

ln -sfn "$TRACE_OUT_DIR" "${TRACE_BASE_DIR}/latest"

_timing "TOTAL (${PROJECT_NAME})" "$RUN_START"
echo "[TIMING] === ${PROJECT_NAME} chicory trace run finished $(date -Iseconds) ==="

echo
echo ">>> Original Chicory-generated dtrace.gz files preserved in:"
echo ">>> $TRACE_OUT_DIR"
echo ">>> Convenient newest-run path:"
echo ">>> ${TRACE_BASE_DIR}/latest"
