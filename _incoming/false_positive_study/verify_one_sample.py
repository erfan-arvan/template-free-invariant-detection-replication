#!/usr/bin/env python3

import csv
import json
from collections import Counter
from pathlib import Path

BASE = Path(__file__).resolve().parent

KEYED = BASE / "reviewer_files" / "invariants-for-review-with-tool.tsv"
SUMMARY = BASE / "artifact_reproduction" / "final-method-summary.tsv"
AUDIT = BASE / "artifact_reproduction" / "final-balanced-audit.tsv"

PROJECT = "dubbo"
CANONICAL_METHOD = (
    "org.apache.dubbo.common.utils.LogHelper.error("
    "org.apache.dubbo.common.logger.Logger, "
    "java.lang.String, "
    "java.lang.Throwable)"
)

DAIKON_RAW = (
    BASE
    / "dubbo-s5-daikon-quickfix-out"
    / "dubbo-s5-quickfix-invariants.txt"
)

OCA_DIR = (
    BASE
    / "resultsOfContextStudyFewshot"
    / "class_doc"
    / PROJECT
)

REGISTRY = OCA_DIR / "daikonpp_registry.jsonl"
OUTCOMES = OCA_DIR / "daikonpp_outcomes.jsonl"


def read_tsv(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def read_jsonl(path):
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def norm_pp(pp):
    p = pp.upper()

    if "ENTER" in p or "METHOD_ENTRY" in p:
        return "ENTRY"

    if "EXIT" in p or "METHOD_EXIT" in p:
        return "EXIT"

    return pp


def all_scalar_values(obj):
    """Recursively yield scalar values from a JSON object."""
    if isinstance(obj, dict):
        for v in obj.values():
            yield from all_scalar_values(v)

    elif isinstance(obj, list):
        for v in obj:
            yield from all_scalar_values(v)

    else:
        yield obj


def contains_exact_string(obj, target):
    return any(
        isinstance(v, str) and v == target
        for v in all_scalar_values(obj)
    )


def candidate_ids(obj):
    """
    Extract likely invariant IDs without assuming one exact schema.
    """
    result = set()

    if isinstance(obj, dict):
        for k, v in obj.items():
            lk = k.lower()

            if (
                lk in {
                    "id",
                    "invariant_id",
                    "invariantid",
                    "inv_id",
                    "candidate_id",
                }
                and isinstance(v, (str, int))
            ):
                result.add(str(v))

            result |= candidate_ids(v)

    elif isinstance(obj, list):
        for v in obj:
            result |= candidate_ids(v)

    return result


def object_has_id(obj, wanted):
    return wanted in candidate_ids(obj)


# ============================================================
# 1. Find this method in final method summary.
# ============================================================

summary = read_tsv(SUMMARY)

matches = [
    r for r in summary
    if r["project"] == PROJECT
    and r["daikon_method"] == CANONICAL_METHOD
]

assert len(matches) == 1, (
    f"Expected exactly one method-summary match, got {len(matches)}"
)

method_row = matches[0]
sample_index = method_row["sample_index"]

print("=" * 80)
print("METHOD")
print("=" * 80)
print("Project:", PROJECT)
print("Sample index:", sample_index)
print("Canonical method:", CANONICAL_METHOD)
print("OCA method:", method_row["oca_method"])
print("final_k_each:", method_row["final_k_each"])


# ============================================================
# 2. Reviewer rows for this method.
# ============================================================

keyed = read_tsv(KEYED)

review_rows = [
    r for r in keyed
    if r["project"] == PROJECT
    and r["method_signature"] == CANONICAL_METHOD
]

print()
print("=" * 80)
print("REVIEWER ROWS")
print("=" * 80)

for r in review_rows:
    print(
        r["review_id"],
        r["source_tool"],
        r["program_point"],
        r["invariant"],
        sep="\t",
    )

print()
print("Reviewer rows:", len(review_rows))
print(
    "Reviewer tool counts:",
    Counter(r["source_tool"] for r in review_rows),
)


# ============================================================
# 3. Find corresponding rows in final audit.
# ============================================================

audit = read_tsv(AUDIT)

audit_rows = [
    r for r in audit
    if r["project"] == PROJECT
    and r["sample_index"] == sample_index
]

print()
print("=" * 80)
print("FINAL AUDIT ROWS")
print("=" * 80)

for r in audit_rows:
    print()
    print("TOOL:", r["tool"])
    print("PP:", norm_pp(r["program_point"]))
    print("ORIGINAL:", r["original_expression"])
    print("FINAL:", r["java_expression"])


# ============================================================
# 4. Confirm reviewer block == final audit block.
# ============================================================

review_multiset = Counter(
    (
        r["source_tool"],
        r["program_point"],
        r["invariant"],
    )
    for r in review_rows
)

audit_multiset = Counter(
    (
        r["tool"],
        norm_pp(r["program_point"]),
        r["java_expression"],
    )
    for r in audit_rows
)

print()
print("=" * 80)
print("REVIEWER -> FINAL AUDIT CHECK")
print("=" * 80)

if review_multiset == audit_multiset:
    print("PASS: reviewer rows exactly match final audit rows.")
else:
    print("FAIL: reviewer and audit rows differ.")

    print("Missing from reviewer:")
    for x, n in (audit_multiset - review_multiset).items():
        print(n, x)

    print("Extra in reviewer:")
    for x, n in (review_multiset - audit_multiset).items():
        print(n, x)

    raise SystemExit(1)


# ============================================================
# 5. Verify Daikon rows against ORIGINAL Daikon text.
# ============================================================

raw_lines = DAIKON_RAW.read_text(
    encoding="utf-8",
    errors="replace",
).splitlines()


def daikon_exact_match(program_point, expression):
    """
    Find exact program point, then exact invariant line before
    the next Daikon program-point header.
    """

    for i, line in enumerate(raw_lines):

        if line.strip() != program_point.strip():
            continue

        j = i + 1

        while j < len(raw_lines):

            current = raw_lines[j].strip()

            # Next program point begins.
            if ":::" in current:
                break

            if current == expression.strip():
                return True, i + 1, j + 1

            j += 1

    return False, None, None


print()
print("=" * 80)
print("DAIKON RAW-OUTPUT CHECK")
print("=" * 80)

daikon_rows = [
    r for r in audit_rows
    if r["tool"] == "DAIKON"
]

for r in daikon_rows:

    ok, pp_line, inv_line = daikon_exact_match(
        r["program_point"],
        r["original_expression"],
    )

    print()
    print("Final expression:")
    print(" ", r["java_expression"])

    print("Original Daikon expression:")
    print(" ", r["original_expression"])

    if ok:
        print(
            f"PASS: found exactly in raw Daikon output "
            f"(program point line {pp_line}, invariant line {inv_line})"
        )
    else:
        print("FAIL: not found under expected Daikon program point")
        raise SystemExit(1)


# ============================================================
# 6. Load raw OCA registry + outcomes.
# ============================================================

registry = list(read_jsonl(REGISTRY))
outcomes = list(read_jsonl(OUTCOMES))

print()
print("=" * 80)
print("OCA RAW HELD CHECK")
print("=" * 80)

oca_rows = [
    r for r in audit_rows
    if r["tool"] == "OCA"
]

for r in oca_rows:

    expr = r["original_expression"]

    registry_matches = [
        obj
        for obj in registry
        if contains_exact_string(obj, expr)
    ]

    print()
    print("Expression:")
    print(" ", expr)

    print("Registry exact-expression matches:", len(registry_matches))

    if not registry_matches:
        print("FAIL: expression not present in OCA registry")
        raise SystemExit(1)

    ids = set()

    for obj in registry_matches:
        ids |= candidate_ids(obj)

    if not ids:
        print("FAIL: found registry row but could not recover invariant ID")
        print("Matching registry object(s):")
        for obj in registry_matches:
            print(json.dumps(obj, indent=2))
        raise SystemExit(1)

    held_matches = []

    for inv_id in ids:

        for outcome in outcomes:

            if not object_has_id(outcome, inv_id):
                continue

            verdict = str(
                outcome.get("verdict", "")
            ).upper()

            compiled = outcome.get("compiled")
            executed = outcome.get("executed")

            if (
                verdict == "HELD"
                and compiled is True
                and executed is True
            ):
                held_matches.append(
                    (inv_id, outcome)
                )

    if held_matches:

        print("PASS: raw OCA invariant is observed-held.")

        for inv_id, outcome in held_matches:
            print("  invariant id:", inv_id)
            print(
                "  verdict:",
                outcome.get("verdict"),
                "compiled:",
                outcome.get("compiled"),
                "executed:",
                outcome.get("executed"),
            )

    else:

        print(
            "FAIL: registry expression found, but no matching "
            "HELD + compiled=true + executed=true outcome."
        )

        print("Candidate IDs:", sorted(ids))

        raise SystemExit(1)


# ============================================================
# 7. Final conclusion.
# ============================================================

print()
print("=" * 80)
print("END-TO-END SAMPLE CHECK PASSED")
print("=" * 80)
print(
    "The reviewer block corresponds exactly to the final audit; "
    "its Daikon invariants occur in the original Daikon report; "
    "and its OCA invariants occur in the original registry with "
    "HELD, compiled=true, executed=true outcomes."
)
