#!/bin/bash

# -----------------------------------------------------------------------------
# lib_chicory_common.sh -- shared logic for running Daikon Chicory instrumentation
# against a Maven project's test suite, sourced by each project's
# submit_<project>_chicory_trace.sh.
#
# Main behavior:
#   - rsync a full local copy of the project (never touches the real checkout)
#   - inject the Chicory javaagent into Surefire's argLine
#   - bump the forked test JVM's heap
#   - recompile with -XDstringConcat=inline
#   - run Maven tests with Chicory attached
#   - preserve ALL original Chicory-generated dtrace files
#   - place every SLURM run in its own output directory
#
# Optional environment variable:
#
#   CHICORY_PKG_PREFIX
#
# If set, this is used directly instead of auto-detecting the package prefix.
# This is recommended for projects such as Dubbo:
#
#   export CHICORY_PKG_PREFIX="org.apache.dubbo"
#
# If CHICORY_PKG_PREFIX is not set, the generic auto-detection logic is used.
# -----------------------------------------------------------------------------

set -euo pipefail


# -----------------------------------------------------------------------------
# Timing helpers
# -----------------------------------------------------------------------------

_now() {
    date +%s
}

_timing() {
    local label="$1"
    local start="$2"
    local end

    end=$(date +%s)

    printf '[TIMING] %-28s %ds  (%s -> %s)\n' \
        "$label" \
        "$((end - start))" \
        "$(date -d "@$start" +%T)" \
        "$(date -d "@$end" +%T)"

    # Also append to a single shared log across all projects/runs so total
    # runtimes can be compared without digging through each job's .out file.
    # PROJECT_NAME/OUT_DIR are picked up from the caller (run_chicory_trace)
    # via bash's dynamic scoping -- this function is only ever called from
    # inside that function's call stack.
    if [[ -n "${OUT_DIR:-}" ]]; then
        printf '%s\t%s\t%s\t%ds\t%s\t%s\t%s\n' \
            "$(date -Iseconds)" \
            "${PROJECT_NAME:-unknown}" \
            "${SLURM_JOB_ID:-nojob}" \
            "$((end - start))" \
            "$label" \
            "$(date -d "@$start" -Iseconds)" \
            "$(date -d "@$end" -Iseconds)" \
            >> "${OUT_DIR}/chicory_timing.log"
    fi
}


# -----------------------------------------------------------------------------
# Generic package-prefix detection fallback
#
# NOTE:
# This detector keeps the original behavior of taking the first two package
# components. That is NOT sufficient for every project.
#
# For projects where the desired namespace is known, set:
#
#   CHICORY_PKG_PREFIX
#
# in the project's submit script.
#
# Example for Dubbo:
#
#   export CHICORY_PKG_PREFIX="org.apache.dubbo"
# -----------------------------------------------------------------------------

detect_package_prefix() {
    local module_src="$1"

    # Disable pipefail inside this subshell because:
    #
    #   - grep -m1 may return 1 for files with no package declaration
    #   - head may cause SIGPIPE upstream
    #   - xargs can propagate those non-zero statuses
    #
    # None of those should abort the whole trace job.
    (
        set +o pipefail

        find "$module_src" -name "*.java" 2>/dev/null \
            | head -1000 \
            | xargs -I{} sh -c \
                'head -20 "{}" 2>/dev/null | grep -m1 "^package "' \
            | sed -E \
                's/^package[[:space:]]+([a-zA-Z0-9_.]+);.*/\1/' \
            | awk -F. \
                '{print $1"."$2}' \
            | sort \
            | uniq -c \
            | sort -rn \
            | head -1 \
            | awk '{print $2}'
    )
}


