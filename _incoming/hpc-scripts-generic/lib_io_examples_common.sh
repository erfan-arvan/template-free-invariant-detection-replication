#!/bin/bash
# -----------------------------------------------------------------------------
# lib_io_examples_common.sh -- shared logic for extracting I/O examples from a
# combined .dtrace via io-examples-tool.jar, sourced by each project's
# submit_<project>_io_examples.sh.
#
# Sized generously for --sample-start=0 (unlimited) traces: hudi's tuned,
# CAPPED (--sample-start=5) trace was 23.27GB/557.5M lines and needed
# -Xmx140g to extract without OOM. An unlimited trace on any of these
# projects could be substantially bigger than that -- there's no prior data
# point, so this heap/mem/time budget is a generous starting guess, not a
# proven number. If it OOMs, the real fix is making the tool stream the file
# instead of loading it whole (see IOExamplesExtractor.readBlocks), not an
# even bigger heap.
# -----------------------------------------------------------------------------

set -euo pipefail

# Args:
#   1  PROJECT_NAME   e.g. "dubbo" -- expects <OUT_DIR>/<PROJECT_NAME>.dtrace
#                      to already exist (written by run_chicory_trace)
#   2  MODULE_SRC_PATH path to the module's src/main/java, e.g.
#                      "<PROJECT_DIR>/dubbo-common/src/main/java"
#   3  OUT_DIR        same directory run_chicory_trace wrote into
#   4  JAVA_MODULE    cluster `module load` argument, e.g. "Java/17.0.15"
#   5  IO_EXAMPLES_JAR path to io-examples-tool.jar
run_io_examples() {
  local PROJECT_NAME="$1"
  local MODULE_SRC_PATH="$2"
  local OUT_DIR="$3"
  local JAVA_MODULE="$4"
  local IO_EXAMPLES_JAR="$5"

  module load "$JAVA_MODULE"

  local DTRACE="${OUT_DIR}/${PROJECT_NAME}.dtrace"
  local OUT_JSON="${OUT_DIR}/${PROJECT_NAME}_io_examples.json"

  echo "JAVA: $(which java)"

  if [[ ! -s "$DTRACE" ]]; then
    echo "ERROR: $DTRACE missing or empty -- did the chicory trace job finish successfully?" >&2
    exit 1
  fi

  local t0; t0=$(date +%s)
  java -Xmx260g -jar "$IO_EXAMPLES_JAR" \
    --dtrace "$DTRACE" \
    --src "$MODULE_SRC_PATH" \
    --out "$OUT_JSON"
  local t1; t1=$(date +%s)
  printf '[TIMING] %-28s %ds  (%s -> %s)\n' \
    "io-examples-tool extract (${PROJECT_NAME})" "$((t1 - t0))" \
    "$(date -d "@$t0" +%T)" "$(date -d "@$t1" +%T)"

  echo ">>> Wrote $OUT_JSON"
  wc -l "$OUT_JSON"
}
