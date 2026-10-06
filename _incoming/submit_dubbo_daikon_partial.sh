#!/bin/bash -l
#SBATCH --job-name=dubbo-daikon-partial
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=192G
#SBATCH --time=72:00:00

set -euo pipefail
module load Java/17.0.15

TRACE="/scratch/mjk76/ea442/promptstudy/dubbo-chicory-out/1280625/dubbo.dtrace.gz"
JAR="/project/mjk76/ea442/promptstudy/daikon.jar"
OUT_DIR="/project/mjk76/ea442/promptstudy/dubbo-daikon-partial-out"
mkdir -p "$OUT_DIR"

echo ">>> Trace size:"
ls -lh "$TRACE"

java -Xmx160g -cp "$JAR" daikon.Daikon \
    --config_option daikon.derive.Derivation.disable_derived_variables=true \
    -o "$OUT_DIR/dubbo.inv.gz" \
    "$TRACE" \
    > "$OUT_DIR/dubbo-invariants.txt"

echo ">>> Done."
ls -lh "$OUT_DIR"
