#!/bin/bash
# -----------------------------------------------------------------------------
# lib_io_examples_full_common.sh -- shared logic for extracting I/O examples
# directly from a project's ORIGINAL Chicory-produced dtrace.gz (full/unlimited
# --sample-start=0 runs), sourced by each project's
# submit_<project>_full_io_examples.sh.
#
# Unlike lib_io_examples_common.sh (which reads a combined plain-text
# "<project>.dtrace" file built by an old, now-removed combine step), this
# takes the real dtrace.gz path directly -- read-only, gzip-native, no
# decompression to disk, and the original file is never modified or deleted.
#
# IOExamplesExtractor streams the trace one blank-line-separated block at a
# time (see its "Fix OOM" commit) rather than materializing the whole file,
# so heap use no longer scales with trace size the way the old
# lib_io_examples_common.sh comment (tuned for a pre-fix 23GB trace) assumed.
# A modest, fixed heap here is intentional, not an oversight.
# -----------------------------------------------------------------------------

set -euo pipefail

# Args:
#   1  PROJECT_NAME   e.g. "netty-full" -- used only for output filenames/logs
#   2  DTRACE_PATH    absolute path to the ORIGINAL Chicory dtrace.gz
#   3  MODULE_SRC_PATH path to the module's src/main/java
#   4  OUT_DIR        where to write <PROJECT_NAME>_io_examples.json
#   5  JAVA_MODULE    cluster `module load` argument, e.g. "Java/17.0.15"
#   6  IO_EXAMPLES_JAR path to io-examples-tool.jar
run_io_examples_full() {
  local PROJECT_NAME="$1"
  local DTRACE_PATH="$2"
  local MODULE_SRC_PATH="$3"
  local OUT_DIR="$4"
  local JAVA_MODULE="$5"
  local IO_EXAMPLES_JAR="$6"

  module load "$JAVA_MODULE"

  local OUT_JSON="${OUT_DIR}/${PROJECT_NAME}_io_examples.json"

  echo "JAVA: $(which java)"
  echo "DTRACE (original, read-only): $DTRACE_PATH"
  echo "OUT:   $OUT_JSON"

  if [[ ! -s "$DTRACE_PATH" ]]; then
    echo "ERROR: $DTRACE_PATH missing or empty -- did the full chicory trace job finish successfully?" >&2
    exit 1
  fi

  local t0; t0=$(date +%s)
  java -Xmx48g -jar "$IO_EXAMPLES_JAR" \
    --dtrace "$DTRACE_PATH" \
    --src "$MODULE_SRC_PATH" \
    --out "$OUT_JSON"
  local t1; t1=$(date +%s)
  printf '[TIMING] %-28s %ds  (%s -> %s)\n' \
    "io-examples-tool extract (${PROJECT_NAME})" "$((t1 - t0))" \
    "$(date -d "@$t0" +%T)" "$(date -d "@$t1" +%T)"

  echo ">>> Wrote $OUT_JSON"
  echo ">>> Original dtrace.gz untouched: $(ls -lh "$DTRACE_PATH")"
}
