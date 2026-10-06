#!/bin/bash -l
#SBATCH --job-name=idflakies-rxjava
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=0-2:00:00
#SBATCH --mem=32G

set -euo pipefail

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

module load Java/23.0.2

# Required by this RxJava checkout; otherwise it requests Java 26.
export JDK_EXPERIMENTAL=23

ORIGINAL_RXJAVA="/project/mjk76/ea442/promptstudy/rxjava"
EXPERIMENT="/project/mjk76/ea442/promptstudy/flakyTestDetection"
IDFLAKIES="$EXPERIMENT/iDFlakies"

WORK_ROOT="/scratch/mjk76/$USER/flakyTestDetection/$SLURM_JOB_ID"
RXJAVA_COPY="$WORK_ROOT/rxjava"
RESULT_DIR="$EXPERIMENT/results/$SLURM_JOB_ID"

# Keep Gradle caches/temp data on scratch.
export TMPDIR="$WORK_ROOT/tmp"
export GRADLE_USER_HOME="$WORK_ROOT/.gradle"

mkdir -p "$WORK_ROOT"
mkdir -p "$RESULT_DIR"
mkdir -p "$TMPDIR"
mkdir -p "$GRADLE_USER_HOME"

export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.io.tmpdir=${TMPDIR}"

echo "Node: $(hostname)"
echo "Java:"
java -version
echo "JDK_EXPERIMENTAL=$JDK_EXPERIMENTAL"
echo "Original RxJava: $ORIGINAL_RXJAVA"
echo "Working copy:    $RXJAVA_COPY"
echo "Results:         $RESULT_DIR"
echo "GRADLE_USER_HOME=$GRADLE_USER_HOME"
echo "TMPDIR=$TMPDIR"

# ------------------------------------------------------------
# 1. Make disposable RxJava copy
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

# ------------------------------------------------------------
# 2. Modify ONLY disposable copy for iDFlakies
# ------------------------------------------------------------

echo
echo "=== Configuring disposable copy for iDFlakies ==="

cd "$IDFLAKIES"

bash gradle-modify/modify_gradle.sh "$RXJAVA_COPY"

# ------------------------------------------------------------
# 2a. Gradle 9 compatibility
# iDFlakies injects jcenter(), removed in Gradle 9.
# ------------------------------------------------------------

echo
echo "=== Removing obsolete jcenter() ==="

sed -i \
    '/^[[:space:]]*jcenter()[[:space:]]*$/d' \
    "$RXJAVA_COPY/build.gradle"

if grep -n 'jcenter()' "$RXJAVA_COPY/build.gradle"; then
    echo "ERROR: jcenter() still exists."
    exit 1
else
    echo "jcenter() successfully removed."
fi

# ------------------------------------------------------------
# 3. Show modifications
# ------------------------------------------------------------

echo
echo "=== iDFlakies modifications ==="

cd "$RXJAVA_COPY"

git diff -- build.gradle || true

# ------------------------------------------------------------
# 4. Verify Gradle / Java toolchain
# ------------------------------------------------------------

echo
echo "=== Gradle version ==="

./gradlew --version

echo
echo "=== Checking Gradle configuration and testplugin ==="

TASKS_FILE="$WORK_ROOT/gradle-tasks.txt"

if ! ./gradlew tasks --all \
    --no-daemon \
    --console=plain \
    > "$TASKS_FILE"; then

    echo "ERROR: Gradle failed while configuring/listing tasks."
    exit 1
fi

if grep -i testplugin "$TASKS_FILE"; then
    echo "testplugin successfully registered."
else
    echo "ERROR: Gradle configured successfully, but testplugin was not registered."
    exit 1
fi

# ------------------------------------------------------------
# 5. Run iDFlakies
# ------------------------------------------------------------

echo
echo "=== Running iDFlakies ==="

./gradlew testplugin \
    --no-daemon \
    --max-workers=1 \
    --console=plain \
    -Dorg.gradle.jvmargs="-Xmx1g" \
    -PmaxParallelForks=1 \
    -Dtestplugin.className=edu.illinois.cs.dt.tools.detection.DetectorPlugin \
    -Ddetector.detector_type=random-class-method \
    -Ddt.randomize.rounds=1 \
    -Ddt.detector.original_order.all_must_pass=false

# ------------------------------------------------------------
# 6. Save results
# ------------------------------------------------------------

echo
echo "=== Copying detection results ==="

if [ -d ".dtfixingtools" ]; then
    cp -a .dtfixingtools "$RESULT_DIR/"
fi

if [ -d "detection-results" ]; then
    cp -a detection-results "$RESULT_DIR/"
fi

find "$RXJAVA_COPY" \
    \( -name "detection-results" -o -name ".dtfixingtools" \) \
    -print \
    > "$RESULT_DIR/result-directories.txt"

echo
echo "=== Result directories ==="
cat "$RESULT_DIR/result-directories.txt"

echo
echo "=== Completed ==="
echo "Persistent results: $RESULT_DIR"
echo "Disposable working copy: $RXJAVA_COPY"
echo "Original RxJava untouched: $ORIGINAL_RXJAVA"
