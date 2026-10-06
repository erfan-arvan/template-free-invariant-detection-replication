#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "============================================================"
echo "1. REQUIRED FILES"
echo "============================================================"

required=(
    "sample_oca_daikon_matched.py"
    "balance_sampled_invariants.py"
    "reproduce_final_from_manual_verdicts.py"
    "manual-daikon-verdicts.tsv"
    "run_reproduction.sh"

    "apollo-daikon-out/apollo-invariants.txt"
    "hudi-daikon-out/hudi-invariants.txt"
    "spring-daikon-out/spring-invariants.txt"
    "libgdx-s5-daikon-out/libgdx-s5-invariants.txt"
    "dubbo-s5-daikon-quickfix-out/dubbo-s5-quickfix-invariants.txt"
    "netty-s5-daikon-quickfix-out/netty-s5-quickfix-invariants.txt"

    "reference_outputs/selected-methods.tsv"
    "reference_outputs/final-balanced-audit.tsv"
)

for f in "${required[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "MISSING: $f"
        exit 1
    fi
    echo "OK: $f"
done


for project in apollo hudi spring libgdx dubbo netty; do
    for f in \
        daikonpp_outcomes.jsonl \
        daikonpp_registry.jsonl \
        daikonpp_invariant_metrics.jsonl \
        run.log
    do
        path="resultsOfContextStudyFewshot/class_doc/$project/$f"

        if [[ ! -f "$path" ]]; then
            echo "MISSING: $path"
            exit 1
        fi
    done

    echo "OK: OCA inputs for $project"
done


echo
echo "============================================================"
echo "2. PORTABILITY CHECK"
echo "============================================================"

if grep -RIn \
    "/project/mjk76/ea442/promptstudy" \
    . \
    --include='*.py' \
    --include='*.sh' \
    --exclude='verify_artifact.sh'
then
    echo
    echo "FAIL: hard-coded original experiment path remains."
    exit 1
fi

echo "PASS: no hard-coded original experiment paths."


echo
echo "============================================================"
echo "3. PYTHON SYNTAX CHECK"
echo "============================================================"

python -m py_compile \
    sample_oca_daikon_matched.py \
    balance_sampled_invariants.py \
    reproduce_final_from_manual_verdicts.py

echo "PASS: Python scripts compile."


echo
echo "============================================================"
echo "4. FULL REPRODUCTION"
echo "============================================================"

./run_reproduction.sh


echo
echo "============================================================"
echo "5. EXACT OUTPUT VERIFICATION"
echo "============================================================"

python - <<'PY'
import csv
from collections import Counter
from pathlib import Path

BASE = Path.cwd()

REF_METHODS = (
    BASE
    / "reference_outputs"
    / "selected-methods.tsv"
)

NEW_METHODS = (
    BASE
    / "oca_daikon_matched_samples"
    / "selected-methods.tsv"
)

REF_FINAL = (
    BASE
    / "reference_outputs"
    / "final-balanced-audit.tsv"
)

NEW_FINAL = (
    BASE
    / "artifact_reproduction"
    / "final-balanced-audit.tsv"
)


def load(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))


# ------------------------------------------------------------
# Check matched methods.
# ------------------------------------------------------------

ref_methods = load(REF_METHODS)
new_methods = load(NEW_METHODS)

def method_id(r):
    return (
        r["project"],
        r["sample_index"],
        r["oca_method"],
        r["daikon_method"],
    )

rm = Counter(method_id(r) for r in ref_methods)
nm = Counter(method_id(r) for r in new_methods)

print("Reference methods:", len(ref_methods))
print("Reproduced methods:", len(new_methods))

if len(new_methods) != 60:
    raise SystemExit(
        f"FAIL: expected 60 methods, got {len(new_methods)}"
    )

if rm != nm:
    print("FAIL: selected methods differ.")

    for item, n in (rm - nm).items():
        print("MISSING METHOD:", n, item)

    for item, n in (nm - rm).items():
        print("EXTRA METHOD:", n, item)

    raise SystemExit(1)

print("PASS: exact same 60 matched methods.")


# ------------------------------------------------------------
# Check final invariant identities.
# ------------------------------------------------------------

ref = load(REF_FINAL)
new = load(NEW_FINAL)

def inv_id(r):
    return (
        r["project"],
        r["sample_index"],
        r["tool"],
        r["method"],
        r["program_point"],
        r["original_expression"],
    )

ref_ids = Counter(inv_id(r) for r in ref)
new_ids = Counter(inv_id(r) for r in new)

print()
print("Reference rows:", len(ref))
print("Reproduced rows:", len(new))

ref_counts = Counter(r["tool"] for r in ref)
new_counts = Counter(r["tool"] for r in new)

print("Reference tool counts:", ref_counts)
print("Reproduced tool counts:", new_counts)

if len(new) != 358:
    raise SystemExit(
        f"FAIL: expected 358 final rows, got {len(new)}"
    )

if new_counts != Counter({"OCA": 179, "DAIKON": 179}):
    raise SystemExit(
        f"FAIL: unexpected final tool counts: {new_counts}"
    )

missing = ref_ids - new_ids
extra = new_ids - ref_ids

if missing or extra:

    print("FAIL: invariant identities differ.")

    for item, n in missing.items():
        print("MISSING:", n, item)

    for item, n in extra.items():
        print("EXTRA:", n, item)

    raise SystemExit(1)

print("PASS: exact same invariant multiset.")


# ------------------------------------------------------------
# Check final normalized expressions.
# ------------------------------------------------------------

ref_expr = {
    inv_id(r): r["java_expression"]
    for r in ref
}

new_expr = {
    inv_id(r): r["java_expression"]
    for r in new
}

diffs = []

for key in ref_expr.keys():
    if ref_expr[key] != new_expr[key]:
        diffs.append(
            (
                key,
                ref_expr[key],
                new_expr[key],
            )
        )

if diffs:

    print(
        f"FAIL: {len(diffs)} expression differences."
    )

    for key, expected, actual in diffs:
        print()
        print("KEY:", key)
        print("REFERENCE:", expected)
        print("REPRODUCED:", actual)

    raise SystemExit(1)

print("PASS: 0 expression differences.")


# ------------------------------------------------------------
# Final result.
# ------------------------------------------------------------

print()
print("============================================================")
print("PERFECT REPRODUCTION")
print("============================================================")
print("Same 60 matched methods.")
print("Same 179 OCA invariants.")
print("Same 179 Daikon invariants.")
print("Same invariant identities.")
print("Same final expressions.")
PY
