#!/bin/bash -l
#SBATCH --job-name=hudi-idflakies
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=128G
#SBATCH --time=04:00:00

set -euo pipefail

# `module spider Java/17.0.15` says Java/17.0.15 isn't available to load
# until `easybuild` is loaded first. Loading Java/17.0.15 directly (as this
# script did before) risks Lmod silently resolving/swapping to a different
# default Java version instead -- exactly the "reloaded: Java/17.0.15 =>
# Java/23.0.2" notice seen in an earlier, unrelated job's .err file.
module load easybuild
module load Java/17.0.15
java -version

cd /project/mjk76/ea442/promptstudy

########################################
# Config -- override any of these with e.g.
#   sbatch --export=ALL,TEST_CLASS=,ROUNDS=20 submit_hudi_idflakies.sh
########################################
HUDI_DIR="${HUDI_DIR:-/project/mjk76/ea442/promptstudy/hudi}"
IDFLAKIES_SRC_DIR="${IDFLAKIES_SRC_DIR:-/project/mjk76/ea442/promptstudy/iDFlakies}"
IDFLAKIES_WORK_DIR="${IDFLAKIES_WORK_DIR:-/project/mjk76/ea442/promptstudy/hudi-idflakies}"

# Same reasoning as run_daikonpp_hudi_java_client.sh's TMPDIR: without this,
# anything that falls back to the default temp dir lands in the node's local
# /tmp instead of scratch.
export TMPDIR="/scratch/mjk76/${USER}/promptstudy/tmp"
mkdir -p "$TMPDIR"

MODULE="hudi-client/hudi-java-client"

# Scoped to the test class where we already isolated a real race condition
# (SevenToEightUpgradeHandler / metadata-table upgrade, see run.log
# analysis). Set TEST_CLASS="" to run detection over the whole module
# instead -- MUCH more expensive, see ROUNDS note below before doing that.
TEST_CLASS="${TEST_CLASS:-org.apache.hudi.client.functional.TestHoodieJavaClientOnCopyOnWriteStorage}"

# Number of times idflakies reruns the (randomized/original) test order.
# Each round costs roughly what one manual `mvn test -Dtest=...` run of
# TEST_CLASS costs (~200s, per daikonpp-test-filter measurements) when
# TEST_CLASS is a single class. If you widen TEST_CLASS to the whole
# module, multiply by the module's full-suite cost (~17-22 min per run,
# per earlier profiling) -- lower ROUNDS accordingly or raise --time above.
ROUNDS="${ROUNDS:-10}"

echo "JAVA: $(which java)"

########################################
# Maven config -- same scratch-based local repo as the other hudi jobs
########################################
export MAVEN_HOME="/scratch/mjk76/${USER}/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"

# idflakies:detect executes test methods without Surefire's own fork
# (confirmed by the log: no "[Fork ...]"/forkedjvm output for the detect
# goal), so it never picks up the --add-opens flags Hudi's own pom.xml
# normally injects into Surefire's <argLine> (see the JDK 17/23-profile
# <argLine> blocks around line ~5648/~5666 of pom.xml). Without them, JDK
# 17+'s module system blocks the reflective Constructor.setAccessible()
# call in HoodieTestDataGenerator.genPseudoRandomUUID, which nearly every
# test's data-generation setup goes through -- so almost every test errored
# out near-instantly, in a way that had nothing to do with any real Hudi
# bug and made the "0 flaky tests" result meaningless.
#
# First attempt: added these flags to MAVEN_OPTS alone. That fixed a
# separate, earlier problem (a single-dash "-add-opens=..." typo copied
# from the pom crashed Maven's own JVM at launch -- job 1237215), proving
# MAVEN_OPTS does reach Maven's own top-level process. But job 1237262's
# actual results (75 of 76 errors still checkCanSetAccessible, verified by
# parsing the JSON in Python -- grep -c is useless here since the whole
# results file is one single line, so it can only ever report 0 or 1
# regardless of true occurrence count) showed the reflection errors were
# completely unaffected. Conclusion: idflakies must run test methods in a
# JVM process MAVEN_OPTS doesn't reach -- either a child process it spawns
# internally (MAVEN_OPTS is a Maven-launcher-specific convention a spawned
# java subprocess won't automatically inherit) or some other boundary.
#
# JDK_JAVA_OPTIONS/_JAVA_OPTIONS are different: the java launcher itself
# checks these env vars on every invocation, in every process, regardless
# of who spawned it or how deeply nested -- this is the exact mechanism
# edu.njit.jerse.daikonplusplus.JavaRunner (in the daikonplusplus tool this
# whole investigation started from) relies on to get its own flags into
# forked test JVMs it doesn't directly control. Setting both here for the
# same reason, on top of keeping MAVEN_OPTS since that's still needed for
# Maven's own process (heap size, local repo).
ADD_OPENS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.util.concurrent=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.base/sun.nio.cs=ALL-UNNAMED --add-opens=java.base/sun.security.action=ALL-UNNAMED --add-opens=java.base/sun.util.calendar=ALL-UNNAMED --add-opens=java.security.jgss/sun.security.krb5=ALL-UNNAMED"

export MAVEN_OPTS="-Xmx4g -Dmaven.repo.local=/scratch/mjk76/${USER}/.m2 ${ADD_OPENS}"
export JDK_JAVA_OPTIONS="${ADD_OPENS}"
export _JAVA_OPTIONS="${ADD_OPENS}"

echo "MVN: $(which mvn)"

########################################
# Sanity checks
########################################
[[ -d "$HUDI_DIR" ]] || { echo "ERROR: Hudi repo not found: $HUDI_DIR"; exit 1; }

