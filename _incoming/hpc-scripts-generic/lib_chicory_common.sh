#!/bin/bash
# -----------------------------------------------------------------------------
# lib_chicory_common.sh -- shared logic for running Daikon Chicory instrumentation
# against a Maven project's test suite, sourced by each project's
# submit_<project>_chicory_trace.sh.
#
# This generalizes the mechanism proven working on hudi:
#   - rsync a full local copy of the project (never touches the real checkout)
#   - inject the Chicory javaagent into Surefire's argLine
#   - bump the forked test JVM's heap
#   - recompile with -XDstringConcat=inline (works around a Chicory/BCEL
#     bytecode-compatibility bug with javac9+ invokedynamic string concat)
#   - combine the resulting dtrace.gz into one file
#
# UNLIKE hudi's original script, the argLine injection here does NOT depend on
# matching a specific literal string in the target pom.xml (hudi's own script
# matched "-XX:-OmitStackTraceInFastThrow</argLine>", which is hudi-specific
# text that won't exist in other projects' poms). Instead it parses the POM as
# XML, finds every <argLine> element anywhere in the document (top-level
# <properties>, per-profile properties, surefire plugin <configuration>, ...)
# and appends to each one, creating a new one under <properties> if none exist
# at all. hudi's own existing script is left untouched -- it already works,
# so there's no reason to risk regressing it just for uniformity.
# -----------------------------------------------------------------------------

set -euo pipefail

# Prints a "[TIMING] <label>: HH:MM:SS (Ns)" line to stdout, for measuring
# how long each phase of the pipeline actually takes per project. Usage:
#   local t0; t0=$(_now)
#   ... do the work ...
#   _timing "mvn test" "$t0"
_now() { date +%s; }
_timing() {
  local label="$1"
  local start="$2"
  local end
  end=$(date +%s)
  printf '[TIMING] %-28s %ds  (%s -> %s)\n' \
    "$label" "$((end - start))" \
    "$(date -d "@$start" +%T)" "$(date -d "@$end" +%T)"
}

# Detects a project module's dominant top-2-segment package prefix (e.g.
# "org.apache.dubbo") by sampling real `package` declarations under its
# src/main/java, rather than guessing from memory. Used to build
# --ppt-select-pattern / --boot-classes so Chicory only instruments the
# target project's own code.
detect_package_prefix() {
  local module_src="$1"
  # Run in a subshell with pipefail disabled: grep -m1 exits 1 (silently, no
  # stderr) for any file with no "package" line at all (e.g. module-info.java,
  # common in netty/dubbo's JPMS-aware modules), which makes xargs itself
  # exit 123 ("some invocations exited 1-125") -- and the "head -N" stages
  # here also SIGPIPE their upstream command once they've read enough lines.
  # Under the caller's `set -euo pipefail`, either one kills the whole script
  # instantly with NO printed error (a signal/nonzero-exit cascade prints
  # nothing on its own) -- that's what silently killed the dubbo and netty
  # trace jobs right after rsync. Only the final command's exit status
  # matters here, and it always exits 0 (even on zero matches), so no `|| true`
  # is needed once pipefail is off.
  ( set +o pipefail
    find "$module_src" -name "*.java" 2>/dev/null | head -1000 \
      | xargs -I{} sh -c 'head -20 "{}" 2>/dev/null | grep -m1 "^package "' \
      | sed -E 's/^package[[:space:]]+([a-zA-Z0-9_.]+);.*/\1/' \
      | awk -F. '{print $1"."$2}' \
      | sort | uniq -c | sort -rn | head -1 | awk '{print $2}'
  )
}

