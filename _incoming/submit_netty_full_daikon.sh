#!/bin/bash -l
#SBATCH --job-name=netty-full-daikon
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=380G
#SBATCH --time=72:00:00

set -euo pipefail
module load Java/17.0.15

TRACE="/scratch/mjk76/ea442/promptstudy/netty-chicory-out/latest/netty-full.dtrace.gz"
JAR="/project/mjk76/ea442/promptstudy/daikon.jar"
OUT_DIR="/project/mjk76/ea442/promptstudy/netty-full-daikon-out"
mkdir -p "$OUT_DIR"

echo ">>> Trace size:"
ls -lh "$(readlink -f "$TRACE")"

java -Xmx350g -cp "$JAR" daikon.Daikon \
    --config_option daikon.derive.Derivation.disable_derived_variables=true \
    -o "$OUT_DIR/netty-full.inv.gz" \
    "$TRACE" \
    > "$OUT_DIR/netty-full-invariants.txt"

echo ">>> Done."
ls -lh "$OUT_DIR"
