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

# module-info.java lives in a separate Gradle source set (src/main/module/), not
# src/main/java, so it must be included explicitly. Without it, javac treats this as an
# unnamed-module compile and rejects FlowableDocBasic's sealed-interface permits clause,
# which spans packages (io.reactivex.rxjava4.core.docs -> io.reactivex.rxjava4.core) --
# that's only legal within a single named module.
{ find src/main/java -name '*.java'; find src/main/module -name '*.java'; } > /tmp/rxjava-sources-$SLURM_JOB_ID.txt
echo "Source file count: $(wc -l < /tmp/rxjava-sources-$SLURM_JOB_ID.txt)"

# rxjava uses Executors.newVirtualThreadPerTaskExecutor() / Future.resultNow()/exceptionNow(),
# both finalized in JDK 21, so --release 17 failed to compile. --release 21 produces class
# file major version 65 instead of the normal build's 67 (Java 23) -- still need to confirm
# WALA 1.6.3 (Shrike bytecode reader) can actually parse major version 65.
javac --release 21 -d "$OUT_DIR" @/tmp/rxjava-sources-$SLURM_JOB_ID.txt

rm -f /tmp/rxjava-sources-$SLURM_JOB_ID.txt

echo ">>> Done. Recompiled classes at: $OUT_DIR"
find "$OUT_DIR" -name '*.class' | wc -l
