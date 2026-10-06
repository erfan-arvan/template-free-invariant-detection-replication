#!/bin/bash -l
#SBATCH --job-name=test-forward-unresolved
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=02:00:00

set -euo pipefail
module load Java/17.0.15

export MAVEN_HOME="/scratch/mjk76/$USER/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"
export MAVEN_OPTS="-Dmaven.repo.local=/scratch/mjk76/$USER/.m2"

TEST_DIR="/scratch/mjk76/ea442/promptstudy/daikon-trace-tools-forward-test"
rm -rf "$TEST_DIR"
git clone --branch forward-source-index --single-branch \
  https://github.com/erfan-arvan/daikon-trace-tools "$TEST_DIR"

cd "$TEST_DIR/io-examples-tool"
mvn -q package

java -Xmx24g -cp target/io-examples-tool-1.0.0.jar tool.IOExamplesExtractor \
  --dtrace /scratch/mjk76/ea442/promptstudy/apollo-chicory-out/latest/dtrace.gz \
  --src /project/mjk76/ea442/promptstudy/apollo/apollo-biz/src/main/java \
  --out /project/mjk76/ea442/promptstudy/apollo-full_io_examples_FORWARD.json \
  --unresolved-out /project/mjk76/ea442/promptstudy/apollo_unresolved_ppts.txt

echo ">>> Done"
wc -l /project/mjk76/ea442/promptstudy/apollo_unresolved_ppts.txt
