#!/usr/bin/env bash
# RQ6 timing/disk data generator: Daikon side (Chicory + daikon.Daikon) and
# Oca (daikonplusplus) side, for the 6 benchmark projects (apollo, dubbo,
# hudi, libgdx, netty, spring).
#
# Run from anywhere on login02 (paths below are absolute):
#   bash rq6_full_report.sh
#
# Pure bash + sacct/du/grep -- no python, no heavy compute, safe to run
# directly on the login node.

set -u
OUT="rq6_results_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "$OUT") 2>&1

sec_from_hms() {
  local t="$1" days=0 rest="$1"
  if [[ "$t" == *-* ]]; then
    days="${t%%-*}"
    rest="${t#*-}"
  fi
  IFS=: read -r h m s <<< "$rest"
  echo $(( 10#$days*86400 + 10#$h*3600 + 10#$m*60 + 10#$s ))
}

sacct_elapsed_sec() {
  local jid="$1"
  local elapsed
  elapsed=$(sacct -j "$jid" --format=Elapsed -X -n 2>/dev/null | tr -d ' ')
  [ -z "$elapsed" ] && { echo 0; return; }
  sec_from_hms "$elapsed"
}

fmt_min() {
  awk -v s="$1" 'BEGIN{printf "%.2f", s/60}'
}

echo "===================================================================="
echo "DAIKON SIDE (Chicory + daikon.Daikon), 6 benchmark projects"
echo "===================================================================="
echo "NOTE: Job IDs and sizes below are the ones confirmed this session."
echo "Several trace directories were already deleted (logged in"
echo "deleted-trace-sizes-20260927.txt / the compiled full+s5 size table)"
echo "so their size is hardcoded, not re-measured live. If you re-trace"
echo "any project, update the job IDs below accordingly."
echo

# --- Full runs: which succeeded, which failed, job IDs ---
declare -A DAIKON_FULL_CHICORY_JOB=( [apollo]=1260710 [spring]=1286325 [hudi]=1260713 [netty]=1295018 )
declare -A DAIKON_FULL_DAIKON_JOB=( [apollo]=1266079 [spring]=1286328 [hudi]=1266273 [netty]=1350673 [dubbo]=1294973 [libgdx]=1294974 )
declare -A DAIKON_FULL_STATE=( [apollo]=COMPLETED [spring]=COMPLETED [hudi]=COMPLETED [netty]=FAILED [dubbo]=FAILED [libgdx]=FAILED )

# --- Full-trace sizes in GB (from compiled size table / deleted-trace log, or live du for netty) ---
declare -A DAIKON_FULL_CHICORY_SIZE_GB=( [apollo]=2.3 [spring]=2.2 [hudi]=683 [netty]=2300 [dubbo]=280 [libgdx]=1900 )

# --- s5 runs: job IDs (only where a completed daikon run exists) ---
declare -A DAIKON_S5_CHICORY_JOB=( [dubbo]=1292749 [netty]=1286082 [libgdx]=1281653 )
declare -A DAIKON_S5_DAIKON_JOB=( [dubbo]=1295049 [netty]=1295032 [libgdx]=1292486 )

# --- s5 chicory trace dirs (for live du; may not exist if since deleted) ---
declare -A DAIKON_S5_CHICORY_DIR=(
  [apollo]="/scratch/mjk76/ea442/promptstudy/apollo-s5-chicory-out"
  [dubbo]="/scratch/mjk76/ea442/promptstudy/dubbo-s5-chicory-out"
  [hudi]="/scratch/mjk76/ea442/promptstudy/hudi-s5-chicory-out"
  [netty]="/scratch/mjk76/ea442/promptstudy/netty-s5-chicory-out"
  [spring]="/scratch/mjk76/ea442/promptstudy/spring-s5-chicory-out"
)

# --- s5 chicory size fallback (used if the live dir above no longer exists) ---
declare -A DAIKON_S5_CHICORY_SIZE_FALLBACK=( [apollo]="59M" [hudi]="98M" [spring]="12M" [netty]="704M" [libgdx]="90G" [dubbo]="1.1G" )

# --- Daikon output dirs (full and s5) ---
declare -A DAIKON_FULL_OUTPUT_DIR=( [apollo]="/project/mjk76/ea442/promptstudy/apollo-daikon-out" [spring]="/project/mjk76/ea442/promptstudy/spring-daikon-out" [hudi]="/project/mjk76/ea442/promptstudy/hudi-daikon-out" )
declare -A DAIKON_S5_OUTPUT_DIR=( [dubbo]="/project/mjk76/ea442/promptstudy/dubbo-s5-daikon-quickfix-out" [netty]="/project/mjk76/ea442/promptstudy/netty-s5-daikon-quickfix-out" [libgdx]="/project/mjk76/ea442/promptstudy/libgdx-s5-daikon-out" )

for p in apollo dubbo netty hudi libgdx spring; do
  echo "--- $p (full) ---"
  state="${DAIKON_FULL_STATE[$p]:-}"
  chicory_gb="${DAIKON_FULL_CHICORY_SIZE_GB[$p]:-?}"

  case "$state" in
    COMPLETED)
      cj=${DAIKON_FULL_CHICORY_JOB[$p]}
      dj=${DAIKON_FULL_DAIKON_JOB[$p]}
      ce=$(sacct_elapsed_sec "$cj")
      de=$(sacct_elapsed_sec "$dj")
      total=$((ce+de))
      out_dir=${DAIKON_FULL_OUTPUT_DIR[$p]:-}
      out_size="n/a"
      [ -n "$out_dir" ] && [ -d "$out_dir" ] && out_size=$(du -sh "$out_dir" 2>/dev/null | awk '{print $1}')
      echo "  chicory job=$cj elapsed=${ce}s ; daikon job=$dj elapsed=${de}s"
      echo "  TOTAL TIME = ${total}s ($(fmt_min $total) min)"
      echo "  chicory size = ${chicory_gb}G ; daikon output size = $out_size"
      ;;
    FAILED)
      cj=${DAIKON_FULL_CHICORY_JOB[$p]:-}
      dj=${DAIKON_FULL_DAIKON_JOB[$p]:-}
      if [ -n "$cj" ]; then
        ce=$(sacct_elapsed_sec "$cj")
        echo "  chicory job=$cj elapsed=${ce}s (COMPLETED)"
      else
        echo "  chicory: TIMEOUT / never completed (partial trace ${chicory_gb}G on disk before deletion)"
      fi
      if [ -n "$dj" ]; then
        de=$(sacct_elapsed_sec "$dj")
        echo "  daikon job=$dj elapsed=${de}s ($(fmt_min $de) min) -- FAILED (check .err for exact error)"
      else
        echo "  daikon: never ran to completion"
      fi
      echo "  chicory size = ${chicory_gb}G ; daikon output = none (failed, no usable output)"
      ;;
    *)
      echo "  no data recorded"
      ;;
  esac

  echo "--- $p (s5) ---"
  cj=${DAIKON_S5_CHICORY_JOB[$p]:-}
  dj=${DAIKON_S5_DAIKON_JOB[$p]:-}
  if [ -n "$cj" ] && [ -n "$dj" ]; then
    ce=$(sacct_elapsed_sec "$cj")
    de=$(sacct_elapsed_sec "$dj")
    total=$((ce+de))
    chicory_dir=${DAIKON_S5_CHICORY_DIR[$p]:-}
    out_dir=${DAIKON_S5_OUTPUT_DIR[$p]:-}
    csize=""
    [ -n "$chicory_dir" ] && [ -e "$chicory_dir" ] && csize=$(du -sh "$chicory_dir" 2>/dev/null | awk '{print $1}')
    if [ -z "$csize" ]; then
      csize="${DAIKON_S5_CHICORY_SIZE_FALLBACK[$p]:-n/a (dir not found, no fallback recorded)}"
    fi
    osize="n/a"
    [ -n "$out_dir" ] && [ -d "$out_dir" ] && osize=$(du -sh "$out_dir" 2>/dev/null | awk '{print $1}')
    echo "  chicory job=$cj elapsed=${ce}s ; daikon job=$dj elapsed=${de}s"
    echo "  TOTAL TIME = ${total}s ($(fmt_min $total) min)"
    echo "  chicory size = $csize ; daikon output size = $osize"
  else
    echo "  no completed s5 daikon run recorded for $p"
  fi
  echo
