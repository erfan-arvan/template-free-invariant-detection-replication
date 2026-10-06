#!/usr/bin/env bash
set -euo pipefail

format_duration() {
  local s="$1"
  printf '%02dh:%02dm:%02ds' $((s / 3600)) $(((s % 3600) / 60)) $((s % 60))
}

CONTEXT_CONFIG_NAMES=(
  local
  documented
  class_aware
  type_aware
  usage_aware
  example_driven
)
CONTEXT_CONFIG_VALUES=(
  "METHOD_BODY,SCOPE"
  "METHOD_BODY,SCOPE,METHOD_JAVADOC"
  "METHOD_BODY,SCOPE,CLASS_DOC"
  "METHOD_BODY,SCOPE,TYPE_DOC"
  "METHOD_BODY,SCOPE,CALL_SITE"
  "METHOD_BODY,SCOPE,IO_EXAMPLES"
)

PROMPT_STRATEGY="fewshot"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="${ROOT:-$SCRIPT_DIR}"
OCA_DIR="${OCA_DIR:-$ROOT/oca-artifact}"
HUDI_DIR="${HUDI_DIR:-$ROOT/hudi}"
SCRATCH_BASE="${SCRATCH_BASE:-$ROOT/scratch}/contextstudy"

mkdir -p "$SCRATCH_BASE"
export TMPDIR="${SCRATCH_BASE}/tmp"
export GRADLE_USER_HOME="${SCRATCH_BASE}/.gradle"
export DP_WORKDIR="${SCRATCH_BASE}/oca_work"
export DP_JAVA_VERSION=23

export DP_LLM_TOTAL_TIMEOUT_SEC=14400
export DP_LLM_REQ_TIMEOUT_SEC=30
export DP_OPENAI_MODEL=gpt-4.1-mini

mkdir -p "$TMPDIR" "$GRADLE_USER_HOME" "$DP_WORKDIR"
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.io.tmpdir=${TMPDIR}"

RESULTS_BASE="${RESULTS_BASE:-$ROOT/resultsOfContextStudy}"
mkdir -p "$RESULTS_BASE"

TOTAL_START_EPOCH=$(date +%s)
echo "CONTEXT STUDY STARTED (prompt strategy: $PROMPT_STRATEGY): $(date '+%Y-%m-%d %H:%M:%S %Z')"

echo ">>> Building Oca"
(cd "$OCA_DIR" && ./gradlew -q shadowJar -x test)
OCA_JAR="$OCA_DIR/build/libs/oca.jar"
[[ -f "$OCA_JAR" ]] || { echo "ERROR: Jar not found"; exit 1; }
export DP_OCA_JAR="$OCA_JAR"

export DP_PROMPT_STRATEGY="$PROMPT_STRATEGY"

BENCHMARKS=(
  "apollo:run_oca_apollo_biz.sh"
  "dubbo:run_oca_dubbo.sh"
  "hudi:run_oca_hudi_java_client.sh"
  "libgdx:run_oca_libgdx_core.sh"
  "netty:run_oca_netty.sh"
  "spring:run_oca_spring.sh"
)

for i in "${!CONTEXT_CONFIG_NAMES[@]}"; do
  CONFIG_NAME="${CONTEXT_CONFIG_NAMES[$i]}"
  CONFIG_START_EPOCH=$(date +%s)
  echo ">>> CONTEXT CONFIG: $CONFIG_NAME (DP_CONTEXTS=${CONTEXT_CONFIG_VALUES[$i]})"
  RESULTS_DIR="$RESULTS_BASE/$CONFIG_NAME"
  mkdir -p "$RESULTS_DIR"
  export DP_CONTEXTS="${CONTEXT_CONFIG_VALUES[$i]}"

  for entry in "${BENCHMARKS[@]}"; do
    NAME="${entry%%:*}"
    SCRIPT="${entry##*:}"
    START=$(date +%s)
    OUT_DIR="$RESULTS_DIR/$NAME"
    mkdir -p "$OUT_DIR"

    export DP_REGISTRY="$OUT_DIR/oca_registry.jsonl"
    export DP_OUTCOMES="$OUT_DIR/oca_outcomes.jsonl"
    export DP_REGISTRY_RESET=true

    (cd "$ROOT" && bash "$ROOT/$SCRIPT") >"$OUT_DIR/run.log" 2>&1

    echo ">>> Finished $NAME (context=$CONFIG_NAME) in $(format_duration $(($(date +%s) - START)))"
  done
  echo "DONE context config $CONFIG_NAME in $(format_duration $(($(date +%s) - CONFIG_START_EPOCH)))"
done

echo "ALL CONTEXT CONFIGS DONE in $(format_duration $(($(date +%s) - TOTAL_START_EPOCH)))"
