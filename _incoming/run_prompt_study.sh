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
# STRATEGIES
########################################
STRATEGIES=(
 #baseline
 #fewshot
 cot
# stepwise
# self_refine
# multi_sample
)

########################################
# PATHS
########################################
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="${ROOT:-$SCRIPT_DIR}"
DPP_DIR="${DPP_DIR:-$ROOT/daikonplusplus}"
HUDI_DIR="${HUDI_DIR:-$ROOT/hudi}"

########################################
# HPC scratch
########################################
ACCOUNT="${ACCOUNT:-mjk76}"
SCRATCH_ROOT="/scratch/${ACCOUNT}/${USER}"
SCRATCH_BASE="${SCRATCH_ROOT}/promptstudy"

mkdir -p "$SCRATCH_BASE"

export TMPDIR="${SCRATCH_BASE}/tmp"
export GRADLE_USER_HOME="${SCRATCH_BASE}/.gradle"
export DP_WORKDIR="${SCRATCH_BASE}/daikonpp_work"

export DP_JAVA_VERSION=23

########################################
# LLM TIMEOUT
########################################
export DP_LLM_TOTAL_TIMEOUT_SEC=14400
export DP_LLM_REQ_TIMEOUT_SEC=30
export DP_OPENAI_MODEL=gpt-4.1-mini
#export DP_DISABLE_REAL_LLM=1

mkdir -p "$TMPDIR" "$GRADLE_USER_HOME" "$DP_WORKDIR"

# Make JVM temp use scratch
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.io.tmpdir=${TMPDIR}"

########################################
# RESULTS
########################################
RESULTS_BASE="${RESULTS_BASE:-$ROOT/resultsOfPromptStudy}"
mkdir -p "$RESULTS_BASE"

########################################
# TOTAL START
########################################
TOTAL_START_EPOCH=$(date +%s)
TOTAL_START_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')

echo "######################################"
echo "PROMPT STUDY STARTED"
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

[[ -f "$DAIKONPP_JAR" ]] || { echo "ERROR: Jar not found"; exit 1; }
export DP_DAIKONPP_JAR="$DAIKONPP_JAR"

########################################
# CONTEXT CONFIG
########################################
export DP_CONTEXTS="METHOD_BODY,SCOPE"

########################################
# BENCHMARKS
########################################
########################################
# BENCHMARKS
########################################

BENCHMARKS=(
 # "apollo:run_daikonpp_apollo_biz.sh"
 # "dubbo:run_daikonpp_dubbo.sh"
  "netty:run_daikonpp_netty.sh"
 # "springReal:run_daikonpp_spring.sh"
)

########################################
# LOOP
########################################
for STRATEGY in "${STRATEGIES[@]}"; do
  STRATEGY_START_EPOCH=$(date +%s)
  STRATEGY_START_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')

  echo "======================================"
  echo ">>> STRATEGY: $STRATEGY"
  echo ">>> Start time: $STRATEGY_START_TIME"
  echo "======================================"

  RESULTS_DIR="$RESULTS_BASE/$STRATEGY"
  mkdir -p "$RESULTS_DIR"

  export DP_PROMPT_STRATEGY="$STRATEGY"

  for entry in "${BENCHMARKS[@]}"; do
    NAME="${entry%%:*}"
    SCRIPT="${entry##*:}"

    BENCHMARK_START_EPOCH=$(date +%s)
    BENCHMARK_START_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')

    echo "--------------------------------------"
    echo ">>> Running benchmark: $NAME"
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

    echo ">>> Finished $NAME (strategy=$STRATEGY)"
    echo ">>> Finish time: $BENCHMARK_END_TIME"
    echo ">>> Duration: $(format_duration "$BENCHMARK_DURATION")"
    echo ">>> Duration in seconds: $BENCHMARK_DURATION"
    echo ">>> Log: $LOG_FILE"
    echo ">>> Registry: $REG_FILE"

  done

  STRATEGY_END_EPOCH=$(date +%s)
  STRATEGY_END_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')
  STRATEGY_DURATION=$((STRATEGY_END_EPOCH - STRATEGY_START_EPOCH))

  echo "======================================"
  echo "DONE strategy: $STRATEGY"
  echo "Finish time: $STRATEGY_END_TIME"
  echo "Duration: $(format_duration "$STRATEGY_DURATION")"
  echo "Duration in seconds: $STRATEGY_DURATION"
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
echo "ALL STRATEGIES DONE"
echo "Start time: $TOTAL_START_TIME"
echo "Finish time: $TOTAL_END_TIME"
echo "Total duration: $(format_duration "$TOTAL_DURATION")"
echo "Total duration in seconds: $TOTAL_DURATION"
echo "######################################"
