#!/usr/bin/env python3

import csv
import random
import re
from collections import defaultdict
from pathlib import Path

BASE = Path(__file__).resolve().parent

AUDIT = (
    BASE
    / "artifact_reproduction"
    / "final-balanced-audit.tsv"
)

METHOD_SUMMARY = (
    BASE
    / "artifact_reproduction"
    / "final-method-summary.tsv"
)

OUTDIR = BASE / "reviewer_files"

BLIND_OUT = OUTDIR / "invariants-for-review.tsv"
KEYED_OUT = OUTDIR / "invariants-for-review-with-tool.tsv"

# Separate seed used only for presentation order.
REVIEW_ORDER_SEED = 46


# ============================================================
# Helpers
# ============================================================

def normalize_program_point(pp):
    """
    Convert tool-specific program-point notation to a common
    reviewer-facing label.
    """

    pp_upper = pp.upper()

    if "ENTER" in pp_upper or "METHOD_ENTRY" in pp_upper:
        return "ENTRY"

    if "EXIT" in pp_upper or "METHOD_EXIT" in pp_upper:
        return "EXIT"

    raise RuntimeError(
        f"Unrecognized program point: {pp!r}"
    )


def parse_method_signature(signature):
    """
    Expected canonical form such as:

      org.example.Foo.bar(java.lang.String,int)

    Returns:
      class_name
      method_name
      parameters
    """

    signature = signature.strip()

    open_paren = signature.rfind("(")
    close_paren = signature.rfind(")")

    if open_paren == -1 or close_paren == -1 or close_paren < open_paren:
        raise RuntimeError(
            f"Cannot parse method signature: {signature}"
        )

    before = signature[:open_paren]
    parameters = signature[open_paren + 1:close_paren]

    dot = before.rfind(".")

    if dot == -1:
        raise RuntimeError(
            f"Cannot separate class/method: {signature}"
        )

    class_name = before[:dot]
    method_name = before[dot + 1:]

    return class_name, method_name, parameters


def read_tsv(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))


# ============================================================
# 1. Load canonical matched-method metadata
# ============================================================

summary = read_tsv(METHOD_SUMMARY)

method_info = {}

for row in summary:

    key = (
        row["project"],
        row["sample_index"],
    )

    if key in method_info:
        raise RuntimeError(
            f"Duplicate method summary key: {key}"
        )

    canonical = row["daikon_method"].strip()

    class_name, method_name, parameters = (
        parse_method_signature(canonical)
    )

    method_info[key] = {
        "canonical_method": canonical,
        "class_name": class_name,
        "method_name": method_name,
        "parameters": parameters,
    }


if len(method_info) != 60:
    raise RuntimeError(
        f"Expected 60 sampled methods, found {len(method_info)}"
    )


# ============================================================
# 2. Load final 358 invariant rows
# ============================================================

audit = read_tsv(AUDIT)

if len(audit) != 358:
    raise RuntimeError(
        f"Expected 358 final invariants, found {len(audit)}"
    )


# ============================================================
# 3. Group by sampled method
# ============================================================

groups = defaultdict(list)

for row in audit:

    key = (
        row["project"],
        row["sample_index"],
    )

    if key not in method_info:
        raise RuntimeError(
            f"No method metadata for {key}"
        )

    info = method_info[key]

    groups[key].append({
        "project": row["project"],
        "sample_index": row["sample_index"],

        # Same canonical metadata regardless of originating tool.
        "class_name": info["class_name"],
        "method_name": info["method_name"],
        "parameters": info["parameters"],
        "method_signature": info["canonical_method"],

        # Tool-specific program-point notation is hidden.
        "program_point": normalize_program_point(
            row["program_point"]
        ),

        "invariant": row["java_expression"],

        # Private field; omitted from blind file.
        "source_tool": row["tool"],
    })


# ============================================================
# 4. Shuffle presentation order
#
# Important:
#   - each method remains a contiguous block
#   - method blocks are shuffled
#   - rows inside each block are shuffled
#   - OCA and Daikon therefore appear intermixed
# ============================================================

rng = random.Random(REVIEW_ORDER_SEED)

group_keys = list(groups.keys())
rng.shuffle(group_keys)

ordered = []

for key in group_keys:

    rows = list(groups[key])

    rng.shuffle(rows)

    ordered.extend(rows)


if len(ordered) != 358:
    raise RuntimeError(
        f"Expected 358 ordered rows, found {len(ordered)}"
    )


# ============================================================
# 5. Assign stable review IDs
# ============================================================

for i, row in enumerate(ordered, 1):
    row["review_id"] = f"INV-{i:04d}"


# ============================================================
# 6. Write blind reviewer TSV
# ============================================================

OUTDIR.mkdir(
    parents=True,
    exist_ok=True,
)

blind_fields = [
    "review_id",
    "project",
    "class_name",
    "method_name",
    "parameters",
    "method_signature",
    "program_point",
    "invariant",
]

with open(
    BLIND_OUT,
    "w",
    encoding="utf-8",
    newline="",
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=blind_fields,
        delimiter="\t",
        lineterminator="\n",
    )

    writer.writeheader()

    for row in ordered:
        writer.writerow({
            field: row[field]
            for field in blind_fields
        })


# ============================================================
# 7. Write private keyed TSV
#
# Identical order and review IDs; only difference is source_tool.
# ============================================================

keyed_fields = blind_fields + [
    "source_tool",
]

with open(
    KEYED_OUT,
    "w",
    encoding="utf-8",
    newline="",
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=keyed_fields,
        delimiter="\t",
        lineterminator="\n",
    )

    writer.writeheader()

    for row in ordered:
        writer.writerow({
            field: row[field]
            for field in keyed_fields
        })


# ============================================================
# 8. Verification
# ============================================================

oca = sum(
    row["source_tool"] == "OCA"
    for row in ordered
)

daikon = sum(
    row["source_tool"] == "DAIKON"
    for row in ordered
)

print("=" * 72)
print("REVIEWER TSVs CREATED")
print("=" * 72)

print("Total invariants:", len(ordered))
print("OCA:", oca)
print("Daikon:", daikon)
print("Method groups:", len(groups))

print()
print("Blind reviewer file:")
print(BLIND_OUT)

print()
print("Private keyed file:")
print(KEYED_OUT)

print()
print(
    "Rows from each method are contiguous; "
    "OCA/Daikon rows are shuffled within each method."
)
