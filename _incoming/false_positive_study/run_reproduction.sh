#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "============================================================"
echo "FALSE-POSITIVE STUDY REPRODUCTION"
echo "============================================================"

rm -rf \
    oca_daikon_matched_samples \
    oca_daikon_balanced_invariants \
    artifact_reproduction

echo
echo "[1/3] Matched-method sampling (seed 42)"
python sample_oca_daikon_matched.py

echo
echo "[2/3] Balanced-invariant sampling (seed 43)"
python balance_sampled_invariants.py

echo
echo "[3/3] Representation filtering/replacement (seed 44)"
python reproduce_final_from_manual_verdicts.py

echo
echo "============================================================"
echo "REPRODUCTION COMPLETE"
echo "============================================================"
