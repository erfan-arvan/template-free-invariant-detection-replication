#!/usr/bin/env python3

import csv
import json
import random
from collections import defaultdict, Counter
from pathlib import Path

BASE = Path(__file__).resolve().parent

BALANCED = (
    BASE
    / "oca_daikon_balanced_invariants"
    / "balanced-invariants.jsonl"
)

MANUAL = (
    BASE
    / "manual-daikon-verdicts.tsv"
)

OUT = (
    BASE
    / "artifact_reproduction"
)

FINAL_SELECTION_SEED = 44
REVIEW_SHUFFLE_SEED = 45


def read_jsonl(path):
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def candidate_key(program_point, expr):
    return (
        program_point.strip(),
        expr.strip(),
    )


def method_key(project, method):
    return (
        project,
        method,
    )


def oca_expr(inv):
    if "expr" in inv:
        return inv["expr"]

    if "expression" in inv:
        return inv["expression"]

    raise RuntimeError(
        f"Cannot find OCA expression in:\n{inv}"
    )


def oca_program_point(inv):
    if "kind" in inv:
        return inv["kind"]

    return inv.get(
        "program_point",
        ""
    )


# ============================================================
# 0. Setup
# ============================================================

OUT.mkdir(
    parents=True,
    exist_ok=True,
)

rng = random.Random(
    FINAL_SELECTION_SEED
)


# ============================================================
# 1. Load the stage-2 balanced sample.
#
# This file is produced by:
#
#   sample_oca_daikon_matched.py   seed 42
#   balance_sampled_invariants.py  seed 43
#
# No normalization decisions have been applied at this point.
# ============================================================

balanced = list(
    read_jsonl(BALANCED)
)

if len(balanced) != 60:
    raise RuntimeError(
        f"Expected 60 sampled methods; "
        f"found {len(balanced)}"
    )

print(
    "Stage-2 sampled methods:",
    len(balanced),
)


# ============================================================
# 2. Load externally supplied/manual Daikon verdicts.
# ============================================================

manual_by_method = defaultdict(list)

with open(
    MANUAL,
    encoding="utf-8",
) as f:

    reader = csv.DictReader(
        f,
        delimiter="\t",
    )

    required = {
        "project",
        "daikon_method",
        "candidate_order",
        "program_point",
        "original_expression",
        "status",
        "java_expression",
    }

    missing = required - set(
        reader.fieldnames or []
    )

    if missing:
        raise RuntimeError(
            "Manual verdict TSV is missing columns: "
            + ", ".join(sorted(missing))
        )

    for row in reader:

        status = (
            row["status"]
            .strip()
            .upper()
        )

        if status not in {
            "VALID",
            "CORRECTED",
            "INVALID",
        }:
            raise RuntimeError(
                f"Bad status: {status}"
            )

        row["status"] = status
        row["candidate_order"] = int(
            row["candidate_order"]
        )

        if (
            status in {
                "VALID",
                "CORRECTED",
            }
            and not row[
                "java_expression"
            ].strip()
        ):
            raise RuntimeError(
                "Usable verdict has empty "
                "java_expression:\n"
                + repr(row)
            )

        k = method_key(
            row["project"],
            row["daikon_method"],
        )

        manual_by_method[k].append(
            row
        )


# Ensure deterministic original candidate order.
for k in manual_by_method:

    manual_by_method[k].sort(
        key=lambda r: (
            r["candidate_order"],
            r["program_point"],
            r["original_expression"],
        )
    )


print(
    "Methods with manual verdicts:",
    len(manual_by_method),
)


# ============================================================
# 3. Reproduce final balancing.
#
# For each originally selected method:
#
#   original_k = stage-2 balanced count
#
#   final_k =
#       min(
#           original_k,
#           number of manually accepted Daikon candidates
#       )
#
# Preserve accepted invariants from the original seed-43
# sample whenever possible.
#
# If some originally sampled Daikon invariants were rejected,
# fill the missing positions by sampling from the remaining
# manually accepted Daikon candidates using seed 44.
#
# OCA is downsampled to final_k using the same RNG.
# ============================================================

final_methods = []
flat_rows = []
summary = []

total_oca = 0
total_daikon = 0
replacement_total = 0


