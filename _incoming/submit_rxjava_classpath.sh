#!/bin/bash -l
#SBATCH --job-name=rxjava-classpath
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
module load Java/23.0.2
export JDK_EXPERIMENTAL=23
cd /project/mjk76/ea442/promptstudy/rxjava

# Init script (not part of rxjava's own build files) that adds a task
# printing the resolved compile classpath for a given project/configuration.
cat > dp-classpath-init.gradle <<'GRADLEEOF'
gradle.projectsEvaluated {
    rootProject.allprojects { p ->
        p.tasks.register("dpPrintClasspath") {
            doLast {
                def confName = project.hasProperty('dpConf') ? project.property('dpConf') : 'compileClasspath'
                def conf = p.configurations.findByName(confName)
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

./gradlew -I dp-classpath-init.gradle dpPrintClasspath -PdpConf=compileClasspath --no-daemon -q

rm -f dp-classpath-init.gradle

echo ">>> Done. Extract the classpath from this job's .out file with:"
echo "    sed -n '/DP_CLASSPATH_BEGIN/,/DP_CLASSPATH_END/p' rxjava-classpath.<JOBID>.out | sed '1d;\$d' > rxjava-cp.txt"
