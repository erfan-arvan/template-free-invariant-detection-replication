#!/bin/bash -l

#SBATCH --job-name=netty-daikon
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

ROOT="/project/mjk76/ea442/promptstudy"
SCRATCH="/scratch/mjk76/ea442/promptstudy"
PROJECT_NAME="netty"

DAIKON_JAR="$ROOT/daikon.jar"
TRACE="$SCRATCH/netty-chicory-out/1260712/dtrace.gz"

OUT_DIR="$ROOT/netty-daikon-out"
INV_FILE="$OUT_DIR/netty.inv.gz"
TEXT_FILE="$OUT_DIR/netty-invariants.txt"

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
        >> "${SCRATCH}/daikon_timing.log"
}
RUN_START=$(_now)
echo "[TIMING] === ${PROJECT_NAME} daikon run started $(date -Iseconds) ==="

module load Java/17.0.15
mkdir -p "$OUT_DIR"

[[ -f "$DAIKON_JAR" ]] || { echo "ERROR: Daikon jar not found: $DAIKON_JAR"; exit 1; }
[[ -f "$TRACE" ]] || { echo "ERROR: trace not found: $TRACE"; exit 1; }

echo "========================================"
echo "Netty Daikon invariant detection"
echo "========================================"
echo "JAVA:   $(which java)"
echo "TRACE:  $TRACE (original Chicory dtrace.gz, read directly)"
echo "JAR:    $DAIKON_JAR"
echo "OUTPUT: $OUT_DIR"
echo

echo ">>> Trace size:"
ls -lh "$TRACE"
echo

t0=$(_now)
echo ">>> Starting Daikon at $(date -Iseconds)"

java \
    -Xmx160g \
    -cp "$DAIKON_JAR" \
    daikon.Daikon \
    -o "$INV_FILE" \
    "$TRACE" \
    > "$TEXT_FILE"

_timing "daikon.Daikon invariant detection" "$t0"

echo
echo ">>> Daikon finished at $(date -Iseconds)"

echo
echo ">>> Output files:"
ls -lh "$INV_FILE" "$TEXT_FILE"
echo
echo ">>> First 50 lines of inferred invariants:"
head -n 50 "$TEXT_FILE"

_timing "TOTAL (${PROJECT_NAME})" "$RUN_START"
echo "[TIMING] === ${PROJECT_NAME} daikon run finished $(date -Iseconds) ==="

echo
echo ">>> Done."