done

echo "===================================================================="
echo "OCA (daikonplusplus) SIDE, 6 benchmark projects"
echo "===================================================================="
echo "Source: resultsOfContextStudyFewshot/class_doc/<project>/run.log"
echo

CLASS_DOC_BASE="/project/mjk76/ea442/promptstudy/resultsOfContextStudyFewshot/class_doc"

for p in apollo dubbo hudi libgdx netty spring; do
  echo "--- $p ---"
  log="$CLASS_DOC_BASE/$p/run.log"
  if [ ! -f "$log" ]; then
    echo "  run.log not found at $log"
    echo
    continue
  fi

  start_line=$(grep -m1 "\[Scan phase\] started at" "$log")
  end_line=$(grep "\[Results phase\] finished at" "$log" | tail -1)

  start_ts=$(echo "$start_line" | sed -E 's/.*started at ([0-9-]+ [0-9:.]+).*/\1/' | sed -E 's/\.[0-9]+$//')
  end_ts=$(echo "$end_line" | sed -E 's/.*finished at ([0-9-]+ [0-9:.]+) \(.*/\1/' | sed -E 's/\.[0-9]+$//')

  if [ -n "$start_ts" ] && [ -n "$end_ts" ]; then
    start_epoch=$(date -d "$start_ts" +%s 2>/dev/null)
    end_epoch=$(date -d "$end_ts" +%s 2>/dev/null)
    if [ -n "$start_epoch" ] && [ -n "$end_epoch" ]; then
      elapsed=$((end_epoch - start_epoch))
      echo "  start=$start_ts  end=$end_ts"
      echo "  TOTAL TIME = ${elapsed}s ($(fmt_min $elapsed) min)"
    else
      echo "  could not parse timestamps: start='$start_ts' end='$end_ts'"
    fi
  else
    echo "  could not find start/end lines in $log"
  fi

  wc_path=$(grep -A1 "Keeping working copy" "$log" | grep "project:" | awk '{print $2}')
  echo "  working copy = $wc_path"
  wc_size="n/a (not found on disk)"
  [ -n "$wc_path" ] && [ -e "$wc_path" ] && wc_size=$(du -sh "$wc_path" 2>/dev/null | awk '{print $1}')

  out_dir="$CLASS_DOC_BASE/$p"
  out_size=$(du -sh "$out_dir" 2>/dev/null | awk '{print $1}')

  echo "  working copy size = $wc_size ; class_doc output size = $out_size"
  echo
done

echo "===================================================================="
echo "Results written to: $OUT"
echo "===================================================================="
