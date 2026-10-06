#!/bin/bash -l
#SBATCH --job-name=netty-classpath
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

export MAVEN_HOME="/scratch/mjk76/$USER/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"
export MAVEN_OPTS="-Dmaven.repo.local=/scratch/mjk76/$USER/.m2"

module load Java/17.0.15

echo "JAVA: $(which java)"
echo "MVN: $(which mvn)"

cd /project/mjk76/ea442/promptstudy/netty

MODULE="${DP_NETTY_MODULE:-common}"

# target/classes doesn't exist yet on this checkout -- compile is bundled
# into the same mvn invocation (Maven runs goals in the order given) so
# this one job produces both the compiled classes callsite-tool.jar needs
# AND the dependency classpath file, instead of needing a separate step.
mvn -pl "$MODULE" -am compile dependency:build-classpath \
  -Dmdep.outputFile=/project/mjk76/ea442/promptstudy/netty-cp.txt

echo ">>> Classpath written to /project/mjk76/ea442/promptstudy/netty-cp.txt"
cat /project/mjk76/ea442/promptstudy/netty-cp.txt
