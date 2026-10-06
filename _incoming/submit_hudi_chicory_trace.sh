#!/bin/bash -l
#SBATCH --job-name=hudi-chicory-trace
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err
#SBATCH --partition=general
#SBATCH --qos=standard
#SBATCH --account=mjk76
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=72:00:00

set -euo pipefail
module load Java/17.0.15
cd /project/mjk76/ea442/promptstudy

DAIKON_JAR="/project/mjk76/ea442/promptstudy/daikon.jar"
OUT_DIR="/scratch/mjk76/ea442/promptstudy"
PROJECT_NAME="hudi"

# Timing: logs both to this job's own .out (via _timing) and appends to a
# single shared log across all projects/runs so total runtimes can be
# compared without digging through each job's .out file individually.
_now() { date +%s; }
_timing() {
    local label="$1" start="$2" end
    end=$(date +%s)
    printf '[TIMING] %-28s %ds  (%s -> %s)\n' \
        "$label" "$((end - start))" \
        "$(date -d "@$start" +%T)" "$(date -d "@$end" +%T)"
    printf '%s\t%s\t%s\t%ds\t%s\t%s\t%s\n' \
        "$(date -Iseconds)" "$PROJECT_NAME" "${SLURM_JOB_ID:-nojob}" \
        "$((end - start))" "$label" \
        "$(date -d "@$start" -Iseconds)" "$(date -d "@$end" -Iseconds)" \
        >> "${OUT_DIR}/chicory_timing.log"
}
RUN_START=$(_now)
echo "[TIMING] === ${PROJECT_NAME} chicory trace run started $(date -Iseconds) ==="

# Each run gets its own job-ID-named subdirectory instead of a fixed path,
# so rerunning this script never deletes a previous run's original
# Chicory-generated dtrace.gz files -- those are what you actually run
# Daikon against. "latest" always points at the most recent run.
TRACE_BASE_DIR="${OUT_DIR}/hudi-chicory-out"
RUN_ID="${SLURM_JOB_ID:-$(date +%Y%m%d-%H%M%S)}"
TRACE_OUT_DIR="${TRACE_BASE_DIR}/${RUN_ID}"
mkdir -p "$TRACE_OUT_DIR"

export MAVEN_HOME="/scratch/mjk76/${USER}/apache-maven-3.9.9"
export PATH="$MAVEN_HOME/bin:$PATH"

# job 1146776 OOM'd in "surefire-forkedjvm-stream-flusher" -- that thread
# runs in the parent `mvn` process (it relays the forked test JVM's
# stdout/stderr), not in the test JVM itself. With
# -Dmaven.test.failure.ignore=true, all 88 failing tests ran to completion
# instead of stopping at the first one, and each dumped the same huge
# (100+ line) VerifyError stack trace, which the parent process had to
# buffer/relay. MAVEN_OPTS never set an explicit -Xmx, so the parent JVM
# was running on Java's small default heap regardless of how much memory
# SLURM allocated to the job (`--mem` controls the node allocation, not the
# JVM's own heap limit -- Java computes -Xmx independently unless told
# otherwise). Bumped --mem to 48G above for headroom and set -Xmx8g here
# explicitly so the parent process actually uses more of what's available.
export MAVEN_OPTS="-Xmx8g -Dmaven.repo.local=/scratch/mjk76/${USER}/.m2"

echo "JAVA: $(which java)"
echo "MVN: $(which mvn)"

