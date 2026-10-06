#!/usr/bin/env bash

set -euo pipefail

########################################
# HELPERS
########################################

format_duration() {
  local total_seconds="$1"

  printf '%02dh:%02dm:%02ds' \
    $((total_seconds / 3600)) \
    $(((total_seconds % 3600) / 60)) \
    $((total_seconds % 60))
}

########################################
# CONTEXT CONFIGS
#
# Prompt strategy is fixed to "fewshot";
# only the context kinds vary.
########################################

CONTEXT_CONFIG_NAMES=(
  io_examples
)

CONTEXT_CONFIG_VALUES=(
  "METHOD_BODY,SCOPE,IO_EXAMPLES"
)

########################################
# FIXED PROMPT STRATEGY
########################################

PROMPT_STRATEGY="fewshot"

########################################
# PATHS
########################################

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

ROOT="${ROOT:-$SCRIPT_DIR}"

DPP_DIR="${DPP_DIR:-$ROOT/daikonplusplus}"
HUDI_DIR="${HUDI_DIR:-$ROOT/hudi}"

########################################
# HPC SCRATCH
#
# Separate from the previous context study
# so this experiment does not interfere
# with existing runs/work directories.
########################################

ACCOUNT="${ACCOUNT:-mjk76}"

SCRATCH_ROOT="/scratch/${ACCOUNT}/${USER}"
SCRATCH_BASE="${SCRATCH_ROOT}/contextstudy_fewshot"

mkdir -p "$SCRATCH_BASE"

export TMPDIR="${SCRATCH_BASE}/tmp"
export GRADLE_USER_HOME="${SCRATCH_BASE}/.gradle"
export DP_WORKDIR="${SCRATCH_BASE}/daikonpp_work"

export DP_JAVA_VERSION=23

########################################
# LLM
########################################

export DP_LLM_TOTAL_TIMEOUT_SEC=14400
export DP_LLM_REQ_TIMEOUT_SEC=30
export DP_OPENAI_MODEL=gpt-4.1-mini

# export DP_DISABLE_REAL_LLM=1

mkdir -p "$TMPDIR" "$GRADLE_USER_HOME" "$DP_WORKDIR"

# Make JVM temp use scratch
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.io.tmpdir=${TMPDIR}"

########################################
# RESULTS
#
# IMPORTANT:
# Separate from resultsOfContextStudy
########################################

RESULTS_BASE="${RESULTS_BASE:-$ROOT/resultsOfContextStudyFewshot}"

mkdir -p "$RESULTS_BASE"

########################################
# TOTAL START
########################################

TOTAL_START_EPOCH=$(date +%s)
TOTAL_START_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')

echo "######################################"
echo "FEWSHOT CONTEXT STUDY STARTED"
echo "Prompt strategy (fixed): $PROMPT_STRATEGY"
echo "Results base: $RESULTS_BASE"
echo "Start time: $TOTAL_START_TIME"
echo "######################################"

########################################
# BUILD DAIKON++ ONCE
########################################

echo ">>> Building Daikon++ (once)"

pushd "$DPP_DIR" >/dev/null

./gradlew -q shadowJar

DAIKONPP_JAR="$DPP_DIR/build/libs/daikonplusplus.jar"

popd >/dev/null

[[ -f "$DAIKONPP_JAR" ]] || {
  echo "ERROR: Jar not found"
  exit 1
}

export DP_DAIKONPP_JAR="$DAIKONPP_JAR"

########################################
# PROMPT STRATEGY (fixed)
########################################

export DP_PROMPT_STRATEGY="$PROMPT_STRATEGY"

########################################
# BENCHMARKS
########################################

BENCHMARKS=(
  "apollo:run_daikonpp_apollo_biz.sh"
  "dubbo:run_daikonpp_dubbo.sh"
  # netty excluded: its s5 chicory trace/io-examples are still being (re)generated
  "hudi:run_daikonpp_hudi_java_client.sh"
  "spring:run_daikonpp_spring.sh"
  "libgdx:run_daikonpp_libgdx_core.sh"
)