########################################
# Step 1: clone iDFlakies if we don't already have a local copy of the
# source (idempotent -- safe to resubmit this job; leaves the clone in
# place for next time instead of re-cloning).
########################################
if [[ ! -d "$IDFLAKIES_SRC_DIR" ]]; then
  echo ">>> Cloning iDFlakies -> $IDFLAKIES_SRC_DIR"
  git clone https://github.com/UT-SE-Research/iDFlakies.git "$IDFLAKIES_SRC_DIR"
else
  echo ">>> iDFlakies source already present at $IDFLAKIES_SRC_DIR, skipping clone"
fi

# Resolve the plugin's actual version from the checked-out pom (avoids
# hardcoding/guessing a version string that may drift from the repo).
IDFLAKIES_VERSION="$(
  cd "$IDFLAKIES_SRC_DIR"
  mvn -q -Dexec.executable=echo help:evaluate -Dexpression=project.version -DforceStdout
)"
echo ">>> iDFlakies version: $IDFLAKIES_VERSION"

########################################
# Step 2: build+install the plugin into the shared local repo, if this
# exact version isn't already there.
########################################
PLUGIN_JAR="/scratch/mjk76/${USER}/.m2/edu/illinois/cs/idflakies-maven-plugin/${IDFLAKIES_VERSION}/idflakies-maven-plugin-${IDFLAKIES_VERSION}.jar"

if [[ ! -f "$PLUGIN_JAR" ]]; then
  echo ">>> Building/installing idflakies-maven-plugin ${IDFLAKIES_VERSION}"
  (
    cd "$IDFLAKIES_SRC_DIR"
    mvn -q install -DskipTests
  )
  [[ -f "$PLUGIN_JAR" ]] || { echo "ERROR: build did not produce $PLUGIN_JAR"; exit 1; }
else
  echo ">>> idflakies-maven-plugin ${IDFLAKIES_VERSION} already in local repo, skipping build"
fi

########################################
# Step 3: fresh local copy of hudi, so pom-modify's edits (and idflakies'
# own run artifacts) never touch the real checkout other jobs use.
# rsync only ever reads from $HUDI_DIR and writes into $IDFLAKIES_WORK_DIR
# -- the original checkout is never opened for writing. .git/target
# excluded (unnecessary history + regeneratable build output); rerunning
# this job is incremental (only changed files re-copied).
########################################
echo ">>> Syncing $HUDI_DIR -> $IDFLAKIES_WORK_DIR"
mkdir -p "$IDFLAKIES_WORK_DIR"
rsync -a --delete --exclude='.git' --exclude='target' "$HUDI_DIR/" "$IDFLAKIES_WORK_DIR/"

########################################
# Step 4: wire the plugin into that copy's pom.xml (never touches
# $HUDI_DIR/pom.xml -- only the rsynced copy).
########################################
bash "$IDFLAKIES_SRC_DIR/pom-modify/modify-project.sh" \
  "$IDFLAKIES_WORK_DIR" idflakies-maven-plugin "$IDFLAKIES_VERSION"

########################################
# Step 5: run detection
########################################
cd "$IDFLAKIES_WORK_DIR"

DETECT_ARGS=(
  -pl "$MODULE"
  # Deliberately no -am here, matching how run_daikonpp_hudi_java_client.sh's
  # own test runner works: hudi-common:1.2.0-SNAPSHOT is already installed in
  # the shared .m2 repo from earlier runs, so Maven resolves it as a normal
  # dependency instead of pulling it into this command's reactor. Adding -am
  # here would (and did, in an earlier run of this script) drag hudi-common
  # into the reactor, and idflakies:detect runs per-module in whatever
  # reactor it's given -- so it started detecting flakiness on hudi-common's
  # 1063 tests instead of just the target class below.
  -DskipITs
  -Duser.timezone=UTC
  -Dcheckstyle.skip=true
  -Dcheckstyle.skipExec=true
  -Denforcer.skip=true
  -Drat.skip=true
  idflakies:detect
  -Ddetector.detector_type=random-class-method
  -Ddt.randomize.rounds="${ROUNDS}"
  # Our baseline run already errors even in the original order (that's the
  # whole reason we're here -- see the SevenToEightUpgradeHandler race in
  # run.log), so requiring an all-pass baseline would abort before ever
  # reaching a rerun.
  -Ddt.detector.original_order.all_must_pass=false
)

if [[ -n "$TEST_CLASS" ]]; then
  DETECT_ARGS+=( -Dtest="$TEST_CLASS" )
fi

echo ">>> mvn ${DETECT_ARGS[*]}"
mvn "${DETECT_ARGS[@]}"

########################################
# Report where results landed
#
# The README's documented lib/detection-results/random/ +
# all_flaky_tests_list.csv paths don't match what 2.0.1-SNAPSHOT actually
# produces -- confirmed against a real run, the plugin writes here instead:
########################################
RESULTS_DIR="$IDFLAKIES_WORK_DIR/$MODULE/.dtfixingtools/detection-results"

echo ">>> Detection results dir:"
ls -la "$RESULTS_DIR" 2>/dev/null || echo "  (not found -- check the mvn output above for errors)"

echo ">>> Flaky test list (list.txt -- empty means none found):"
cat "$RESULTS_DIR/list.txt" 2>/dev/null || echo "  (not found: $RESULTS_DIR/list.txt)"

echo ">>> Detailed dependent-test JSON (flaky-lists.json):"
cat "$RESULTS_DIR/flaky-lists.json" 2>/dev/null || echo "  (not found: $RESULTS_DIR/flaky-lists.json)"

echo ">>> Done."
