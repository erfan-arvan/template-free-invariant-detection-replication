#!/bin/bash -l
#SBATCH --job-name=rxjava-recompile21
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:30:00

set -euo pipefail
module load Java/23.0.2
cd /project/mjk76/ea442/promptstudy/rxjava

echo "JAVAC: $(which javac)"
javac -version

OUT_DIR="/project/mjk76/ea442/promptstudy/rxjava-classes21"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Exclude the docs-only package: FlowableDocBasic is a sealed interface that permits
# Flowable (a different package); that only resolves via module-info.java's named-module
# boundary in the real build, which this ad-hoc per-file javac compile doesn't reproduce.
# It's documentation filler, not real API surface, so dropping it doesn't affect callsites.
find src/main/java -name '*.java' -not -path '*/core/docs/*' > /tmp/rxjava-sources-$SLURM_JOB_ID.txt
echo "Source file count: $(wc -l < /tmp/rxjava-sources-$SLURM_JOB_ID.txt)"

# rxjava uses Executors.newVirtualThreadPerTaskExecutor() / Future.resultNow()/exceptionNow(),
# both finalized in JDK 21, so --release 17 failed to compile. --release 21 produces class
# file major version 65 instead of the normal build's 67 (Java 23) -- still need to confirm
# WALA 1.6.3 (Shrike bytecode reader) can actually parse major version 65.
javac --release 21 -d "$OUT_DIR" @/tmp/rxjava-sources-$SLURM_JOB_ID.txt

rm -f /tmp/rxjava-sources-$SLURM_JOB_ID.txt

echo ">>> Done. Recompiled classes at: $OUT_DIR"
find "$OUT_DIR" -name '*.class' | wc -l
