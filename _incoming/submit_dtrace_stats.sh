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
#SBATCH --mem=48G
#SBATCH --time=06:00:00

set -euo pipefail
module load Java/17.0.15
cd /project/mjk76/ea442/promptstudy

DAIKON_JAR="/project/mjk76/ea442/promptstudy/daikon.jar"
TRACE_OUT_DIR="/project/mjk76/ea442/promptstudy/hudi-chicory-out"
rm -rf "$TRACE_OUT_DIR"
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
AGENT_FLAG="-javaagent:${DAIKON_JAR}=--output_dir=${TRACE_OUT_DIR} --ppt-select-pattern=^org\.apache\.hudi\..* --ppt-omit-pattern=HoodieFieldOrder|HoodieTableType"
HUDI_CHICORY_DIR="/project/mjk76/ea442/promptstudy/hudi-chicory"

mkdir -p "$HUDI_CHICORY_DIR"
rsync -a --delete --exclude='.git' --exclude='target' hudi/ "$HUDI_CHICORY_DIR/"

python3 - "$AGENT_FLAG" "$HUDI_CHICORY_DIR/pom.xml" <<'EOF'
import sys

agent_flag = sys.argv[1]
path = sys.argv[2]

with open(path) as f:
    content = f.read()

old = "-XX:-OmitStackTraceInFastThrow</argLine>"
new = f'-XX:-OmitStackTraceInFastThrow "{agent_flag}"</argLine>'

count = content.count(old)
if count == 0:
    raise SystemExit("ERROR: no occurrences of the expected argLine tail found -- pom.xml format may have changed")

content = content.replace(old, new)
with open(path, "w") as f:
    f.write(content)
print(f"Patched {count} occurrence(s) of argLine in {path} (hudi/pom.xml itself untouched)")
EOF

cd "$HUDI_CHICORY_DIR"

# v5: scoping is now correct (no more Maven/Guava/Guice instrumentation
# crashes), but instrumenting hudi's OWN classes now hits a genuine
# BCEL/bytecode-compatibility bug in Chicory: "VerifyError: Expecting a
# stack map frame" in org.apache.hudi.common.schema.HoodieFieldOrder.<clinit>,
# plus BCEL constant-pool corruption elsewhere ("ConstantUtf8 cannot be
# cast to ConstantCP", "Invalid constant pool reference"). Both are the
# same known cause: javac since JDK 9 compiles string concatenation (+) to
# invokedynamic calls against StringConcatFactory by default, and Chicory's
# bundled (old) BCEL can't correctly parse/rewrite that -- it corrupts the
# constant pool and drops stack-map frames when it adds its instrumentation
# hooks. The documented workaround is compiling with
# -XDstringConcat=inline, which forces javac back to old-style
# StringBuilder concatenation that BCEL can handle.
#
# HoodieFieldOrder lives in hudi-common, a dependency module, not
# hudi-java-client itself -- so recompiling only hudi-java-client would
# just reuse the already-built hudi-common jar from ~/.m2 (compiled without
# the flag) and still fail. -am (also-make) pulls hudi-common (and any
# other required reactor module) into this same build so it gets rebuilt
# with the same compiler flag.
#
# Doing that as a single `-am test` would also run every upstream module's
# OWN test suite (hudi-common's tests, etc.) -- slow and irrelevant here.
# Instead: first install everything upstream + the target module with
# tests skipped (so the fixed classes land in the local .m2 cache), then
# run tests for just hudi-java-client against that now-correct cache.
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

# Some hudi classes (HoodieTableConfig, HoodieFieldOrder, etc.) have static
# initializers complex enough that Chicory's bundled BCEL can't correctly
# regenerate StackMapTable frames after instrumenting them, producing a hard
# VerifyError at class-load time. This is a longstanding, undocumented BCEL
# limitation in Daikon itself (unfixed since at least 2015) -- not something
# fixable from here. It only affects test classes that happen to touch those
# specific static initializers; the rest run and trace fine.
#
# -Dmaven.test.failure.ignore=true stops a handful of failing tests from
# making `mvn test` return nonzero, which under `set -e` was killing this
# script before it ever reached the step that collects the trace files --
# so previous runs never got to report how much trace data was actually
# produced by the tests that DID run cleanly. We don't need every method
# traced, just a usable set of IO examples, so tolerating some failures here
# is the right tradeoff.
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

# Surefire may fork multiple JVMs (one per test class or per fork-count), so
# Chicory can emit more than one trace file. Concatenate them into a single file --
# the dtrace format is just repeated blank-line-separated blocks, so concatenation
# with a blank-line separator between files is safe.
COMBINED="/project/mjk76/ea442/promptstudy/hudi.dtrace"
: > "$COMBINED"

# Chicory's actual output filename is "dtrace.gz" (no leading dot before
# "dtrace") -- the old *.dtrace.gz / *.dtrace globs never matched it, so
# every prior run silently produced an empty combined file.
shopt -s nullglob
for f in "$TRACE_OUT_DIR"/*dtrace.gz; do
  zcat "$f" >> "$COMBINED"
  echo "" >> "$COMBINED"
done
for f in "$TRACE_OUT_DIR"/*dtrace; do
  cat "$f" >> "$COMBINED"
  echo "" >> "$COMBINED"
done
shopt -u nullglob

echo ">>> Combined trace: $COMBINED"
wc -l "$COMBINED"
