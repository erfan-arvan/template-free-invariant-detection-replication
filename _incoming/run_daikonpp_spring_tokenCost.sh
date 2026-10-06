#!/usr/bin/env bash
set -uo pipefail

########################################
# PATHS
########################################
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="${ROOT:-$SCRIPT_DIR}"
SPRING_DIR="${SPRING_DIR:-$ROOT/spring-framework}"
DPP_DIR="${DPP_DIR:-$ROOT/daikonplusplus}"

# ASSUMPTION: targeting spring-core (foundational, low-dependency module --
# analogous to dubbo-common/netty:common; good first pipeline smoke test).
# Override DP_SPRING_MODULE to point at a different Gradle project (e.g.
# spring-beans, spring-context) if needed. Note: spring-core also has
# version-gated source overlays (src/main/java21, src/main/java24) --
# we deliberately target only the baseline src/main/java.
MODULE="${DP_SPRING_MODULE:-spring-core}"
MAIN_SRC="$MODULE/src/main/java"
TEST_SRC="$MODULE/src/test/java"

########################################
# HPC scratch
########################################
ACCOUNT="${ACCOUNT:-mjk76}"
SCRATCH_ROOT="/scratch/${ACCOUNT}/${USER}"
SCRATCH_BASE="${SCRATCH_ROOT}/token_cost_fewshot_class_doc"

mkdir -p "$SCRATCH_BASE"

export TMPDIR="${SCRATCH_BASE}/tmp"
export DP_WORKDIR="${SCRATCH_BASE}/daikonpp_work"

mkdir -p "$TMPDIR" "$DP_WORKDIR"

export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.io.tmpdir=${TMPDIR}"

########################################
# SHM base (bypass /dev/shm for invariant-execution recording)
########################################
# App.java records each invariant's execution synchronously to a shm
# directory (Files.createFile under shm/ex/<uuid>) the instant it fires, with
# no dependency on any JVM shutdown hook -- this is the PRIMARY recording
# mechanism, and it's normally rock solid (confirmed working for
# Dubbo/Netty/Hudi). For this run, both it AND the separate shutdown-hook
# sidecar fallback (.daikonpp-events/) came back completely empty after a
# 5166-test run, even though only 2 tests genuinely failed -- meaning the
# other 5164 tests ran fine but recorded nothing. App.java defaults to
# /dev/shm, but honors DP_SHM_BASE as an override (see App.java:662-672).
# Gradle's test task runs each test batch in a forked "Gradle Test Executor"
# worker process, a different process-spawning path than Maven/surefire's
# forked JVMs (which is what Dubbo/Netty/Hudi actually exercised) -- if that
# worker's sandbox/namespace doesn't share this job's /dev/shm the same way,
# every write would silently no-op (DpRuntime's own shm setup is wrapped in
# a swallow-everything catch block by design, so this fails silently rather
# than with a visible error). Point it at scratch instead, which every other
# part of this pipeline already reads/writes from successfully.
export DP_SHM_BASE="${SCRATCH_BASE}/shm"
mkdir -p "$DP_SHM_BASE"

########################################
# Gradle config (for the TARGET project, spring-framework -- separate
# from any Gradle used to build daikonplusplus itself)
########################################
# Redirect Gradle's own caches/downloads into scratch, same idea as
# -Dmaven.repo.local for the Maven-based scripts.
export GRADLE_USER_HOME="${SCRATCH_BASE}/.gradle-spring"
mkdir -p "$GRADLE_USER_HOME"

# Daikon++'s autofilter invokes the compile/test script dozens of times per
# run and stale-kills a pass that hangs -- but killing that script's process
# does NOT kill the Gradle daemon it spawned (daemons are designed to
# outlive their launching client and be reused). Over enough kill/retry
# cycles this leaves orphaned daemons holding locks on this GRADLE_USER_HOME,
# and a later pass can deadlock waiting on one of them ("N busy and M
# stopped Daemons could not be reused" in the log, followed by total
# silence). Maven has no equivalent persistent daemon, which is why this
# never showed up on Dubbo/Netty. Clear out anything already leaked before
# this run starts.
if [[ -x "$SPRING_DIR/gradlew" ]]; then
  ( cd "$SPRING_DIR" && ./gradlew --stop --gradle-user-home "$GRADLE_USER_HOME" ) || true
fi

