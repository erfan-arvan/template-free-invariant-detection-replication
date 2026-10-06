#!/bin/bash -l
#SBATCH --job-name=nondex-rxjava
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=0-4:00:00
#SBATCH --mem=32G

set -euo pipefail

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

module load Java/17.0.15

export JDK_EXPERIMENTAL=17

ORIGINAL_RXJAVA="/project/mjk76/ea442/promptstudy/rxjava"
EXPERIMENT="/project/mjk76/ea442/promptstudy/flakyTestDetection"

WORK_ROOT="/scratch/mjk76/$USER/flakyTestDetection/nondex/$SLURM_JOB_ID"
RXJAVA_COPY="$WORK_ROOT/rxjava"

RESULT_DIR="$EXPERIMENT/results/nondex-$SLURM_JOB_ID"

export TMPDIR="$WORK_ROOT/tmp"
export GRADLE_USER_HOME="$WORK_ROOT/.gradle"

mkdir -p "$WORK_ROOT"
mkdir -p "$RESULT_DIR"
mkdir -p "$TMPDIR"
mkdir -p "$GRADLE_USER_HOME"

export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.io.tmpdir=${TMPDIR}"

echo "Node:             $(hostname)"
echo "Original RxJava:  $ORIGINAL_RXJAVA"
echo "Working copy:     $RXJAVA_COPY"
echo "Results:          $RESULT_DIR"
echo "JDK_EXPERIMENTAL: $JDK_EXPERIMENTAL"

java -version

# ------------------------------------------------------------
# 1. Copy RxJava
# ------------------------------------------------------------

echo
echo "=== Copying RxJava ==="

mkdir -p "$RXJAVA_COPY"

rsync -a \
    --exclude='.gradle/' \
    --exclude='build/' \
    --exclude='*.out' \
    --exclude='*.err' \
    "$ORIGINAL_RXJAVA/" \
    "$RXJAVA_COPY/"

cd "$RXJAVA_COPY"

# ------------------------------------------------------------
# 2. Inject NonDex into ONLY the scratch copy
# ------------------------------------------------------------

echo
echo "=== Adding NonDex plugin to disposable copy ==="

python3 - <<'PY'
from pathlib import Path

p = Path("build.gradle")
text = p.read_text()

plugin_line = '    id("edu.illinois.nondex") version "2.2.5"\n'

marker = "plugins {\n"

if plugin_line.strip() in text:
    print("NonDex plugin already present.")
elif marker in text:
    text = text.replace(marker, marker + plugin_line, 1)
    p.write_text(text)
    print("Injected NonDex plugin.")
else:
    raise SystemExit("ERROR: Could not find plugins { block in build.gradle")
PY

echo
echo "=== build.gradle diff ==="

git diff -- build.gradle || true

# ------------------------------------------------------------
# 3. Verify Gradle sees NonDex
# ------------------------------------------------------------

echo
echo "=== Gradle version ==="

./gradlew --version

echo
echo "=== Checking NonDex tasks ==="

TASKS_FILE="$WORK_ROOT/gradle-tasks.txt"

if ! ./gradlew tasks --all \
    --no-daemon \
    --console=plain \
    > "$TASKS_FILE"; then

    echo "ERROR: Gradle failed while configuring the NonDex-enabled copy."
    exit 1
fi

grep -i nondex "$TASKS_FILE" || {
    echo "ERROR: No NonDex Gradle task was registered."
    exit 1
}

# ------------------------------------------------------------
# 4. First ensure ordinary tests work
# ------------------------------------------------------------

echo
echo "=== Running ordinary RxJava tests first ==="

./gradlew test \
    --no-daemon \
    --max-workers=1 \
    -Dorg.gradle.jvmargs="-Xmx1g" \
    -PmaxParallelForks=1 \
    --console=plain

# ------------------------------------------------------------
# 5. Run NonDex
# ------------------------------------------------------------

echo
echo "=== Running NonDex ==="

set +e

./gradlew nondexTest \
    --no-daemon \
    --max-workers=1 \
    -Dorg.gradle.jvmargs="-Xmx1g" \
    -PmaxParallelForks=1 \
    --console=plain

NONDEX_EXIT=$?

set -e

echo
echo "NonDex exit code: $NONDEX_EXIT"

# ------------------------------------------------------------
# 6. Save NonDex output/results
# ------------------------------------------------------------

echo
echo "=== Locating NonDex results ==="

find "$RXJAVA_COPY" \
    \( -iname '*nondex*' -o -path '*/test-results/*' \) \
    -print \
    > "$RESULT_DIR/result-paths.txt" || true

cat "$RESULT_DIR/result-paths.txt"

# Save NonDex's own hidden result/config directory if present.
if [ -d ".nondex" ]; then
    cp -a ".nondex" "$RESULT_DIR/"
fi

# Save Gradle XML results as well.
if [ -d "build/test-results" ]; then
    cp -a "build/test-results" "$RESULT_DIR/"
fi

# Save reports if generated.
if [ -d "build/reports/tests" ]; then
    cp -a "build/reports/tests" "$RESULT_DIR/"
fi

echo
echo "=== Completed ==="
echo "NonDex exit code: $NONDEX_EXIT"
echo "Persistent results: $RESULT_DIR"
echo "Scratch copy:       $RXJAVA_COPY"
echo "Original untouched: $ORIGINAL_RXJAVA"

exit 0