for rec in balanced:

    project = rec["project"]
    sample_index = int(
        rec["sample_index"]
    )

    oca_method = rec["oca_method"]
    daikon_method = rec[
        "daikon_method"
    ]

    original_oca = list(
        rec["oca_sample"]
    )

    original_daikon = list(
        rec["daikon_sample"]
    )

    original_k = len(
        original_oca
    )

    if original_k != len(
        original_daikon
    ):
        raise RuntimeError(
            f"Stage-2 sample is not balanced: "
            f"{project} / {sample_index}"
        )

    mk = method_key(
        project,
        daikon_method,
    )

    if mk not in manual_by_method:
        raise RuntimeError(
            "No manual verdict pool for:\n"
            f"{project}\n"
            f"{daikon_method}"
        )

    verdict_rows = (
        manual_by_method[mk]
    )

    usable = [
        row
        for row in verdict_rows
        if row["status"]
        in {
            "VALID",
            "CORRECTED",
        }
    ]

    # Deduplicate exact original candidates,
    # retaining original candidate order.
    seen = set()
    pool = []

    for row in usable:

        ck = candidate_key(
            row["program_point"],
            row["original_expression"],
        )

        if ck in seen:
            continue

        seen.add(ck)
        pool.append(row)

    final_k = min(
        original_k,
        len(pool),
    )

    pool_by_original = {
        candidate_key(
            r["program_point"],
            r["original_expression"],
        ): r
        for r in pool
    }

    # --------------------------------------------------------
    # Which originally sampled Daikon invariants survived
    # the manual verdict?
    # --------------------------------------------------------

    surviving = []

    for inv in original_daikon:

        ck = candidate_key(
            inv["program_point"],
            inv["expr"],
        )

        if ck in pool_by_original:
            surviving.append(
                pool_by_original[ck]
            )

    # --------------------------------------------------------
    # Final Daikon selection.
    # --------------------------------------------------------

    if len(surviving) > final_k:

        final_daikon = rng.sample(
            surviving,
            final_k,
        )

    else:

        final_daikon = list(
            surviving
        )

        already = {
            candidate_key(
                r["program_point"],
                r["original_expression"],
            )
            for r in final_daikon
        }

        replacements = [
            r
            for r in pool
            if candidate_key(
                r["program_point"],
                r["original_expression"],
            )
            not in already
        ]

        need = (
            final_k
            - len(final_daikon)
        )

        if need > len(
            replacements
        ):
            raise RuntimeError(
                f"Not enough replacements for "
                f"{project} / {daikon_method}"
            )

        picked = (
            rng.sample(
                replacements,
                need,
            )
            if need
            else []
        )

        final_daikon.extend(
            picked
        )

        replacement_total += len(
            picked
        )

    # --------------------------------------------------------
    # Final OCA selection.
    #
    # OCA already came from the original seed-43 sample.
    # Only downsample if final_k decreased.
    # --------------------------------------------------------

    if final_k < original_k:

        final_oca = rng.sample(
            original_oca,
            final_k,
        )

    else:

        final_oca = list(
            original_oca
        )

    if len(final_oca) != len(
        final_daikon
    ):
        raise RuntimeError(
            "Internal imbalance for "
            f"{project} / {sample_index}"
        )

    # --------------------------------------------------------
    # Track whether selected Daikon rows were already present
    # in the original stage-2 sample.
    # --------------------------------------------------------

    original_daikon_keys = {
        candidate_key(
            inv["program_point"],
            inv["expr"],
        )
        for inv in original_daikon
    }

    daikon_records = []

    for i, row in enumerate(
        final_daikon,
        1,
    ):

        ck = candidate_key(
            row["program_point"],
            row["original_expression"],
        )

        selection_status = (
            "RETAINED_ORIGINAL_SAMPLE"
            if ck
            in original_daikon_keys
            else "RESAMPLED_REPLACEMENT"
        )

        d = {
            "final_index": i,
            "program_point":
                row["program_point"],
            "original_expression":
                row[
                    "original_expression"
                ],
            "java_expression":
                row[
                    "java_expression"
                ],
            "manual_status":
                row["status"],
            "candidate_order":
                row[
                    "candidate_order"
                ],
            "selection_status":
                selection_status,
        }

        daikon_records.append(d)

        flat_rows.append({
            "project":
                project,
            "sample_index":
                sample_index,
            "tool":
                "DAIKON",
            "method":
                daikon_method,
            "final_index":
                i,
            "program_point":
                row["program_point"],
            "original_expression":
                row[
                    "original_expression"
                ],
            "java_expression":
                row[
                    "java_expression"
                ],
            "selection_status":
                selection_status,
        })

    oca_records = []

    for i, inv in enumerate(
        final_oca,
        1,
    ):

        expr = oca_expr(inv)
        pp = oca_program_point(inv)

        o = {
            "final_index": i,
            "program_point": pp,
            "java_expression": expr,
        }

        oca_records.append(o)

        flat_rows.append({
            "project":
                project,
            "sample_index":
                sample_index,
            "tool":
                "OCA",
            "method":
                oca_method,
            "final_index":
                i,
            "program_point":
                pp,
            "original_expression":
                expr,
            "java_expression":
                expr,
            "selection_status":
                "ORIGINAL_OCA_SAMPLE",
        })

    retained = sum(
        d["selection_status"]
        == "RETAINED_ORIGINAL_SAMPLE"
        for d in daikon_records
    )

    replacements = sum(
        d["selection_status"]
        == "RESAMPLED_REPLACEMENT"
        for d in daikon_records
    )

    final_methods.append({
        "project":
            project,
        "sample_index":
            sample_index,
        "oca_method":
            oca_method,
        "daikon_method":
            daikon_method,
        "original_k":
            original_k,
        "manual_accepted_daikon":
            len(pool),
        "final_k_each":
            final_k,
        "retained_original_daikon":
            retained,
        "replacement_daikon":
            replacements,
        "oca_final":
            oca_records,
        "daikon_final":
            daikon_records,
    })

    summary.append({
        "project":
            project,
        "sample_index":
            sample_index,
        "oca_method":
            oca_method,
        "daikon_method":
            daikon_method,
        "original_k":
            original_k,
        "manual_accepted_daikon":
            len(pool),
        "final_k_each":
            final_k,
        "retained_original_daikon":
            retained,
        "replacement_daikon":
            replacements,
    })

    total_oca += len(
        final_oca
    )

    total_daikon += len(
        final_daikon
    )


