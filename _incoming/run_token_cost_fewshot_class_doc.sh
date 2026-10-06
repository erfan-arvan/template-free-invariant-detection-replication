#!/usr/bin/env bash

set -euo pipefail

ROOT="/project/mjk76/ea442/promptstudy"
DPP_DIR="/scratch/mjk76/${USER}/daikonplusplus-token-cost"

CASSETTE_DIR="$ROOT/daikonplusplus/src/test/cassettes"

RESULTS_BASE="$ROOT/resultsOfTokenCostFewshotClassDoc"

ACCOUNT="${ACCOUNT:-mjk76}"
SCRATCH_ROOT="/scratch/${ACCOUNT}/${USER}"
SCRATCH_BASE="$SCRATCH_ROOT/token_cost_fewshot_class_doc"

mkdir -p \
  "$RESULTS_BASE" \
  "$SCRATCH_BASE/tmp" \
  "$SCRATCH_BASE/.gradle" \
  "$SCRATCH_BASE/daikonpp_work"

export TMPDIR="$SCRATCH_BASE/tmp"
export GRADLE_USER_HOME="$SCRATCH_BASE/.gradle"
export DP_WORKDIR="$SCRATCH_BASE/daikonpp_work"
export DP_JAVA_VERSION=23

export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.io.tmpdir=${TMPDIR}"

echo "======================================"
echo "TOKEN-COST DRY RUN"
echo "ROOT: $ROOT"
echo "DPP_DIR: $DPP_DIR"
echo "Cassette dir: $CASSETTE_DIR"
echo "Results: $RESULTS_BASE"
echo "======================================"

########################################
# VERIFY DRY-RUN IMPLEMENTATION
########################################

ACTUAL_COMMIT="$(git -C "$DPP_DIR" rev-parse --short=7 HEAD)"

if [[ "$ACTUAL_COMMIT" != "0ea6324" ]]; then
  echo "ERROR: wrong Daikon++ commit"
  echo "Expected: 0ea6324"
  echo "Actual:   $ACTUAL_COMMIT"
  exit 1
fi

echo "Daikon++ commit: $ACTUAL_COMMIT"

########################################
# BUILD FIRST
#
# IMPORTANT:
# DP_LLM_DRY_RUN must NOT be set yet.
########################################

unset DP_LLM_DRY_RUN || true

echo ">>> Building Daikon++"

pushd "$DPP_DIR" >/dev/null
./gradlew -q shadowJar
popd >/dev/null

DAIKONPP_JAR="$DPP_DIR/build/libs/daikonplusplus.jar"

[[ -f "$DAIKONPP_JAR" ]] || {
  echo "ERROR: jar not found: $DAIKONPP_JAR"
  exit 1
}

export DP_DAIKONPP_JAR="$DAIKONPP_JAR"

########################################
# DRY RUN
#
# Must be set AFTER building the jar.
########################################

export DP_LLM_DRY_RUN=true

export DP_LLM_PRICE_INPUT_PER_M=0.40
export DP_LLM_PRICE_OUTPUT_PER_M=1.60

########################################
# PROMPT-AFFECTING SETTINGS
########################################

export DP_OPENAI_MODEL=gpt-4.1-mini
export DP_PROMPT_STRATEGY=fewshot
export DP_CONTEXTS="METHOD_BODY,SCOPE,CLASS_DOC"

# Reuse the cassette corpus from the real experiments.
export DP_LLM_CASSETTES="$CASSETTE_DIR"

########################################
# SAME RELAXED-CONTEXT FLAGS
#
# These do not affect prompt token counts,
# but keep the configuration consistent.
########################################

export DP_QUALITY_FILTER_SELF_COMPARISON=false
export DP_QUALITY_FILTER_UNKNOWN_IDENTIFIER=false
export DP_QUALITY_FILTER_REQUIRE_RESULT_AT_EXIT=false
export DP_QUALITY_FILTER_REQUIRE_IN_SCOPE_NAME=false
export DP_QUALITY_FILTER_MAX_LENGTH=true

export DP_AUTOFILTER_MAX_MODIFY_PASSES=200
export DP_AUTOFILTER_MAX_EXTRA_PASSES=150
export DP_TEST_FILTER=false

########################################
# PROJECTS
#
# These are copies of the exact launchers
# used by the real context experiment.
########################################

BENCHMARKS=(
  "apollo:run_daikonpp_apollo_biz_tokenCost.sh"
  "dubbo:run_daikonpp_dubbo_tokenCost.sh"
  "netty:run_daikonpp_netty_tokenCost.sh"
  "hudi:run_daikonpp_hudi_java_client_tokenCost.sh"
  "spring:run_daikonpp_spring_tokenCost.sh"
  "libgdx:run_daikonpp_libgdx_core_tokenCost.sh"
)

echo
echo "Prompt strategy: $DP_PROMPT_STRATEGY"
echo "Contexts: $DP_CONTEXTS"
echo "Model: $DP_OPENAI_MODEL"
echo "Dry run: $DP_LLM_DRY_RUN"
echo "Projects: ${#BENCHMARKS[@]}"
echo

for entry in "${BENCHMARKS[@]}"; do

  NAME="${entry%%:*}"
  SCRIPT="${entry##*:}"

  OUT_DIR="$RESULTS_BASE/$NAME"
  mkdir -p "$OUT_DIR"

  LOG_FILE="$OUT_DIR/run.log"

  # New files. Never touch the real experiment registry/outcomes.
  export DP_REGISTRY="$OUT_DIR/daikonpp_registry.jsonl"
  export DP_OUTCOMES="$OUT_DIR/daikonpp_outcomes.jsonl"
  export DP_REGISTRY_RESET=true

  START="$(date +%s)"

  echo "======================================"
  echo ">>> Running: $NAME"
  echo ">>> Start: $(date)"
  echo ">>> Log: $LOG_FILE"
  echo "======================================"

  EXIT_STATUS=0

  (
    cd "$ROOT"
    bash "$ROOT/$SCRIPT"
  ) >"$LOG_FILE" 2>&1 || EXIT_STATUS=$?

  END="$(date +%s)"

  echo ">>> Finished: $NAME"
  echo ">>> Exit status: $EXIT_STATUS"
  echo ">>> Duration: $((END - START)) seconds"

  echo ">>> Dry-run summary:"
  grep -E 'DRY RUN|NOT recorded|recorded|token|Token|cost|Cost' \
    "$LOG_FILE" | tail -30 || true

  echo

done

echo "======================================"
echo "TOKEN-COST STUDY FINISHED"
echo "Finish: $(date)"
echo "Results: $RESULTS_BASE"
echo "======================================"
