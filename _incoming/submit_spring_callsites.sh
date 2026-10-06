#!/bin/bash -l
#SBATCH --job-name=spring-callsites
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

MODULE="${DP_SPRING_MODULE:-spring-core}"
CLASSES="spring-framework/$MODULE/build/classes/java/main"
SRC="spring-framework/$MODULE/src/main/java"
CP="$(cat spring-cp.txt)"

echo "JAVA: $(which java)"
echo "CLASSES: $CLASSES"
echo "SRC: $SRC"

java -Xmx24g -jar callsite-tool.jar \
  --classes "$CLASSES" \
  --classpath "$CP" \
  --src "$SRC" \
  --out spring_callsites.json

echo ">>> Wrote spring_callsites.json"
wc -l spring_callsites.json
