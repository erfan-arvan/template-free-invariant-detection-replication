#!/bin/bash -l
#SBATCH --job-name=spring-chicory-trace-s5
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=192G
#SBATCH --time=08:00:00

set -euo pipefail
cd /project/mjk76/ea442/promptstudy

DAIKON_JAR="/project/mjk76/ea442/promptstudy/daikon-spring-jdk25.jar"
SPRING_DIR="/project/mjk76/ea442/promptstudy/spring-framework"
OUT_DIR="/scratch/mjk76/ea442/promptstudy"
MODULE="${DP_SPRING_MODULE:-spring-core}"

TRACE_OUT_DIR="${OUT_DIR}/spring-s5-chicory-out"
WORK_DIR="${OUT_DIR}/spring-s5-chicory"
GRADLE_HOME_DIR="${OUT_DIR}/spring-s5-gradle-home"

rm -rf "$TRACE_OUT_DIR"
rm -rf "$GRADLE_HOME_DIR"
mkdir -p "$TRACE_OUT_DIR" "$GRADLE_HOME_DIR"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
rsync -a --delete --exclude='.git' --exclude='/*/build/' --exclude='.gradle' "${SPRING_DIR}/" "${WORK_DIR}/"

JDK25_DIR="${OUT_DIR}/jdk25"
if [[ ! -x "$JDK25_DIR/bin/javac" ]]; then
  echo ">>> JDK 25 not found at $JDK25_DIR -- downloading Eclipse Temurin 25 (one-time)..."
  rm -rf "$JDK25_DIR"
  EXTRACT_DIR="${OUT_DIR}/jdk25_extract_tmp"
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$JDK25_DIR" "$EXTRACT_DIR"

  JDK25_TAR="${OUT_DIR}/jdk25.tar.gz"
  curl -fL --retry 3 --retry-delay 5 -o "$JDK25_TAR" \
    "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse"

  tar -xzf "$JDK25_TAR" -C "$EXTRACT_DIR"
  rm -f "$JDK25_TAR"

  JAVAC_PATH="$(find "$EXTRACT_DIR" -type f -name javac -path '*/bin/javac' | head -n1)"
  [[ -n "$JAVAC_PATH" ]] || { echo "ERROR: no bin/javac found under extracted JDK archive"; exit 1; }
  JDK_HOME_FOUND="$(dirname "$(dirname "$JAVAC_PATH")")"
  rm -rf "$JDK25_DIR"
  mv "$JDK_HOME_FOUND" "$JDK25_DIR"
  rm -rf "$EXTRACT_DIR"
  chmod -R u+rX "$JDK25_DIR"
  find "$JDK25_DIR/bin" -type f -exec chmod u+x {} +
fi
[[ -x "$JDK25_DIR/bin/javac" ]] || { echo "ERROR: JDK 25 not available at $JDK25_DIR"; exit 1; }
echo ">>> Using JDK 25 at: $JDK25_DIR"

GRADLE_TOOLCHAIN_ARGS=(
  -Porg.gradle.java.installations.paths="$JDK25_DIR"
  -Porg.gradle.java.installations.auto-detect=false
  -Porg.gradle.java.installations.auto-download=false
)

AGENT_FLAG="-javaagent:${DAIKON_JAR}=--output_dir=${TRACE_OUT_DIR} --ppt-select-pattern=^org\.springframework\..* --ppt-omit-pattern=com\.google\.protobuf --boot-classes=^(?!org\.springframework\.).* --sample-start=5 --nesting-depth=0"
AGENT_FLAG_GROOVY="${AGENT_FLAG//\\/\\\\}"

INIT_GRADLE="${WORK_DIR}/daikon-agent-init.gradle"
cat > "$INIT_GRADLE" <<GEOF
gradle.projectsEvaluated {
    def target = rootProject.findProject(':${MODULE}')
    if (target != null) {
        target.tasks.withType(Test).configureEach {
            jvmArgs += ['${AGENT_FLAG_GROOVY}', '-Xmx48g']
            ignoreFailures = true
        }
    }
}
GEOF

cd "$WORK_DIR"
echo ">>> Stopping any leaked Gradle daemons from prior runs on this GRADLE_USER_HOME"
./gradlew --stop --gradle-user-home "$GRADLE_HOME_DIR" || true

echo ">>> gradle compileJava (warm build, no agent)"
./gradlew --no-daemon --console=plain --gradle-user-home "$GRADLE_HOME_DIR" \
  "${GRADLE_TOOLCHAIN_ARGS[@]}" \
  ":${MODULE}:compileJava"

echo ">>> gradle test (javaagent attached via init script) -- this is the actual Chicory-instrumented run"
./gradlew --no-daemon --console=plain --gradle-user-home "$GRADLE_HOME_DIR" \
  --init-script "$INIT_GRADLE" \
  "${GRADLE_TOOLCHAIN_ARGS[@]}" \
  ":${MODULE}:test" || true

./gradlew --no-daemon --gradle-user-home "$GRADLE_HOME_DIR" --stop || true

echo ">>> Chicory trace output directory:"
ls -la "$TRACE_OUT_DIR"

echo
echo ">>> Original Chicory-generated dtrace.gz files preserved in:"
echo ">>> $TRACE_OUT_DIR"
