#!/bin/bash
# -----------------------------------------------------------------------------
# submit_all.sh -- submits the Chicory trace + io-examples pipeline for all
# four Maven projects (hudi, dubbo, netty, apollo) in one command. Each
# project's io-examples job is chained to run only after its own trace job
# finishes successfully (SLURM --dependency=afterok), so this is genuinely
# hands-off -- no need to babysit each trace job and manually submit
# io-examples once it's done.
#
# All four run with --sample-start=0 (unlimited sampling, per your choice).
# There is no prior data point for how big an unlimited trace gets on
# dubbo/netty/apollo specifically -- worth checking each *-chicory-out/
# dtrace.gz's growth rate an hour or two in, same way we caught it early on
# hudi, rather than waiting out the full --time budget to find out.
#
# Run from /project/mjk76/ea442/promptstudy (all paths in the individual
# scripts are absolute to that directory).
# -----------------------------------------------------------------------------
set -euo pipefail

declare -A TRACE_SCRIPT=(
  [hudi]="submit_hudi_chicory_trace_full.sh"
  [dubbo]="submit_dubbo_chicory_trace.sh"
  [netty]="submit_netty_chicory_trace.sh"
  [apollo]="submit_apollo_chicory_trace.sh"
)

declare -A IO_SCRIPT=(
  [hudi]="submit_hudi_io_examples_full.sh"
  [dubbo]="submit_dubbo_io_examples.sh"
  [netty]="submit_netty_io_examples.sh"
  [apollo]="submit_apollo_io_examples.sh"
)

for proj in hudi dubbo netty apollo; do
  echo "=== $proj ==="
  TRACE_JOB=$(sbatch --parsable "${TRACE_SCRIPT[$proj]}")
  echo "  trace job: $TRACE_JOB"
  IO_JOB=$(sbatch --parsable --dependency=afterok:"$TRACE_JOB" "${IO_SCRIPT[$proj]}")
  echo "  io-examples job (runs after $TRACE_JOB succeeds): $IO_JOB"
done

echo
echo ">>> All 8 jobs submitted. Check with: squeue -u \$USER"
