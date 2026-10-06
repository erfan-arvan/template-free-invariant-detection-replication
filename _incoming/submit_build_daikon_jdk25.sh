#!/bin/bash -l

#SBATCH --job-name=build-daikon-jdk25
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00

set -euo pipefail

BUILD_DIR=/scratch/mjk76/ea442/promptstudy/daikon-src-jdk25

rm -rf "$BUILD_DIR"

git clone https://github.com/codespecs/daikon "$BUILD_DIR"
cd "$BUILD_DIR"

export DAIKONDIR="$BUILD_DIR"
export JAVA_HOME=/scratch/mjk76/ea442/promptstudy/jdk25
export PATH="$JAVA_HOME/bin:$PATH"

# Wulver/GPFS checkout is losing executable bits.
# Restore +x exactly for files Git marks executable.
git ls-files --stage |
awk '$1 == "100755" {print $4}' |
while IFS= read -r f; do
    chmod u+x "$f"
done

# Daikon normally clones this during Makefile parsing.
# Clone it ourselves so we can restore its executable bits first.
mkdir -p "$DAIKONDIR/.utils"

git clone --depth=1 \
    https://github.com/plume-lib/plume-scripts.git \
    "$DAIKONDIR/.utils/plume-scripts"

cd "$DAIKONDIR/.utils/plume-scripts"

git ls-files --stage |
awk '$1 == "100755" {print $4}' |
while IFS= read -r f; do
    chmod u+x "$f"
done

cd "$DAIKONDIR"

echo "=== Important permissions ==="
ls -l scripts/java-cpp
ls -l .utils/plume-scripts/sort-directory-order

python3 /project/mjk76/ea442/promptstudy/patch_chicory_runtime.py
make daikon.jar

cp "$DAIKONDIR/daikon.jar" \
   /project/mjk76/ea442/promptstudy/daikon-spring-jdk25.jar

echo ">>> Built successfully"
ls -lh /project/mjk76/ea442/promptstudy/daikon-spring-jdk25.jar