# v1 (_JAVA_OPTIONS, no quoting) split the agent's argument string on the
# embedded space and crashed with "Unrecognized option".
#
# v2/v3 (JDK_JAVA_OPTIONS, which DOES support quoting) fixed that, but
# JDK_JAVA_OPTIONS/_JAVA_OPTIONS attach to EVERY java process, including the
# `mvn` launcher JVM itself -- not just the Surefire-forked JVM that actually
# runs hudi's tests. So Chicory was instrumenting Maven's own bootstrap
# classes and its whole dependency graph (Plexus ClassWorlds, Guava, Guice,
# Sisu, jansi) before any hudi test code even ran. --ppt-select-pattern only
# filters what gets WRITTEN to the trace, not which classes the
# ClassFileTransformer attempts to rewrite -- so it never stopped Chicory
# from touching those classes, and BCEL's stack-map computation chokes on
# their modern bytecode (lambdas/invokedynamic), producing the
# "bcelCalcStackTypes failure" errors across Maven/Guava/Guice/Sisu/jansi
# classes we saw in job 1146072.
#
# v4: -DargLine turned out to be a dead end. hudi/pom.xml hardcodes literal
# <argLine> values (not @{argLine} placeholders) at lines ~214, ~2928, ~2938
# -- one of the two JDK-version-specific profiles (2928/2938, which carry the
# --add-opens flags JDK 17 needs) is almost certainly the one active here.
# A literal <configuration> value in the POM always wins over a same-named
# -D property passed on the command line; the property binding is only a
# fallback for when the POM doesn't set it explicitly. That's why job
# 1146091 produced a completely empty trace with zero errors: Surefire never
# saw our -javaagent flag at all.
#
# v6 (-f pom.chicory.xml) turned out to be a dead end too: -f only changes
# which file Maven starts the reactor from. Each child module (hudi-common,
# hudi-java-client) still resolves its own <parent> against the real
# hudi/pom.xml on disk, not our patched sibling file -- job 1146620 ran the
# full test suite successfully but produced zero trace output and zero
# Chicory log lines, confirming the agent never attached.
#
# v7: make a full LOCAL copy of the hudi tree (rsync, same disk, no network,
# not a git clone) and patch pom.xml only inside that copy. This is the only
# approach that's actually worked: with a fully separate directory tree,
# every child module's <parent> relativePath naturally resolves within the
# copy, so there's no ambiguity about which pom.xml is in effect.
# hudi/pom.xml (the user's real checkout) is never opened, read for editing,
# or written to -- rsync only reads from it to populate the copy.
#
# .git and target/ are excluded: .git is unnecessary multi-GB history we
# don't need for a build, and target/ is build output that gets regenerated
# fresh anyway -- skipping both makes this fast and keeps disk usage low.
# Re-running rsync is safe and incremental (only changed files re-copied).
unset JDK_JAVA_OPTIONS
#
# v10: HoodieFieldOrder.<clinit> / HoodieTableType.<clinit> hit a genuine,
# unfixable-from-outside VerifyError in Chicory's bundled BCEL (confirmed by
# reading Instrument.java/Chicory.java source: Chicory.checkStaticInit is a
# hardcoded `public static final boolean = true`, so addInvokeToClinit()
# ALWAYS runs and produces corrupted bytecode for these classes in memory --
# there is no flag to turn that off). The fix that DOES work: transform()
# only hands the corrupted bytecode to the JVM if classInfo.shouldInclude is
# true, and shouldInclude is computed per-class from shouldIgnore(className,
# methodName, pptName) -- which matches --ppt-omit-pattern against className
# too. So omitting these two classes by name makes every one of their
# (non-clinit) methods excluded, shouldInclude stays false for the whole
# class, and transform() falls back to returning the ORIGINAL unmodified
# bytecode -- no VerifyError, class loads fine. If later runs reveal more
# classes crashing the same way, add them to this pattern too.
# job 1146967: with the heap fix in place, the run made real progress (21M+
# lines of genuine test execution logged) but two things surfaced --
#
# 1. it hit the 6h --time limit before finishing (bumped to 16h, then to
#    72h -- see #SBATCH --time above -- to match the other chicory jobs).
#
# 2. Chicory's instrument_all_methods/createClinit hit the SAME BCEL
#    constant-pool-corruption bug on classes that have nothing to do with
#    hudi at all (e.g. org.apache.hadoop.hdfs.protocol.proto
#    .DatanodeProtocolProtos$FinalizeCommandProto$Builder). Unlike the
#    clinit-rewrite case, this crash happens INSIDE instrumentClass() itself,
#    which transform()'s outer try/catch (Instrument.java:290-294) catches
#    and RE-THROWS as a RuntimeException -- so the class fails to load
#    entirely. --ppt-omit-pattern can't prevent this: it only affects
#    whether the (already-corrupted) bytecode gets returned, not whether
#    Chicory attempts to instrument the class in the first place.
#
#    The actual guard for that is --boot-classes, checked in isBootClass()
#    BEFORE instrumentClass() is ever called. Using a negative-lookahead
#    regex to treat everything that is NOT org.apache.hudi.* as a boot class
#    means Chicory never touches Hadoop/Guava/Jackson/etc. at all -- no
#    corruption risk from them, and as a side effect much less BCEL work
#    per class loaded, which should also help with the time-limit problem.
# job 1149036: with boot-classes scoping the crashes are gone, but recording
# EVERY call/return at every matched program point (sample_start defaults to
# 0 = unlimited) produced a 93GB dtrace.gz and the job hit the 24h TIMEOUT
# before mvn test even finished. Per-call trace writing (formatting args,
# walking object structure, disk I/O) is expensive enough that it's very
# likely the dominant cost driving the 24h+ runtime, not the test logic
# itself.
# --sample-start=N records every call in full for the first N invocations of
# each program point, then decays to a shrinking sample rate instead of
# recording forever -- still captures real, varied I/O examples at every
# program point, just not literally every single call.
# job 1177196: 24 minutes, real 557M-line trace -- sampling fixed the
# runtime/size problem. But 89/238 tests errored on the SAME BCEL
# clinit-VerifyError bug, this time on org.apache.hudi.com.google.protobuf
# .Descriptors$FieldDescriptor -- hudi's shaded/relocated protobuf (shade
# plugin repackages com.google.protobuf under org.apache.hudi.* to dodge
# version conflicts). Because it's namespaced under org.apache.hudi.*,
# --boot-classes doesn't exclude it. Same fix as HoodieFieldOrder/
# HoodieTableType: omit it by name so shouldInclude stays false for the
# whole class and transform() falls back to the original, uncorrupted
# bytecode.
# hudi_io_examples.json review: even a simple (String,String):int method's
# "args" came back as a ~40-entry bag mixing the real parameters with enum
# tables, config-map contents, and class names -- because nesting_depth
# defaults to 2, so Chicory walks 2 levels into every variable's object
# graph, including `this`, and emits every reachable field as its own
# variable. That's useful for Daikon's original invariant-detection purpose
# but wrong for isolated I/O examples: it erases the distinction between
# "the actual parameter" and "some field two hops off `this`."
# --nesting-depth=0 stops that traversal so only the top-level
# parameters/return (and `this` itself, not its fields) get emitted.
#
# NOTE: TRACE_OUT_DIR/HUDI_CHICORY_DIR below now point at
# /scratch (not /project) to match every other chicory trace script --
# /project has a much smaller quota and isn't meant to hold large generated
# trace output.
AGENT_FLAG="-javaagent:${DAIKON_JAR}=--output_dir=${TRACE_OUT_DIR} --ppt-select-pattern=^org\.apache\.hudi\..* --ppt-omit-pattern=HoodieFieldOrder|HoodieTableType|com\.google\.protobuf --boot-classes=^(?!org\.apache\.hudi\.).* --sample-start=5 --nesting-depth=0"
HUDI_CHICORY_DIR="${OUT_DIR}/hudi-chicory"

