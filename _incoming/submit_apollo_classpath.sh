#!/bin/bash -l
#SBATCH --job-name=apollo-classpath
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=00:30:00

set -euo pipefail

export MAVEN_HOME="/scratch/mjk76/$USER/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"
export MAVEN_OPTS="-Dmaven.repo.local=/scratch/mjk76/$USER/.m2"

module load Java/17.0.15

echo "JAVA: $(which java)"
echo "MVN: $(which mvn)"

cd /project/mjk76/ea442/promptstudy/apollo

mvn -pl apollo-biz -am dependency:build-classpath \
  -Dmdep.outputFile=/project/mjk76/ea442/promptstudy/apollo-cp.txt

echo ">>> Classpath written to /project/mjk76/ea442/promptstudy/apollo-cp.txt"
cat /project/mjk76/ea442/promptstudy/apollo-cp.txt