# Runs the full Chicory trace pipeline for one Maven project/module.
#
# Args (all required unless noted):
#   1  PROJECT_NAME      short name used in output file/dir naming, e.g. "dubbo"
#   2  PROJECT_DIR       path to the real checkout, e.g. .../promptstudy/dubbo
#   3  MODULE            Maven module path (-pl target), e.g. "dubbo-common"
#                         -- SAME module your run_daikonpp_<project>.sh already
#                         targets, so IO_EXAMPLES data lines up with the
#                         methods your own pipeline actually processes.
#   4  JAVA_MODULE       cluster `module load` argument, e.g. "Java/17.0.15"
#   5  DAIKON_JAR        path to daikon.jar
#   6  OUT_DIR           where to write hudi-chicory-out-style trace files +
#                         the combined .dtrace + the working rsync copy
#   7  PPT_OMIT_EXTRA    (may be empty) extra "|"-joined regex alternatives to
#                         append to --ppt-omit-pattern, for project-specific
#                         VerifyError-crashing classes discovered on a prior
#                         run (mirrors HoodieFieldOrder|HoodieTableType for
#                         hudi). Start empty; add classes here as they turn up.
#   8+ MVN_SKIP_FLAGS... additional -D flags for both the install and test
#                         mvn invocations (checkstyle/enforcer/rat/etc a given
#                         project's build needs skipped) -- pass the SAME
#                         flags your project's own compile/test scripts use.
run_chicory_trace() {
  local PROJECT_NAME="$1"
  local PROJECT_DIR="$2"
  local MODULE="$3"
  local JAVA_MODULE="$4"
  local DAIKON_JAR="$5"
  local OUT_DIR="$6"
  local PPT_OMIT_EXTRA="$7"
  shift 7
  local MVN_SKIP_FLAGS=("$@")

  module load "$JAVA_MODULE"

  local TRACE_OUT_DIR="${OUT_DIR}/${PROJECT_NAME}-chicory-out"
  local WORK_DIR="${OUT_DIR}/${PROJECT_NAME}-chicory"
  local COMBINED="${OUT_DIR}/${PROJECT_NAME}.dtrace"

  rm -rf "$TRACE_OUT_DIR"
  mkdir -p "$TRACE_OUT_DIR"

  echo "JAVA: $(which java)"
  echo "MVN: $(which mvn)"

  local RUN_START; RUN_START=$(_now)
  echo "[TIMING] === ${PROJECT_NAME} chicory trace run started $(date -Iseconds) ==="

  local t0
  t0=$(_now)
  mkdir -p "$WORK_DIR"
  rsync -a --delete --exclude='.git' --exclude='target' "${PROJECT_DIR}/" "${WORK_DIR}/"
  _timing "rsync copy" "$t0"

  local MODULE_SRC="${WORK_DIR}/${MODULE}/src/main/java"
  echo ">>> Detecting package prefix under $MODULE_SRC (samples up to 1000 files, can take a bit on a large module)..."
  t0=$(_now)
  local PKG_PREFIX
  PKG_PREFIX="$(detect_package_prefix "$MODULE_SRC")"
  _timing "detect package prefix" "$t0"
  if [[ -z "$PKG_PREFIX" ]]; then
    echo "ERROR: could not auto-detect a package prefix under $MODULE_SRC -- aborting rather than guessing." >&2
    exit 1
  fi
  echo ">>> Detected package prefix: $PKG_PREFIX"

  local PKG_PREFIX_ESCAPED="${PKG_PREFIX//./\\.}"
  local SELECT_PATTERN="^${PKG_PREFIX_ESCAPED}\..*"
  # Generic BCEL clinit-rewrite crash triggers common across Apache-ecosystem
  # projects: shaded/relocated protobuf (the same issue hit on hudi). Extend
  # with PPT_OMIT_EXTRA for project-specific classes discovered on a run.
  local OMIT_PATTERN="com\.google\.protobuf"
  if [[ -n "$PPT_OMIT_EXTRA" ]]; then
    OMIT_PATTERN="${OMIT_PATTERN}|${PPT_OMIT_EXTRA}"
  fi
  local BOOT_CLASSES_PATTERN="^(?!${PKG_PREFIX_ESCAPED}\.).*"

  local AGENT_FLAG="-javaagent:${DAIKON_JAR}=--output_dir=${TRACE_OUT_DIR} --ppt-select-pattern=${SELECT_PATTERN} --ppt-omit-pattern=${OMIT_PATTERN} --boot-classes=${BOOT_CLASSES_PATTERN} --sample-start=0"

  # Full-power sampling per explicit choice: --sample-start=0 records every
  # single call/return forever (Daikon/Chicory's own default), same as hudi's
  # very first, unlimited attempt that produced a 93GB trace and didn't
  # finish in 24h. Budget --mem/--time/heap in the submit script accordingly
  # -- there is no prior data point for how big this gets on THIS project.
  local FORK_XMX="-Xmx48g"

  echo ">>> Patching pom.xml argLine..."
  t0=$(_now)
  python3 - "$AGENT_FLAG" "$FORK_XMX" "${WORK_DIR}/pom.xml" <<'PYEOF'
import sys
import xml.etree.ElementTree as ET

agent_flag = sys.argv[1]
fork_xmx = sys.argv[2]
path = sys.argv[3]

NS = "http://maven.apache.org/POM/4.0.0"
ET.register_namespace('', NS)

tree = ET.parse(path)
root = tree.getroot()

addition = f' "{agent_flag}" {fork_xmx}'

argline_elems = root.findall(f'.//{{{NS}}}argLine')

if argline_elems:
    for el in argline_elems:
        el.text = (el.text or '') + addition
else:
    props = root.find(f'{{{NS}}}properties')
    if props is None:
        props = ET.SubElement(root, f'{{{NS}}}properties')
    new_el = ET.SubElement(props, f'{{{NS}}}argLine')
    new_el.text = addition.strip()
    argline_elems = [new_el]

tree.write(path, xml_declaration=True, encoding='UTF-8')
print(f"Patched {len(argline_elems)} argLine element(s) in {path} (real checkout untouched -- this is an rsync copy)")
PYEOF
  _timing "pom.xml argLine patch" "$t0"

  cd "$WORK_DIR"

  local COMPILER_FLAG="-Dmaven.compiler.compilerArgument=-XDstringConcat=inline"

  echo ">>> mvn install (-am, tests skipped) -- rebuilds all reactor deps with the compat compiler flag"
  t0=$(_now)
  mvn -q \
    -pl "$MODULE" -am \
    install \
    -DskipTests \
    "${MVN_SKIP_FLAGS[@]}" \
    "${COMPILER_FLAG}"
  _timing "mvn install (-am, no tests)" "$t0"

  echo ">>> mvn test (javaagent attached via patched argLine) -- this is the actual Chicory-instrumented run"
  t0=$(_now)
  mvn -q \
    -pl "$MODULE" \
    -DskipITs \
    -Duser.timezone=UTC \
    -Dmaven.test.failure.ignore=true \
    "${MVN_SKIP_FLAGS[@]}" \
    "${COMPILER_FLAG}" \
    test
  _timing "mvn test (Chicory instrumented)" "$t0"

  echo ">>> Chicory trace output directory:"
  ls -la "$TRACE_OUT_DIR"

  echo ">>> Combining dtrace files..."
  t0=$(_now)
  : > "$COMBINED"
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
  _timing "combine dtrace files" "$t0"

  echo ">>> Combined trace: $COMBINED"
  wc -l "$COMBINED"

  _timing "TOTAL (${PROJECT_NAME})" "$RUN_START"
  echo "[TIMING] === ${PROJECT_NAME} chicory trace run finished $(date -Iseconds) ==="
}