mkdir -p "$HUDI_CHICORY_DIR"
rsync -a --delete --exclude='.git' --exclude='target' hudi/ "$HUDI_CHICORY_DIR/"

python3 - "$AGENT_FLAG" "$HUDI_CHICORY_DIR/pom.xml" <<'EOF'
import sys

agent_flag = sys.argv[1]
path = sys.argv[2]

with open(path) as f:
    content = f.read()

old = "-XX:-OmitStackTraceInFastThrow</argLine>"
new = f'-XX:-OmitStackTraceInFastThrow "{agent_flag}" -Xmx24g</argLine>'

count = content.count(old)
if count == 0:
    raise SystemExit("ERROR: no occurrences of the expected argLine tail found -- pom.xml format may have changed")

content = content.replace(old, new)
with open(path, "w") as f:
    f.write(content)
print(f"Patched {count} occurrence(s) of argLine in {path} (hudi/pom.xml itself untouched)")
EOF

cd "$HUDI_CHICORY_DIR"

COMPILER_FLAG="-Dmaven.compiler.compilerArgument=-XDstringConcat=inline"

echo "[TIMING] === mvn install (compile, no chicory agent) STARTING $(date -Iseconds) ==="
t0=$(_now)

mvn -q \
  -pl hudi-client/hudi-java-client -am \
  install \
  -DskipTests \
  -Dcheckstyle.skip=true \
  -Dcheckstyle.skipExec=true \
  -Denforcer.skip=true \
  -Drat.skip=true \
  "${COMPILER_FLAG}"

_timing "mvn install (compile, no chicory agent)" "$t0"

echo "[TIMING] === mvn test (Chicory instrumented) STARTING $(date -Iseconds) ==="
t0=$(_now)

mvn -q \
  -pl hudi-client/hudi-java-client \
  -DskipITs \
  -Duser.timezone=UTC \
  -Dcheckstyle.skip=true \
  -Dcheckstyle.skipExec=true \
  -Denforcer.skip=true \
  -Drat.skip=true \
  -Dmaven.test.failure.ignore=true \
  -DforkCount="${SLURM_CPUS_PER_TASK:-8}" \
  -DreuseForks=false \
  "${COMPILER_FLAG}" \
  test

_timing "mvn test (Chicory instrumented)" "$t0"

echo ">>> Chicory trace output directory:"
ls -la "$TRACE_OUT_DIR"

# NOTE: no combine/decompress step here on purpose. Daikon reads
# gzip-compressed dtrace files natively -- decompressing into a plain-text
# combined file was never necessary, and doing so for a large unlimited
# trace can require many times the original file's size. That exact step
# exhausted /scratch and killed the netty and hudi_full runs. The original
# Chicory-generated dtrace.gz in TRACE_OUT_DIR is the only file needed.

# Update "latest" only after successful completion, so a failed/partial run
# never becomes the pointer to look at.
ln -sfn "$TRACE_OUT_DIR" "${TRACE_BASE_DIR}/latest"

_timing "TOTAL (${PROJECT_NAME})" "$RUN_START"
echo "[TIMING] === ${PROJECT_NAME} chicory trace run finished $(date -Iseconds) ==="

echo
echo ">>> Original Chicory-generated dtrace.gz files preserved in:"
echo ">>> $TRACE_OUT_DIR"
echo ">>> Convenient newest-run path:"
echo ">>> ${TRACE_BASE_DIR}/latest"
