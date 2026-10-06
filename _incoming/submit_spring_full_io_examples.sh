#!/bin/bash -l
#SBATCH --job-name=spring-full-io-examples
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=01:00:00

set -euo pipefail
module load Java/17.0.15
cd /project/mjk76/ea442/promptstudy

TOOL_JAR="/project/mjk76/ea442/promptstudy/daikon-trace-tools/io-examples-tool/target/io-examples-tool-1.0.0.jar"
DTRACE="/scratch/mjk76/ea442/promptstudy/spring-full-chicory-out/1280660/dtrace.gz"
SRC_ROOT="/project/mjk76/ea442/promptstudy/spring-framework/spring-core/src/main/java"
OUT="/project/mjk76/ea442/promptstudy/spring-full-1280660_io_examples_FIXED.json"

echo "JAVA: $(which java)"
echo "TOOL_JAR: $TOOL_JAR"
echo "DTRACE:   $DTRACE"
echo "SRC_ROOT: $SRC_ROOT"
echo "OUT:      $OUT"

[[ -f "$TOOL_JAR" ]] || { echo "ERROR: tool jar not found: $TOOL_JAR"; exit 1; }
[[ -f "$DTRACE" ]] || { echo "ERROR: dtrace not found: $DTRACE"; exit 1; }

java -Xmx24g -cp "$TOOL_JAR" tool.IOExamplesExtractor \
  --dtrace "$DTRACE" \
  --src "$SRC_ROOT" \
  --out "$OUT"

echo ">>> Wrote $OUT"
ls -lh "$OUT"
