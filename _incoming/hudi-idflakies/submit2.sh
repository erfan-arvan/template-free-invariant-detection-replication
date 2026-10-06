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
module load Java/17.0.15

########################################
# Setup Maven (from scratch)
########################################
export MAVEN_HOME="/scratch/mjk76/$USER/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"
export MAVEN_OPTS="-Dmaven.repo.local=/scratch/mjk76/$USER/.m2"

echo "JAVA: $(which java)"
echo "MVN: $(which mvn)"

cd "/project/mjk76/ea442/promptstudy/hudi"

########################################
# Pre-build dependencies into .m2
########################################
echo ">>> Pre-building dependencies..."
mvn clean install -DskipTests -Dspark3.5 -Dscala-2.12 -Dflink1.20

########################################
# Test the compile script (what daikonplusplus runs)
########################################
echo ">>> Testing compile script..."
mvn \
  -pl hudi-client/hudi-java-client \
  -am \
  -DskipTests \
  -Dmaven.test.skip=true \
  -Dcheckstyle.skip=true \
  -Dcheckstyle.skipExec=true \
  -Denforcer.skip=true \
  -Drat.skip=true \
  compile

########################################
# Test the runner script (what daikonplusplus runs)
########################################
echo ">>> Testing runner script..."
mvn -q \
  -pl hudi-client/hudi-java-client \
  -DskipITs \
  -Duser.timezone=UTC \
  -Dcheckstyle.skip=true \
  -Dcheckstyle.skipExec=true \
  -Denforcer.skip=true \
  -Drat.skip=true \
  test

echo ">>> Done."
