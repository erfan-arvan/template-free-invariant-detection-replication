#!/bin/bash

# -----------------------------------------------------------------------------
# lib_chicory_common_s5.sh -- IDENTICAL to lib_chicory_common.sh except for
# one line: --sample-start=5 instead of --sample-start=0. Kept as a separate
# copy (not a parameterized flag) so the original unlimited-sampling
# lib/scripts/running jobs are never touched.
# -----------------------------------------------------------------------------

set -euo pipefail


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


detect_package_prefix() {
    local module_src="$1"

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


run_chicory_trace() {

    local PROJECT_NAME="$1"
    local PROJECT_DIR="$2"
    local MODULE="$3"
    local JAVA_MODULE="$4"
    local DAIKON_JAR="$5"
    local OUT_DIR="$6"
    local PPT_OMIT_EXTRA="$7"

    shift 7


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


    module load "$JAVA_MODULE"


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


    local PKG_PREFIX_ESCAPED
    PKG_PREFIX_ESCAPED="${PKG_PREFIX//./\\.}"

    local SELECT_PATTERN
    SELECT_PATTERN="^${PKG_PREFIX_ESCAPED}\..*"

    local OMIT_PATTERN
    OMIT_PATTERN="com\.google\.protobuf"

    if [[ -n "$PPT_OMIT_EXTRA" ]]; then
        OMIT_PATTERN="${OMIT_PATTERN}|${PPT_OMIT_EXTRA}"
    fi

    local BOOT_CLASSES_PATTERN
    BOOT_CLASSES_PATTERN="^(?!${PKG_PREFIX_ESCAPED}\.).*"

    echo
    echo ">>> Chicory configuration:"
    echo ">>> package prefix:     $PKG_PREFIX"
    echo ">>> select pattern:     $SELECT_PATTERN"
    echo ">>> omit pattern:       $OMIT_PATTERN"
    echo ">>> boot classes:       $BOOT_CLASSES_PATTERN"


    local AGENT_FLAG

    AGENT_FLAG="-javaagent:${DAIKON_JAR}=\
--output_dir=${TRACE_OUT_DIR} \
--ppt-select-pattern=${SELECT_PATTERN} \
--ppt-omit-pattern=${OMIT_PATTERN} \
--boot-classes=${BOOT_CLASSES_PATTERN} \
--sample-start=5"

    local FORK_XMX="-Xmx48g"


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


    cd "$WORK_DIR"

    local COMPILER_FLAG
    COMPILER_FLAG="-Dmaven.compiler.compilerArgument=-XDstringConcat=inline"


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


    ln -sfn "$TRACE_OUT_DIR" "${TRACE_BASE_DIR}/latest"

    echo
    echo ">>> Latest-run symlink:"
    ls -ld "${TRACE_BASE_DIR}/latest"


    echo
    echo ">>> Final contents of this run:"
    ls -lah "$TRACE_OUT_DIR"

    echo
    echo ">>> Original Chicory-generated files are preserved in:"
    echo ">>> $TRACE_OUT_DIR"

    echo
    echo ">>> Convenient newest-run path:"
    echo ">>> ${TRACE_BASE_DIR}/latest"


    _timing "TOTAL (${PROJECT_NAME})" "$RUN_START"

    echo
    echo "[TIMING] === ${PROJECT_NAME} chicory trace run finished $(date -Iseconds) ==="
}
