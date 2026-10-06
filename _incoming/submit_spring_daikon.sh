#!/bin/bash -l

#SBATCH --job-name=spring-daikon
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
PROJECT_NAME="spring-full"

DAIKON_JAR="$ROOT/daikon.jar"
TRACE="$SCRATCH/spring-full-chicory-out/latest/spring-full.dtrace.gz"

OUT_DIR="$ROOT/spring-daikon-out"
INV_FILE="$OUT_DIR/spring.inv.gz"
TEXT_FILE="$OUT_DIR/spring-invariants.txt"

# job 1266081 crashed with a NullPointerException inside Daikon's own
# derived-variable logic (SequenceScalarSubscript.makeVarInfo / this.sequence
# is null) while deriving a subscript variable for one specific constructor.
# job 1266274 (after omitting that one ppt) crashed with the SAME error at a
# DIFFERENT program point -- confirming this isn't one bad method, it's a
# systemic issue across many program points with a certain sequence-typed
# variable shape. Chasing individual ppts is not practical; instead disable
# derived-variable creation globally (confirmed real, documented Daikon
# option -- daikon/derive/Derivation.java's dkconfig_disable_derived_variables,
# set via --config_option daikon.derive.Derivation.disable_derived_variables=true).
# This sidesteps the whole crash class. Tradeoff: no derived-variable
# invariants (e.g. array[i] subscripts) -- only invariants over the directly
# traced variables -- but the run actually completes.
CONFIG_OPTION='daikon.derive.Derivation.disable_derived_variables=true'

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
echo "Spring (full) Daikon invariant detection"
echo "========================================"
echo "JAVA:        $(which java)"
echo "TRACE:       $TRACE"
echo "JAR:         $DAIKON_JAR"
echo "CONFIG:      $CONFIG_OPTION"
echo "OUTPUT:      $OUT_DIR"
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
    --config_option "$CONFIG_OPTION" \
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