# -----------------------------------------------------------------------------
# Runs the full Chicory trace pipeline for one Maven project/module.
#
# Arguments:
#
#   1  PROJECT_NAME
#      Short name used in output naming, e.g. "dubbo"
#
#   2  PROJECT_DIR
#      Path to real checkout
#
#   3  MODULE
#      Maven module path, e.g. "dubbo-common"
#
#   4  JAVA_MODULE
#      Cluster module-load argument, e.g. "Java/17.0.15"
#
#   5  DAIKON_JAR
#      Path to daikon.jar
#
#   6  OUT_DIR
#      Base output directory
#
#   7  PPT_OMIT_EXTRA
#      Optional additional regex alternatives for --ppt-omit-pattern
#
#   8+ INSTALL_SKIP_FLAGS...
#      "---TEST---"
#      TEST_SKIP_FLAGS...
#
# Important:
#
# Compile/install flags and test flags remain separate.
# In particular, -Dmaven.test.skip=true must NOT leak into the actual
# test invocation.
# -----------------------------------------------------------------------------

run_chicory_trace() {

    local PROJECT_NAME="$1"
    local PROJECT_DIR="$2"
    local MODULE="$3"
    local JAVA_MODULE="$4"
    local DAIKON_JAR="$5"
    local OUT_DIR="$6"
    local PPT_OMIT_EXTRA="$7"

    shift 7


    # -------------------------------------------------------------------------
    # Split compile flags and test flags
    # -------------------------------------------------------------------------

    local INSTALL_SKIP_FLAGS=()
    local TEST_SKIP_FLAGS=()
    local _in_test_flags=false

    for arg in "$@"; do

        if [[ "$arg" == "---TEST---" ]]; then
            _in_test_flags=true
            continue
        fi

        if [[ "$_in_test_flags" == true ]]; then
            TEST_SKIP_FLAGS+=("$arg")
        else
            INSTALL_SKIP_FLAGS+=("$arg")
        fi

    done


    # -------------------------------------------------------------------------
    # Java
    # -------------------------------------------------------------------------

    module load "$JAVA_MODULE"


    # -------------------------------------------------------------------------
    # Output paths
    #
    # Each run gets a unique permanent directory.
    #
    # Example:
    #
    #   dubbo-chicory-out/
    #       1219488/
    #       1220001/
    #       latest -> .../1220001
    #
    # Under SLURM, RUN_ID is the job ID.
    # Outside SLURM, use a timestamp.
    # -------------------------------------------------------------------------

    local RUN_ID
    RUN_ID="${SLURM_JOB_ID:-$(date +%Y%m%d-%H%M%S)}"

    local TRACE_BASE_DIR
    TRACE_BASE_DIR="${OUT_DIR}/${PROJECT_NAME}-chicory-out"

    local TRACE_OUT_DIR
    TRACE_OUT_DIR="${TRACE_BASE_DIR}/${RUN_ID}"

    local WORK_DIR
    WORK_DIR="${OUT_DIR}/${PROJECT_NAME}-chicory"

    mkdir -p "$TRACE_BASE_DIR"
    mkdir -p "$TRACE_OUT_DIR"


    echo "============================================================"
    echo "${PROJECT_NAME} Chicory trace"
    echo "============================================================"
    echo "RUN ID:             $RUN_ID"
    echo "JAVA:               $(which java)"
    echo "MVN:                $(which mvn)"
    echo "PROJECT:            $PROJECT_DIR"
    echo "MODULE:             $MODULE"
    echo "WORK DIR:           $WORK_DIR"
    echo "TRACE BASE DIR:     $TRACE_BASE_DIR"
    echo "TRACE OUTPUT DIR:   $TRACE_OUT_DIR"
    echo "============================================================"


    local RUN_START
    RUN_START=$(_now)

    echo
    echo "[TIMING] === ${PROJECT_NAME} chicory trace run started $(date -Iseconds) ==="


    # -------------------------------------------------------------------------
    # Copy project into working directory
    # -------------------------------------------------------------------------

    local t0
    t0=$(_now)

    mkdir -p "$WORK_DIR"

    rsync -a \
        --delete \
        --exclude='.git' \
        --exclude='target' \
        "${PROJECT_DIR}/" \
        "${WORK_DIR}/"

    _timing "rsync copy" "$t0"


    # -------------------------------------------------------------------------
    # Determine package prefix
    # -------------------------------------------------------------------------

    local MODULE_SRC
    MODULE_SRC="${WORK_DIR}/${MODULE}/src/main/java"

    local PKG_PREFIX

    if [[ -n "${CHICORY_PKG_PREFIX:-}" ]]; then

        PKG_PREFIX="$CHICORY_PKG_PREFIX"

        echo
        echo ">>> Using explicitly configured package prefix:"
        echo ">>> $PKG_PREFIX"

    else

        echo
        echo ">>> No CHICORY_PKG_PREFIX supplied."
        echo ">>> Auto-detecting package prefix under:"
        echo ">>> $MODULE_SRC"

        t0=$(_now)

        PKG_PREFIX="$(detect_package_prefix "$MODULE_SRC")"

        _timing "detect package prefix" "$t0"

        if [[ -z "$PKG_PREFIX" ]]; then
            echo \
                "ERROR: could not auto-detect a package prefix under $MODULE_SRC" \
                >&2
            exit 1
        fi

        echo ">>> Auto-detected package prefix: $PKG_PREFIX"

    fi


    # -------------------------------------------------------------------------
    # Build Chicory filters
    # -------------------------------------------------------------------------

    local PKG_PREFIX_ESCAPED
    PKG_PREFIX_ESCAPED="${PKG_PREFIX//./\\.}"

    local SELECT_PATTERN
    SELECT_PATTERN="^${PKG_PREFIX_ESCAPED}\..*"

    # Generic BCEL/protobuf exclusion.
    local OMIT_PATTERN
    OMIT_PATTERN="com\.google\.protobuf"

    if [[ -n "$PPT_OMIT_EXTRA" ]]; then
        OMIT_PATTERN="${OMIT_PATTERN}|${PPT_OMIT_EXTRA}"
    fi

    # Treat everything outside the selected project namespace as boot classes.
    local BOOT_CLASSES_PATTERN
    BOOT_CLASSES_PATTERN="^(?!${PKG_PREFIX_ESCAPED}\.).*"

    echo
    echo ">>> Chicory configuration:"
    echo ">>> package prefix:     $PKG_PREFIX"
    echo ">>> select pattern:     $SELECT_PATTERN"
    echo ">>> omit pattern:       $OMIT_PATTERN"
    echo ">>> boot classes:       $BOOT_CLASSES_PATTERN"


    # -------------------------------------------------------------------------
    # Chicory Java agent
    # -------------------------------------------------------------------------

    local AGENT_FLAG

    AGENT_FLAG="-javaagent:${DAIKON_JAR}=\
--output_dir=${TRACE_OUT_DIR} \
--ppt-select-pattern=${SELECT_PATTERN} \
--ppt-omit-pattern=${OMIT_PATTERN} \
--boot-classes=${BOOT_CLASSES_PATTERN} \
--sample-start=0"

    # Full tracing.
    #
    # --sample-start=0 records every call/return rather than using sampling.
    # This may produce very large traces.
    local FORK_XMX="-Xmx48g"


    # -------------------------------------------------------------------------
    # Patch copied root pom.xml
    # -------------------------------------------------------------------------

    echo
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

tree.write(
    path,
    xml_declaration=True,
    encoding='UTF-8'
)

print(
    f"Patched {len(argline_elems)} argLine element(s) "
    f"in {path} "
    f"(real checkout untouched -- this is an rsync copy)"
)
PYEOF

    _timing "pom.xml argLine patch" "$t0"


    # -------------------------------------------------------------------------
    # Maven build
    # -------------------------------------------------------------------------

    cd "$WORK_DIR"

    local COMPILER_FLAG
    COMPILER_FLAG="-Dmaven.compiler.compilerArgument=-XDstringConcat=inline"


    # -------------------------------------------------------------------------
    # Compile
    # -------------------------------------------------------------------------

    echo
    echo ">>> mvn compile (-am, warms build with compatibility compiler flag)"

    t0=$(_now)

    mvn \
        -pl "$MODULE" \
        -am \
        compile \
        -DskipTests \
        "${INSTALL_SKIP_FLAGS[@]}" \
        "${COMPILER_FLAG}"

    _timing "mvn compile (-am, no tests)" "$t0"


    # -------------------------------------------------------------------------
    # Actual Chicory-instrumented test run
    # -------------------------------------------------------------------------

    echo
    echo ">>> mvn test"
    echo ">>> Chicory javaagent is attached through patched argLine"

    t0=$(_now)

    mvn \
        -pl "$MODULE" \
        -am \
        -DskipITs \
        -Duser.timezone=UTC \
        -Dmaven.test.failure.ignore=true \
        "${TEST_SKIP_FLAGS[@]}" \
        "${COMPILER_FLAG}" \
        test

    _timing "mvn test (Chicory instrumented)" "$t0"


    # -------------------------------------------------------------------------
    # Show original files produced by Chicory
    #
    # IMPORTANT:
    # These files are preserved exactly as generated.
    # -------------------------------------------------------------------------

    echo
    echo "============================================================"
    echo ">>> Chicory trace output directory:"
    echo "$TRACE_OUT_DIR"
    echo "============================================================"

    echo
    echo ">>> Complete directory listing:"
    ls -lah "$TRACE_OUT_DIR"

    echo
    echo ">>> Individual Chicory-generated trace files:"

    find "$TRACE_OUT_DIR" \
        -maxdepth 1 \
        -type f \
        \( -name 'dtrace' -o -name 'dtrace.gz' -o -name '*.dtrace' -o -name '*.dtrace.gz' \) \
        -exec ls -lh {} \;


    # -------------------------------------------------------------------------
    # Count original trace files
    # -------------------------------------------------------------------------

    local ORIGINAL_TRACE_COUNT

    ORIGINAL_TRACE_COUNT="$(
        find "$TRACE_OUT_DIR" \
            -maxdepth 1 \
            -type f \
            \( -name 'dtrace' -o -name 'dtrace.gz' -o -name '*.dtrace' -o -name '*.dtrace.gz' \) \
            | wc -l
    )"

    echo
    echo ">>> Number of original Chicory trace files: $ORIGINAL_TRACE_COUNT"

    if [[ "$ORIGINAL_TRACE_COUNT" -eq 0 ]]; then
        echo "ERROR: Chicory produced no dtrace files." >&2
        exit 1
    fi


    # -------------------------------------------------------------------------
    # NOTE: no combine/decompress step here on purpose.
    #
    # Daikon reads gzip-compressed dtrace files natively -- decompressing
    # into a plain-text combined file was never necessary, and doing so for
    # a large unlimited trace can require many times the original file's
    # size (text decompresses to several times the gzip size). That exact
    # step exhausted /scratch and killed both the netty and hudi_full runs.
    # The original Chicory-generated dtrace.gz in TRACE_OUT_DIR is the only
    # file this pipeline needs; keep it exactly as produced.
    # -------------------------------------------------------------------------


    # -------------------------------------------------------------------------
    # Update "latest" only after successful completion
    # -------------------------------------------------------------------------

    ln -sfn "$TRACE_OUT_DIR" "${TRACE_BASE_DIR}/latest"

    echo
    echo ">>> Latest-run symlink:"
    ls -ld "${TRACE_BASE_DIR}/latest"


    # -------------------------------------------------------------------------
    # Final directory summary
    # -------------------------------------------------------------------------

    echo
    echo ">>> Final contents of this run:"
    ls -lah "$TRACE_OUT_DIR"

    echo
    echo ">>> Original Chicory-generated files are preserved in:"
    echo ">>> $TRACE_OUT_DIR"

    echo
    echo ">>> Convenient newest-run path:"
    echo ">>> ${TRACE_BASE_DIR}/latest"


    # -------------------------------------------------------------------------
    # Timing
    # -------------------------------------------------------------------------

    _timing "TOTAL (${PROJECT_NAME})" "$RUN_START"

    echo
    echo "[TIMING] === ${PROJECT_NAME} chicory trace run finished $(date -Iseconds) ==="
}
