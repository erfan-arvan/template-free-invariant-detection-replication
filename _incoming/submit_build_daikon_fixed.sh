#!/bin/bash -l
#SBATCH --job-name=build-daikon-fixed
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

BUILD_DIR=/scratch/mjk76/ea442/promptstudy/daikon-src-fixed

rm -rf "$BUILD_DIR"

git clone https://github.com/codespecs/daikon "$BUILD_DIR"
cd "$BUILD_DIR"

export DAIKONDIR="$BUILD_DIR"
module load Java/17.0.15

git ls-files --stage |
awk '$1 == "100755" {print $4}' |
while IFS= read -r f; do
    chmod u+x "$f"
done

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

python3 /project/mjk76/ea442/promptstudy/patch_chicory_runtime.py
python3 /project/mjk76/ea442/promptstudy/patch_dtracewriter.py
python3 /project/mjk76/ea442/promptstudy/patch_dtracewriter_bug5.py
python3 /project/mjk76/ea442/promptstudy/patch_classinfo_declfailed.py
python3 /project/mjk76/ea442/promptstudy/patch_runtime_declfailed.py

make daikon.jar

cp "$DAIKONDIR/daikon.jar" \
   /project/mjk76/ea442/promptstudy/daikon-fixed.jar

echo ">>> Built successfully"
ls -lh /project/mjk76/ea442/promptstudy/daikon-fixed.jar