# Note: do NOT `module load` a specific Java version here at top level. The
# gradle compile/test steps below point Gradle at a self-provisioned JDK 25
# directly (see below) rather than touching PATH. The Daikon++ jar must run
# under whatever Java built it (loaded by the caller, e.g. submit.sh) --
# switching java on the PATH here would downgrade that final `java -jar`
# invocation too.

########################################
# JDK 25 (no cluster module available)
########################################
# spring-framework's Gradle toolchain pins JavaLanguageVersion.of(25), and
# there's no Foojay auto-download resolver wired into its settings.gradle,
# so Gradle won't fetch a JDK on its own. Since there's no `module load
# Java/25` on this cluster either, we download Eclipse Temurin 25 ourselves
# once into scratch (compute nodes already reach repo.maven.apache.org per
# the earlier Dubbo run, so this should work the same way) and hand Gradle
# that exact path via -Porg.gradle.java.installations.paths -- this bypasses
# PATH/module system entirely, so it's independent of what's `module
# load`-able on this cluster.
JDK25_DIR="${SCRATCH_BASE}/jdk25"
if [[ ! -x "$JDK25_DIR/bin/javac" ]]; then
  echo ">>> JDK 25 not found at $JDK25_DIR -- downloading Eclipse Temurin 25 (one-time)..."
  rm -rf "$JDK25_DIR"
  EXTRACT_DIR="${SCRATCH_BASE}/jdk25_extract_tmp"
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$JDK25_DIR" "$EXTRACT_DIR"

  JDK25_TAR="${SCRATCH_BASE}/jdk25.tar.gz"
  HTTP_CODE=$(curl -fL --retry 3 --retry-delay 5 -o "$JDK25_TAR" -w '%{http_code}' \
    "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse") \
    || { echo "ERROR: curl download failed (HTTP $HTTP_CODE)"; exit 1; }
  echo ">>> Download HTTP status: $HTTP_CODE, size: $(stat -c%s "$JDK25_TAR" 2>/dev/null || wc -c < "$JDK25_TAR") bytes"

  # Sanity-check it's actually a gzip archive, not an HTML error page or
  # some proxy interstitial that curl treated as a 200.
  if [[ "$(head -c2 "$JDK25_TAR" | xxd -p 2>/dev/null)" != "1f8b" ]]; then
    echo "ERROR: downloaded file is not a gzip archive. First 300 bytes:"
    head -c 300 "$JDK25_TAR"
    echo
    exit 1
  fi

  tar -xzf "$JDK25_TAR" -C "$EXTRACT_DIR" || { echo "ERROR: tar extraction failed"; exit 1; }
  rm -f "$JDK25_TAR"

  # Don't assume a fixed nesting depth (--strip-components=1 broke on the
  # cluster) -- locate the extracted javac wherever it landed and use its
  # JDK home directly, then copy that into JDK25_DIR.
  JAVAC_PATH="$(find "$EXTRACT_DIR" -type f -name javac -path '*/bin/javac' | head -n1)"
  if [[ -z "$JAVAC_PATH" ]]; then
    echo "ERROR: no bin/javac found anywhere under extracted archive. Extracted layout:"
    find "$EXTRACT_DIR" -maxdepth 3
    exit 1
  fi
  JDK_HOME_FOUND="$(dirname "$(dirname "$JAVAC_PATH")")"
  echo ">>> Found extracted JDK home at: $JDK_HOME_FOUND"
  rm -rf "$JDK25_DIR"
  mv "$JDK_HOME_FOUND" "$JDK25_DIR"
  rm -rf "$EXTRACT_DIR"

  # Safety net: some filesystems / extraction paths don't preserve the exec
  # bit. Re-assert it explicitly rather than trust tar's mode preservation.
  chmod -R u+rX "$JDK25_DIR"
  find "$JDK25_DIR/bin" -type f -exec chmod u+x {} +
  if [[ -d "$JDK25_DIR/lib/jspawnhelper" ]]; then chmod u+x "$JDK25_DIR/lib/jspawnhelper"; fi
fi
[[ -x "$JDK25_DIR/bin/javac" ]] || { echo "ERROR: JDK 25 download/extract failed, no executable javac at $JDK25_DIR/bin/javac"; exit 1; }
echo ">>> Using JDK 25 at: $JDK25_DIR"
"$JDK25_DIR/bin/javac" -version