########################################
# LOOP
########################################

for i in "${!CONTEXT_CONFIG_NAMES[@]}"; do

  CONFIG_NAME="${CONTEXT_CONFIG_NAMES[$i]}"
  CONTEXTS="${CONTEXT_CONFIG_VALUES[$i]}"

  CONFIG_START_EPOCH=$(date +%s)
  CONFIG_START_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')

  echo "======================================"
  echo ">>> CONTEXT CONFIG: $CONFIG_NAME"
  echo ">>> Prompt strategy: $PROMPT_STRATEGY"
  echo ">>> DP_CONTEXTS: $CONTEXTS"
  echo ">>> Start time: $CONFIG_START_TIME"
  echo "======================================"

  RESULTS_DIR="$RESULTS_BASE/$CONFIG_NAME"

  mkdir -p "$RESULTS_DIR"

  export DP_CONTEXTS="$CONTEXTS"

  for entry in "${BENCHMARKS[@]}"; do

    NAME="${entry%%:*}"
    SCRIPT="${entry##*:}"

    BENCHMARK_START_EPOCH=$(date +%s)
    BENCHMARK_START_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')

    echo "--------------------------------------"
    echo ">>> Running benchmark: $NAME"
    echo ">>> Context config: $CONFIG_NAME"
    echo ">>> Prompt strategy: $PROMPT_STRATEGY"
    echo ">>> Start time: $BENCHMARK_START_TIME"
    echo "--------------------------------------"

    OUT_DIR="$RESULTS_DIR/$NAME"

    mkdir -p "$OUT_DIR"

    LOG_FILE="$OUT_DIR/run.log"
    REG_FILE="$OUT_DIR/daikonpp_registry.jsonl"

    export DP_REGISTRY="$REG_FILE"
    export DP_OUTCOMES="$OUT_DIR/daikonpp_outcomes.jsonl"
    export DP_REGISTRY_RESET=true

    (
      cd "$ROOT"
      bash "$ROOT/$SCRIPT"
    ) >"$LOG_FILE" 2>&1

    BENCHMARK_END_EPOCH=$(date +%s)
    BENCHMARK_END_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')
    BENCHMARK_DURATION=$((BENCHMARK_END_EPOCH - BENCHMARK_START_EPOCH))

    echo ">>> Finished $NAME (context_config=$CONFIG_NAME, prompt=$PROMPT_STRATEGY)"
    echo ">>> Finish time: $BENCHMARK_END_TIME"
    echo ">>> Duration: $(format_duration "$BENCHMARK_DURATION")"
    echo ">>> Duration in seconds: $BENCHMARK_DURATION"
    echo ">>> Log: $LOG_FILE"
    echo ">>> Registry: $REG_FILE"

  done

  CONFIG_END_EPOCH=$(date +%s)
  CONFIG_END_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')
  CONFIG_DURATION=$((CONFIG_END_EPOCH - CONFIG_START_EPOCH))

  echo "======================================"
  echo "DONE context config: $CONFIG_NAME"
  echo "Prompt strategy: $PROMPT_STRATEGY"
  echo "Finish time: $CONFIG_END_TIME"
  echo "Duration: $(format_duration "$CONFIG_DURATION")"
  echo "Duration in seconds: $CONFIG_DURATION"
  echo "Results in: $RESULTS_DIR"
  echo "======================================"

done

########################################
# TOTAL END
########################################

TOTAL_END_EPOCH=$(date +%s)
TOTAL_END_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')
TOTAL_DURATION=$((TOTAL_END_EPOCH - TOTAL_START_EPOCH))

echo "######################################"
echo "ALL FEWSHOT CONTEXT CONFIGS DONE"
echo "Prompt strategy: $PROMPT_STRATEGY"
echo "Start time: $TOTAL_START_TIME"
echo "Finish time: $TOTAL_END_TIME"
echo "Total duration: $(format_duration "$TOTAL_DURATION")"
echo "Total duration in seconds: $TOTAL_DURATION"
echo "Results base: $RESULTS_BASE"
echo "######################################"
