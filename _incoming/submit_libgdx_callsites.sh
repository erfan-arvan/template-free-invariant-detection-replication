#!/bin/bash -l
#SBATCH --job-name=libgdx-callsites
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=03:00:00

set -euo pipefail
module load Java/17.0.15
cd /project/mjk76/ea442/promptstudy

CLASSES="libgdx/gdx/build/classes/java/main"
SRC="libgdx/gdx/src"
CP="$(cat libgdx-cp.txt)"

echo "JAVA: $(which java)"
echo "CLASSES: $CLASSES"
echo "SRC: $SRC"

java -Xmx24g -jar callsite-tool.jar \
  --classes "$CLASSES" \
  --classpath "$CP" \
  --src "$SRC" \
  --out libgdx_callsites.json

echo ">>> Wrote libgdx_callsites.json"
wc -l libgdx_callsites.json
