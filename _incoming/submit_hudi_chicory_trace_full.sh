#!/bin/bash -l
#SBATCH --job-name=hudi-chicory-trace-full
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
OUT_DIR="/scratch/mjk76/ea442/promptstudy"
PROJECT_NAME="hudi-full"

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

TRACE_BASE_DIR="${OUT_DIR}/hudi-chicory-out"
RUN_ID="${SLURM_JOB_ID:-$(date +%Y%m%d-%H%M%S)}"
TRACE_OUT_DIR="${TRACE_BASE_DIR}/${RUN_ID}"
mkdir -p "$TRACE_OUT_DIR"

export MAVEN_HOME="/scratch/mjk76/${USER}/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"
export MAVEN_OPTS="-Xmx16g -Dmaven.repo.local=/scratch/mjk76/${USER}/.m2-hudi-full"

echo "JAVA: $(which java)"
echo "MVN: $(which mvn)"

unset JDK_JAVA_OPTIONS

# Full-power variant of the proven hudi script: --sample-start=0 instead of
# 5, so Chicory records EVERY call/return forever instead of decaying after
# the first 5 per program point. This is what produced a 93GB trace that
# still hadn't finished after 24h the first time it was tried (before
# sampling was added) -- --mem/--time/heap below are bumped well past that
# as a starting budget.
AGENT_FLAG="-javaagent:${DAIKON_JAR}=--output_dir=${TRACE_OUT_DIR} --ppt-select-pattern=^org\.apache\.hudi\..* --ppt-omit-pattern=HoodieFieldOrder|HoodieTableType|com\.google\.protobuf --boot-classes=^(?!org\.apache\.hudi\.).* --sample-start=0"
HUDI_CHICORY_DIR="${OUT_DIR}/hudi-full-chicory"

mkdir -p "$HUDI_CHICORY_DIR"
rsync -a --delete --exclude='.git' --exclude='target' hudi/ "$HUDI_CHICORY_DIR/"

python3 - "$AGENT_FLAG" "$HUDI_CHICORY_DIR/pom.xml" <<'EOF'
import sys

agent_flag = sys.argv[1]
path = sys.argv[2]

with open(path) as f:
    content = f.read()

old = "-XX:-OmitStackTraceInFastThrow</argLine>"
new = f'-XX:-OmitStackTraceInFastThrow "{agent_flag}" -Xmx48g</argLine>'

count = content.count(old)
if count == 0:
    raise SystemExit("ERROR: no occurrences of the expected argLine tail found -- pom.xml format may have changed")

content = content.replace(old, new)
with open(path, "w") as f:
    f.write(content)
print(f"Patched {count} occurrence(s) of argLine in {path} (hudi/pom.xml itself untouched)")
EOF

cd "$HUDI_CHICORY_DIR"

COMPILER_FLAG="-Dmaven.compiler.compilerArgument=-XDstringConcat=inline"

echo "[TIMING] === mvn install (compile, no chicory agent) STARTING $(date -Iseconds) ==="
t0=$(_now)

mvn -q \
  -pl hudi-client/hudi-java-client -am \
  install \
  -DskipTests \
  -Dcheckstyle.skip=true \
  -Dcheckstyle.skipExec=true \
  -Denforcer.skip=true \
  -Drat.skip=true \
  "${COMPILER_FLAG}"

_timing "mvn install (compile, no chicory agent)" "$t0"

echo "[TIMING] === mvn test (Chicory instrumented) STARTING $(date -Iseconds) ==="
t0=$(_now)

mvn -q \
  -pl hudi-client/hudi-java-client \
  -DskipITs \
  -Duser.timezone=UTC \
  -Dcheckstyle.skip=true \
  -Dcheckstyle.skipExec=true \
  -Denforcer.skip=true \
  -Drat.skip=true \
  -Dmaven.test.failure.ignore=true \
  -DforkCount="${SLURM_CPUS_PER_TASK:-8}" \
  -DreuseForks=false \
  "${COMPILER_FLAG}" \
  test

_timing "mvn test (Chicory instrumented)" "$t0"

echo ">>> Chicory trace output directory:"
ls -la "$TRACE_OUT_DIR"

# NOTE: no combine/decompress step here on purpose. Daikon reads
# gzip-compressed dtrace files natively -- decompressing into a plain-text
# combined file was never necessary, and doing so for a large unlimited
# trace can require many times the original file's size. That exact step
# exhausted /scratch and killed this run (job 1260714): its combine step
# tried to decompress a 335GB dtrace.gz and hit "disk quota exceeded"
# mid-write. The original Chicory-generated dtrace.gz in TRACE_OUT_DIR is
# the only file needed.

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