########################################
# LLM / Cassette config
########################################
export DP_LLM_CASSETTES="${DP_LLM_CASSETTES:-$DPP_DIR/src/test/cassettes}"

########################################
# Other configs
########################################
MAXK="${MAXK:-5}"

########################################
# Sanity checks
########################################
[[ -d "$SPRING_DIR" ]] || { echo "ERROR: spring-framework repo not found: $SPRING_DIR"; exit 1; }
[[ -x "$DPP_DIR/gradlew" ]] || { echo "ERROR: Daikon++ repo not found: $DPP_DIR"; exit 1; }
[[ -d "$SPRING_DIR/$MODULE" ]] || { echo "ERROR: Module '$MODULE' not found under $SPRING_DIR"; exit 1; }
[[ -x "$SPRING_DIR/gradlew" ]] || { echo "ERROR: $SPRING_DIR/gradlew not found/executable"; exit 1; }

########################################
# Use pre-built jar
########################################
DAIKONPP_JAR="${DP_DAIKONPP_JAR:?ERROR: DP_DAIKONPP_JAR not set}"

########################################
# External COMPILE script (IDENTICAL to laptop)
########################################
COMPILE_SCRIPT="$SCRATCH_BASE/spring_${MODULE}_compile.sh"

cat > "$COMPILE_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail

cd "\$DP_PROJECT_ROOT"

# -Werror is hardcoded into compileJava's compiler args in
# buildSrc/.../JavaConventions.java (main sources only -- test compile
# deliberately omits it). Injected invariant expressions occasionally call a
# deprecated API (isAccessible(), toByteBuffer(), isDaemon()), which is only
# a warning normally, but -Werror promotes it to a hard failure -- and
# unlike a real "file:line: error:" diagnostic, Daikon++'s autofilter can't
# reliably parse a warning-turned-error to know which invariant to strip,
# so the run stalls with "no progress". Patch it out of the working copy's
# buildSrc every run (idempotent: no-op once already patched); Gradle
# detects the changed buildSrc source and recompiles it automatically.
sed -i 's/"-Xlint:unchecked", "-Werror"/"-Xlint:unchecked"/' \\
  "\$DP_PROJECT_ROOT/buildSrc/src/main/java/org/springframework/build/JavaConventions.java"

# Every spring-* module gets Spring's own "io.spring.nullability" plugin via
# gradle/spring-module.gradle (root build.gradle:9 declares it, :80-81
# applies gradle/spring-module.gradle to every moduleProject). That plugin
# wraps NullAway/Error Prone. spring-core never opts out the way
# spring-instrument/spring-context-indexer do (their own *.gradle files set
# `nullability { requireExplicitNullMarking = false }`), so Daikon++'s
# generated daikonpp/DpRuntime.java -- which has no @NullMarked/@NullUnmarked
# annotation, since it isn't instrumented target code with an "original" to
# restore -- trips NullAway's RequireExplicitNullMarking check and fails the
# build with an error the autofilter can't attribute to any invariant.
# Disable the plugin's application for every module, same idempotent
# working-copy patch as the -Werror one above.
sed -i 's/apply plugin: "io\\.spring\\.nullability"/\\/\\/ Daikon++: nullability\\/NullAway disabled/' \\
  "\$DP_PROJECT_ROOT/gradle/spring-module.gradle"

# Gradle configures every subproject in settings.gradle before running any
# task, even one scoped to :spring-core:compileJava -- so once the plugin
# application above is gone, any *.gradle file that still calls the now
# -nonexistent `nullability { ... }` extension (e.g. spring-instrument,
# spring-context-indexer, which use it to opt OUT of the check with
# `requireExplicitNullMarking = false`) fails project evaluation with
# "Could not find method nullability()" before compileJava ever runs.
# Comment out every such block, wherever it appears, rather than hardcoding
# today's two known files (in case a future module adds one). The sed range
# comments every line from the block's opening `nullability {` through its
# closing `}` (both un-indented, matching Spring's own formatting); once
# commented, the opening line no longer matches, so this is idempotent.
for f in \$(grep -rl '^nullability {\$' "\$DP_PROJECT_ROOT" --include='*.gradle' 2>/dev/null); do
  sed -i '/^nullability {\$/,/^}\$/s/^/\\/\\/ /' "\$f"
done

