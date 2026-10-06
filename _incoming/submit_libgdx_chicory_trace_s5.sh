#!/bin/bash -l
#SBATCH --job-name=libgdx-chicory-trace-s5
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
LIBGDX_DIR="/project/mjk76/ea442/promptstudy/libgdx"
OUT_DIR="/scratch/mjk76/ea442/promptstudy"

TRACE_OUT_DIR="${OUT_DIR}/libgdx-s5-chicory-out"
WORK_DIR="${OUT_DIR}/libgdx-s5-chicory"
GRADLE_HOME_DIR="${OUT_DIR}/libgdx-s5-gradle-home"

rm -rf "$TRACE_OUT_DIR"
mkdir -p "$TRACE_OUT_DIR" "$GRADLE_HOME_DIR"

echo "JAVA: $(which java)"

mkdir -p "$WORK_DIR"
rsync -a --delete --exclude='.git' --exclude='build' --exclude='.gradle' "${LIBGDX_DIR}/" "${WORK_DIR}/"

AGENT_FLAG="-javaagent:${DAIKON_JAR}=--output_dir=${TRACE_OUT_DIR} --ppt-select-pattern=^com\.badlogic\.gdx\.(utils|math)\..* --ppt-omit-pattern=com\.google\.protobuf --boot-classes=^(?!com\.badlogic\.gdx\.).* --sample-start=5 --nesting-depth=0"
AGENT_FLAG_GROOVY="${AGENT_FLAG//\\/\\\\}"

INIT_GRADLE="${WORK_DIR}/daikon-agent-init.gradle"
cat > "$INIT_GRADLE" <<GEOF
allprojects {
    tasks.withType(Test).configureEach {
        jvmArgs += ['${AGENT_FLAG_GROOVY}', '-Xmx48g']
        ignoreFailures = true
    }
}
GEOF

cd "$WORK_DIR"

echo ">>> gradle compileJava (warm build, no agent)"
./gradlew --no-daemon --console=plain --gradle-user-home "$GRADLE_HOME_DIR" \
  clean :gdx:compileJava

echo ">>> gradle test (javaagent attached via init script) -- this is the actual Chicory-instrumented run"
./gradlew --no-daemon --console=plain --gradle-user-home "$GRADLE_HOME_DIR" \
  --init-script "$INIT_GRADLE" \
  :gdx:test --info || true

./gradlew --no-daemon --gradle-user-home "$GRADLE_HOME_DIR" --stop || true

echo ">>> Chicory trace output directory:"
ls -la "$TRACE_OUT_DIR"

echo
echo ">>> Original Chicory-generated dtrace.gz files preserved in:"
echo ">>> $TRACE_OUT_DIR"
