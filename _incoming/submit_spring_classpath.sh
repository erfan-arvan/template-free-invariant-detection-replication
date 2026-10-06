#!/bin/bash -l
#SBATCH --job-name=spring-classpath
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
cd /project/mjk76/ea442/promptstudy/spring-framework

MODULE="${DP_SPRING_MODULE:-spring-core}"

JDK25_DIR="/scratch/mjk76/ea442/promptstudy/jdk25"
[[ -x "$JDK25_DIR/bin/javac" ]] || { echo "ERROR: JDK 25 not found at $JDK25_DIR -- run submit_spring_chicory_trace_s5.sh first, or copy its download logic here."; exit 1; }
echo ">>> Using JDK 25 at: $JDK25_DIR"

GRADLE_TOOLCHAIN_ARGS=(
  -Porg.gradle.java.installations.paths="$JDK25_DIR"
  -Porg.gradle.java.installations.auto-detect=false
  -Porg.gradle.java.installations.auto-download=false
)

GRADLE_HOME_DIR="/scratch/mjk76/ea442/promptstudy/spring-classpath-gradle-home"
mkdir -p "$GRADLE_HOME_DIR"

cat > dp-classpath-init.gradle <<'GRADLEEOF'
gradle.projectsEvaluated {
    def target = rootProject.findProject(':spring-core')
    if (target != null) {
        target.tasks.register("dpPrintClasspath") {
            doLast {
                def confName = project.hasProperty('dpConf') ? project.property('dpConf') : 'compileClasspath'
                def conf = target.configurations.findByName(confName)
                if (conf != null) {
                    println "DP_CLASSPATH_BEGIN"
                    println conf.resolve().collect { it.absolutePath }.join(File.pathSeparator)
                    println "DP_CLASSPATH_END"
                }
            }
        }
    }
}
GRADLEEOF

./gradlew -I dp-classpath-init.gradle \
  --no-daemon --console=plain --gradle-user-home "$GRADLE_HOME_DIR" \
  "${GRADLE_TOOLCHAIN_ARGS[@]}" \
  ":${MODULE}:compileJava" ":${MODULE}:dpPrintClasspath" -PdpConf=compileClasspath -q

rm -f dp-classpath-init.gradle

echo ">>> Done. Extract the classpath from this job's .out file with:"
echo "    sed -n '/DP_CLASSPATH_BEGIN/,/DP_CLASSPATH_END/p' spring-classpath.<JOBID>.out | sed '1d;\$d' > spring-cp.txt"
