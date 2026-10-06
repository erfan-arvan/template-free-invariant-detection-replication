#!/bin/bash -l
#SBATCH --job-name=spring-chicory-diag
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:30:00

set -euo pipefail
cd /project/mjk76/ea442/promptstudy

JDK25_DIR="/scratch/mjk76/ea442/promptstudy/jdk25"
WORK_DIR="/scratch/mjk76/ea442/promptstudy/spring-s5-chicory"
GRADLE_HOME_DIR="/scratch/mjk76/ea442/promptstudy/spring-s5-gradle-home-diag"
rm -rf "$GRADLE_HOME_DIR"
mkdir -p "$GRADLE_HOME_DIR"

GRADLE_TOOLCHAIN_ARGS=(
  -Porg.gradle.java.installations.paths="$JDK25_DIR"
  -Porg.gradle.java.installations.auto-detect=false
  -Porg.gradle.java.installations.auto-download=false
)

cd "$WORK_DIR"

echo ">>> [1/2] Checking spring-core testRuntimeClasspath for any daikon/chicory/bcel artifact"
./gradlew --no-daemon --console=plain --gradle-user-home "$GRADLE_HOME_DIR" \
  "${GRADLE_TOOLCHAIN_ARGS[@]}" \
  :spring-core:dependencies --configuration testRuntimeClasspath \
  | grep -i -E "daikon|chicory|bcel" || echo "(no matches -- nothing shadowing daikon/chicory/bcel on testRuntimeClasspath)"

echo ">>> [2/2] Printing actual jvmArgs for one Test Executor, running a single tiny test class"
cat > daikon-agent-init-diag.gradle <<'EOF'
gradle.rootProject {
    if (rootProject.findProject(':spring-core') == null) {
        return
    }
    afterEvaluate {
        project(':spring-core').tasks.withType(Test).configureEach {
            jvmArgs += ['-javaagent:/project/mjk76/ea442/promptstudy/daikon-spring-jdk25.jar=--output_dir=/scratch/mjk76/ea442/promptstudy/spring-s5-chicory-out --ppt-select-pattern=^org\\.springframework\\..* --ppt-omit-pattern=com\\.google\\.protobuf --boot-classes=^(?!org\\.springframework\\.).* --sample-start=5 --nesting-depth=0', '-Xmx8g']
            ignoreFailures = true
            doFirst {
                println ">>> ACTUAL jvmArgs: ${jvmArgs}"
            }
        }
    }
}
EOF

./gradlew --no-daemon --console=plain --gradle-user-home "$GRADLE_HOME_DIR" \
  --init-script daikon-agent-init-diag.gradle \
  "${GRADLE_TOOLCHAIN_ARGS[@]}" \
  :spring-core:test --tests "org.springframework.util.StringUtilsTests" || true

echo ">>> Diagnostic job done"
