#!/bin/bash -l
#SBATCH --job-name=hudi-io-examples
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=160G
#SBATCH --time=04:00:00

set -euo pipefail
module load Java/17.0.15
cd /project/mjk76/ea442/promptstudy

echo "JAVA: $(which java)"

# job 1178422: OOM'd inside IOExamplesExtractor.readBlocks() -- it
# materializes the whole dtrace as an in-memory List<String>. hudi.dtrace is
# 23.27GB raw / 557.5M lines; per-line Java object overhead (String header +
# backing array) roughly doubles-to-triples that footprint once loaded, plus
# ArrayList grow() transient overhead during resizing, plus whatever
# additional per-line/per-block structures the tool builds on top. -Xmx8g
# was never going to be enough. Bumped heap and SBATCH --mem substantially;
# if this still OOMs, the real fix is making the tool stream the file
# instead of loading it whole, not a bigger heap.
java -Xmx140g -jar io-examples-tool.jar \
  --dtrace hudi.dtrace \
  --src hudi/hudi-client/hudi-java-client/src/main/java \
  --out hudi_io_examples.json

echo ">>> Wrote hudi_io_examples.json"
wc -l hudi_io_examples.json
