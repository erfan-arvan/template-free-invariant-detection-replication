#!/bin/bash -l
#SBATCH --job-name=dubbo-s5-daikon-quickfix
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

TRACE="/scratch/mjk76/ea442/promptstudy/dubbo-s5-chicory-out/latest/dubbo-s5-v2.dtrace.gz"
JAR="/project/mjk76/ea442/promptstudy/daikon.jar"
OUT_DIR="/project/mjk76/ea442/promptstudy/dubbo-s5-daikon-quickfix-out"
mkdir -p "$OUT_DIR"

echo ">>> Trace size:"
ls -lh "$(readlink -f "$TRACE")"

java -Xmx160g -cp "$JAR" daikon.Daikon \
    --config_option daikon.derive.Derivation.disable_derived_variables=true \
    --ppt-omit-pattern='^org\.apache\.dubbo\.common\.compiler\.support\.HelloServiceImpl12\b' \
    -o "$OUT_DIR/dubbo-s5-quickfix.inv.gz" \
    "$TRACE" \
    > "$OUT_DIR/dubbo-s5-quickfix-invariants.txt"

echo ">>> Done."
ls -lh "$OUT_DIR"