# ============================================================
# 4. Sanity checks.
# ============================================================

print()
print(
    "Final OCA:",
    total_oca,
)
print(
    "Final Daikon:",
    total_daikon,
)
print(
    "Final total:",
    total_oca + total_daikon,
)
print(
    "Daikon replacements:",
    replacement_total,
)

if total_oca != total_daikon:
    raise RuntimeError(
        "Final dataset is not balanced."
    )


# For the verdict file corresponding to the dataset you
# constructed previously, these should reproduce:
#
#   179 OCA
#   179 Daikon
#   358 total
#
if (
    total_oca != 179
    or total_daikon != 179
):
    print()
    print(
        "WARNING: This verdict file does not "
        "reproduce the expected 179 + 179."
    )


# ============================================================
# 5. Method-level JSONL.
# ============================================================

jsonl_out = (
    OUT
    / "final-balanced.jsonl"
)

with open(
    jsonl_out,
    "w",
    encoding="utf-8",
) as f:

    for row in final_methods:
        f.write(
            json.dumps(
                row,
                ensure_ascii=False,
            )
            + "\n"
        )


# ============================================================
# 6. Flat internal audit.
# ============================================================

audit_out = (
    OUT
    / "final-balanced-audit.tsv"
)

audit_fields = [
    "project",
    "sample_index",
    "tool",
    "method",
    "final_index",
    "program_point",
    "original_expression",
    "java_expression",
    "selection_status",
]

with open(
    audit_out,
    "w",
    encoding="utf-8",
    newline="",
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=audit_fields,
        delimiter="\t",
        lineterminator="\n",
    )

    writer.writeheader()
    writer.writerows(
        flat_rows
    )


# ============================================================
# 7. Per-method summary.
# ============================================================

summary_out = (
    OUT
    / "final-method-summary.tsv"
)

summary_fields = [
    "project",
    "sample_index",
    "oca_method",
    "daikon_method",
    "original_k",
    "manual_accepted_daikon",
    "final_k_each",
    "retained_original_daikon",
    "replacement_daikon",
]

with open(
    summary_out,
    "w",
    encoding="utf-8",
    newline="",
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=summary_fields,
        delimiter="\t",
        lineterminator="\n",
    )

    writer.writeheader()
    writer.writerows(
        summary
    )


# ============================================================
# 8. Reviewer dataset.
# ============================================================

review_rows = [
    {
        "project":
            r["project"],
        "sample_index":
            r["sample_index"],
        "method":
            r["method"],
        "program_point":
            r["program_point"],
        "java_expression":
            r["java_expression"],
        "_tool":
            r["tool"],
    }
    for r in flat_rows
]


shuffle_rng = random.Random(
    REVIEW_SHUFFLE_SEED
)

shuffle_rng.shuffle(
    review_rows
)


review_out = (
    OUT
    / "reviewer-dataset.tsv"
)

key_out = (
    OUT
    / "reviewer-answer-key.tsv"
)

review_fields = [
    "review_id",
    "project",
    "sample_index",
    "method",
    "program_point",
    "java_expression",
]

with open(
    review_out,
    "w",
    encoding="utf-8",
    newline="",
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=review_fields,
        delimiter="\t",
        lineterminator="\n",
    )

    writer.writeheader()

    for i, row in enumerate(
        review_rows,
        1,
    ):
        writer.writerow({
            "review_id":
                f"INV-{i:04d}",
            "project":
                row["project"],
            "sample_index":
                row["sample_index"],
            "method":
                row["method"],
            "program_point":
                row["program_point"],
            "java_expression":
                row["java_expression"],
        })


with open(
    key_out,
    "w",
    encoding="utf-8",
    newline="",
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=[
            "review_id",
            "tool",
        ],
        delimiter="\t",
        lineterminator="\n",
    )

    writer.writeheader()

    for i, row in enumerate(
        review_rows,
        1,
    ):
        writer.writerow({
            "review_id":
                f"INV-{i:04d}",
            "tool":
                row["_tool"],
        })


# ============================================================
# 9. Final report.
# ============================================================

print()
print("=" * 72)
print("REPRODUCTION COMPLETE")
print("=" * 72)

print(
    "Methods:",
    len(final_methods),
)

print(
    "Methods contributing >=1 invariant:",
    sum(
        int(r["final_k_each"]) > 0
        for r in summary
    ),
)

print(
    "OCA:",
    total_oca,
)

print(
    "Daikon:",
    total_daikon,
)

print(
    "Total:",
    total_oca + total_daikon,
)

print()
print("Outputs:")
print(jsonl_out)
print(audit_out)
print(summary_out)
print(review_out)
print(key_out)