# Deliberately calling ONLY compileJava (not "build" or "check"). Spring's
# Checkstyle, Spring-Java-Format, and ArchUnit-based architecture-check
# plugins are all wired to the "check" task in buildSrc conventions
# (confirmed: ArchitecturePlugin does checkTask.dependsOn(architectureChecks),
# and the Gradle checkstyle/format plugins follow the same "check" convention
# by default) -- none of them are dependencies of compileJava/test, so
# invoking those tasks directly skips all of them with no skip flags needed.
# (Deliberately NOT using "-x <task>" here: excluding a task name that turns
# out not to exist makes Gradle fail hard with "task not found", and since
# compileJava/test don't pull these tasks in anyway, excluding them buys
# nothing.)
#
# -Porg.gradle.java.installations.paths points Gradle's toolchain resolver
# directly at the JDK 25 we downloaded ourselves -- no module load, no PATH
# changes, independent of whatever's `module load`-able on this cluster.
./gradlew \\
  --console=plain \\
  --no-daemon \\
  --gradle-user-home "\$GRADLE_USER_HOME" \\
  -Porg.gradle.java.installations.paths=$JDK25_DIR \\
  -Porg.gradle.java.installations.auto-detect=false \\
  -Porg.gradle.java.installations.auto-download=false \\
  :${MODULE}:compileJava
EOF

chmod +x "$COMPILE_SCRIPT"

export DP_COMPILE_MAIN_SCRIPT="$COMPILE_SCRIPT"
export DP_COMPILE_TEST_SCRIPT="$COMPILE_SCRIPT"

########################################
# External TEST runner (IDENTICAL to laptop)
########################################
RUNNER="$SCRATCH_BASE/spring_${MODULE}_run_tests.sh"

cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
set -e


# Same idempotent working-copy patches as \$COMPILE_SCRIPT (see there for the
# full explanation of each). By the time the autofilter loop calls this
# runner, \$COMPILE_SCRIPT has normally already applied all of them -- these
# are here so this script doesn't depend on that ordering (e.g. if it's ever
# invoked standalone).
sed -i 's/"-Xlint:unchecked", "-Werror"/"-Xlint:unchecked"/' \\
  "\$DP_PROJECT_ROOT/buildSrc/src/main/java/org/springframework/build/JavaConventions.java"
sed -i 's/apply plugin: "io\\.spring\\.nullability"/\\/\\/ Daikon++: nullability\\/NullAway disabled/' \\
  "\$DP_PROJECT_ROOT/gradle/spring-module.gradle"
for f in \$(grep -rl '^nullability {\$' "\$DP_PROJECT_ROOT" --include='*.gradle' 2>/dev/null); do
  sed -i '/^nullability {\$/,/^}\$/s/^/\\/\\/ /' "\$f"
done

./gradlew \\
  --console=plain \\
  --no-daemon \\
  --gradle-user-home "\$GRADLE_USER_HOME" \\
  -Porg.gradle.java.installations.paths=$JDK25_DIR \\
  -Porg.gradle.java.installations.auto-detect=false \\
  -Porg.gradle.java.installations.auto-download=false \\
  :${MODULE}:test
EOF

chmod +x "$RUNNER"

export DP_EXTERNAL_CMD="$RUNNER"

########################################
# Minimal classpath (Gradle's output dir, analogous to target/classes)
########################################
export DP_EXTERNAL_COMPILE_CP="$SPRING_DIR/$MODULE/build/classes/java/main:$SPRING_DIR/$MODULE/build/resources/main"

########################################
# Project Root
########################################
export DP_PROJECT_ROOT="$SPRING_DIR"

# Call sites
export DP_CALL_SITES_INDEX="/project/${ACCOUNT}/${USER}/promptstudy/spring_callsites.json"
export DP_IO_EXAMPLES_INDEX="/project/mjk76/ea442/promptstudy/spring-s5_io_examples.json"

########################################
# Run Daikon++ (IDENTICAL to laptop)
########################################
echo ">>> Running Daikon++"

cd "$SPRING_DIR"

CMD=(
  java -jar "$DAIKONPP_JAR"
  --external-project
  --project-root "$SPRING_DIR"
  --main-src "$MAIN_SRC"
  --test-src "$TEST_SRC"
  --runner-script "$RUNNER"
  "$MAXK"
)

echo ">>> CMD: ${CMD[*]}"
"${CMD[@]}"

echo ">>> Done."
