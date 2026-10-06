#!/bin/bash -l

#SBATCH --job-name=dubbo-daikon
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=192G
#SBATCH --time=48:00:00

set -euo pipefail

########################################
# PATHS
########################################

ROOT="/project/mjk76/ea442/promptstudy"

DAIKON_JAR="$ROOT/daikon.jar"

TRACE="$ROOT/dubbo-chicory-out/dubbo.dtrace.gz"

OUT_DIR="$ROOT/dubbo-daikon-out"

INV_FILE="$OUT_DIR/dubbo.inv.gz"
TEXT_FILE="$OUT_DIR/dubbo-invariants.txt"

########################################
# JAVA
########################################

module load Java/17.0.15

mkdir -p "$OUT_DIR"

########################################
# SANITY CHECKS
########################################

[[ -f "$DAIKON_JAR" ]] || {
    echo "ERROR: Daikon jar not found: $DAIKON_JAR"
    exit 1
}

[[ -f "$TRACE" ]] || {
    echo "ERROR: trace not found: $TRACE"
    exit 1
}

echo "========================================"
echo "Dubbo Daikon invariant detection"
echo "========================================"
echo "JAVA:   $(which java)"
echo "TRACE:  $TRACE"
echo "JAR:    $DAIKON_JAR"
echo "OUTPUT: $OUT_DIR"
echo

echo ">>> Trace size:"
ls -lh "$TRACE"
echo

########################################
# RUN DAIKON
########################################

START=$(date +%s)

echo ">>> Starting Daikon at $(date -Iseconds)"

java \
    -Xmx160g \
    -cp "$DAIKON_JAR" \
    daikon.Daikon \
    -o "$INV_FILE" \
    "$TRACE" \
    > "$TEXT_FILE"

END=$(date +%s)

echo
echo ">>> Daikon finished at $(date -Iseconds)"
echo ">>> Runtime: $((END - START)) seconds"

########################################
# OUTPUT SUMMARY
########################################

echo
echo ">>> Output files:"
ls -lh "$INV_FILE" "$TEXT_FILE"

echo
echo ">>> First 50 lines of inferred invariants:"
head -n 50 "$TEXT_FILE"

echo
echo ">>> Done."
