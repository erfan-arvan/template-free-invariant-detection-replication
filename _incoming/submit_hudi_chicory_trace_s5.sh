#!/bin/bash -l
#SBATCH --job-name=hudi-chicory-trace-s5
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=192G
#SBATCH --time=14:00:00

set -euo pipefail
module load Java/17.0.15
cd /project/mjk76/ea442/promptstudy

DAIKON_JAR="/project/mjk76/ea442/promptstudy/daikon.jar"
TRACE_OUT_DIR="/scratch/mjk76/ea442/promptstudy/hudi-s5-chicory-out"
rm -rf "$TRACE_OUT_DIR"
mkdir -p "$TRACE_OUT_DIR"

export MAVEN_HOME="/scratch/mjk76/${USER}/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"
export MAVEN_OPTS="-Xmx16g -Dmaven.repo.local=/scratch/mjk76/${USER}/.m2"

echo "JAVA: $(which java)"
echo "MVN: $(which mvn)"

unset JDK_JAVA_OPTIONS

AGENT_FLAG="-javaagent:${DAIKON_JAR}=--output_dir=${TRACE_OUT_DIR} --ppt-select-pattern=^org\.apache\.hudi\..* --ppt-omit-pattern=HoodieFieldOrder|HoodieTableType|com\.google\.protobuf --boot-classes=^(?!org\.apache\.hudi\.).* --sample-start=5 --nesting-depth=0"
HUDI_CHICORY_DIR="/scratch/mjk76/ea442/promptstudy/hudi-s5-chicory"

mkdir -p "$HUDI_CHICORY_DIR"
rsync -a --delete --exclude='.git' --exclude='target' hudi/ "$HUDI_CHICORY_DIR/"

python3 - "$AGENT_FLAG" "$HUDI_CHICORY_DIR/pom.xml" <<'PYEOF'
import sys

agent_flag = sys.argv[1]
path = sys.argv[2]

with open(path) as f:
    content = f.read()

old = "-XX:-OmitStackTraceInFastThrow</argLine>"
new = f'-XX:-OmitStackTraceInFastThrow "{agent_flag}" -Xmx48g</argLine>'

count = content.count(old)
if count == 0:
    raise SystemExit("ERROR: no occurrences of the expected argLine tail found -- pom.xml format may have changed")

content = content.replace(old, new)
with open(path, "w") as f:
    f.write(content)
print(f"Patched {count} occurrence(s) of argLine in {path} (hudi/pom.xml itself untouched)")
PYEOF

cd "$HUDI_CHICORY_DIR"

COMPILER_FLAG="-Dmaven.compiler.compilerArgument=-XDstringConcat=inline"

mvn -q \
  -pl hudi-client/hudi-java-client -am \
  install \
  -DskipTests \
  -Dcheckstyle.skip=true \
  -Dcheckstyle.skipExec=true \
  -Denforcer.skip=true \
  -Drat.skip=true \
  "${COMPILER_FLAG}"

mvn -q \
  -pl hudi-client/hudi-java-client \
  -DskipITs \
  -Duser.timezone=UTC \
  -Dcheckstyle.skip=true \
  -Dcheckstyle.skipExec=true \
  -Denforcer.skip=true \
  -Drat.skip=true \
  -Dmaven.test.failure.ignore=true \
  "${COMPILER_FLAG}" \
  test

echo ">>> Chicory trace output directory:"
ls -la "$TRACE_OUT_DIR"

# NOTE: no combine/decompress step here on purpose (removed -- the old
# version of this script decompressed into a combined plain-text file via
# zcat, unnecessary since Daikon reads gzip-compressed dtrace natively, and
# the exact pattern that exhausted /scratch and killed netty/hudi_full's
# runs earlier this session). The original Chicory-generated dtrace.gz in
# TRACE_OUT_DIR is the only file needed.

echo
echo ">>> Original Chicory-generated dtrace.gz files preserved in:"
echo ">>> $TRACE_OUT_DIR"
