#!/bin/bash -l
#SBATCH --job-name=hudi-test
#SBATCH --output=hudi-test.%j.out
#SBATCH --error=hudi-test.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00
#SBATCH --mem=32G

set -euo pipefail

########################################
# Load Java
########################################
#module purge
#module load Java/17.0.15

########################################
# Setup Maven (from scratch)
########################################
export MAVEN_HOME="/scratch/mjk76/$USER/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"

echo "JAVA: $(which java)"
echo "MVN: $(which mvn)"

########################################
# Go to Hudi repo
########################################
cd "/project/mjk76/ea442/promptstudy/hudi"
########################################
# (Optional but recommended) Maven cache in scratch
########################################
export MAVEN_OPTS="-Dmaven.repo.local=/scratch/mjk76/$USER/.m2"

########################################
# Run your exact command
########################################
echo ">>> Running Maven tests..."

mvn clean install -DskipTests -Dspark3.5 -Dscala-2.12 -Dflink1.20

mvn -q \
  -pl hudi-client/hudi-java-client \
  -DskipITs \
  -Duser.timezone=UTC \
  -Dcheckstyle.skip=true \
  -Dcheckstyle.skipExec=true \
  -Denforcer.skip=true \
  test
echo ">>> Done."
