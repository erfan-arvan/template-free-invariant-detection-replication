#!/usr/bin/env python3

import csv
import random
from collections import OrderedDict, Counter
from pathlib import Path

BASE = Path(__file__).resolve().parent

FULL_BLIND = (
    BASE
    / "reviewer_files"
    / "invariants-for-review.tsv"
)

FULL_KEYED = (
    BASE
    / "reviewer_files"
    / "invariants-for-review-with-tool.tsv"
)

OUTDIR = BASE / "reviewer_files"

BLIND_OUT = OUTDIR / "invariants-for-review-100.tsv"
KEYED_OUT = OUTDIR / "invariants-for-review-100-with-tool.tsv"

# Deterministic seed used only to choose method blocks
# from the already-created 358-row reviewer dataset.
METHOD_SELECTION_SEED = 47

# Target distribution. Total = 100.
# This keeps representation from all six projects.
PROJECT_TARGETS = {
    "dubbo": 12,
    "apollo": 18,
    "hudi": 22,
    "libgdx": 22,
    "netty": 14,
    "spring": 12,
}


def read_tsv(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def method_key(row):
    return (
        row["project"],
        row["class_name"],
        row["method_name"],
        row["parameters"],
    )


# ============================================================
# 1. Load full reviewer datasets
# ============================================================

blind = read_tsv(FULL_BLIND)
keyed = read_tsv(FULL_KEYED)

assert len(blind) == 358
assert len(keyed) == 358

for b, k in zip(blind, keyed):
    assert b["review_id"] == k["review_id"]
    assert b["invariant"] == k["invariant"]


# ============================================================
# 2. Group rows by method.
#
# Rows belonging to the same method are already contiguous.
# We keep or remove whole method blocks only.
# ============================================================

groups = OrderedDict()

for index, row in enumerate(keyed):
    key = method_key(row)

    groups.setdefault(
        key,
        []
    ).append((index, row))


# ============================================================
# 3. Mandatory methods.
#
# User requirement:
#   Do not remove any of the first 15 reviewer rows.
#
# INV-0015 belongs to a 2-row method block containing
# INV-0015 and INV-0016, so preserving whole methods means
# the mandatory portion contains 16 rows.
# ============================================================

mandatory = []
optional = []

for key, items in groups.items():

    original_positions = [
        index
        for index, _ in items
    ]

    # zero-based index < 15 means INV-0001 ... INV-0015
    if min(original_positions) < 15:
        mandatory.append(
            (key, items)
        )
    else:
        optional.append(
            (key, items)
        )


mandatory_counts = Counter()

for key, items in mandatory:
    mandatory_counts[key[0]] += len(items)


print(
    "Mandatory method blocks:",
    len(mandatory)
)

print(
    "Mandatory rows:",
    sum(len(items) for _, items in mandatory)
)


# ============================================================
# 4. Deterministically choose optional method blocks.
#
# Selection is by WHOLE METHOD.
#
# For each project, find an exact subset of method-block sizes
# that reaches the target number of rows for that project.
# ============================================================

rng = random.Random(
    METHOD_SELECTION_SEED
)


def choose_exact_subset(
    candidates,
    target,
):
    """
    Randomize candidate ordering deterministically, then use
    subset-sum dynamic programming to find whole method blocks
    whose row counts sum exactly to target.
    """

    candidates = list(candidates)
    rng.shuffle(candidates)

    dp = {
        0: []
    }

    for item in candidates:

        size = len(item[1])

        # Reverse order so an item is used at most once.
        existing = sorted(
            list(dp.keys()),
            reverse=True,
        )

        for total in existing:

            new_total = total + size

            if (
                new_total <= target
                and new_total not in dp
            ):
                dp[new_total] = (
                    dp[total]
                    + [item]
                )

        if target in dp:
            break

    if target not in dp:
        raise RuntimeError(
            f"Could not find exact method subset "
            f"for target={target}"
        )

    return dp[target]


selected_optional = []

for project, target_total in PROJECT_TARGETS.items():

    already = mandatory_counts[project]

    needed = target_total - already

    candidates = [
        item
        for item in optional
        if item[0][0] == project
    ]

    picked = choose_exact_subset(
        candidates,
        needed,
    )

    selected_optional.extend(
        picked
    )


selected_keys = {
    key
    for key, _ in (
        mandatory
        + selected_optional
    )
}


# ============================================================
# 5. Preserve ORIGINAL reviewer order.
#
# We do NOT reshuffle selected rows here.
#
# This guarantees:
# - INV-0001 ... INV-0015 stay exactly where they were
#   relative to one another;
# - rows from the same method remain contiguous;
# - the existing within-method OCA/Daikon randomization remains
#   unchanged.
# ============================================================

selected_keyed = [
    row
    for row in keyed
    if method_key(row)
    in selected_keys
]

selected_ids = {
    row["review_id"]
    for row in selected_keyed
}

selected_blind = [
    row
    for row in blind
    if row["review_id"]
    in selected_ids
]


# ============================================================
# 6. Sanity checks
# ============================================================

assert len(selected_keyed) == 100
assert len(selected_blind) == 100

# First 15 original reviewer IDs must remain.
for i in range(1, 16):

    review_id = f"INV-{i:04d}"

    assert review_id in selected_ids, (
        f"Required first-15 row missing: {review_id}"
    )


tool_counts = Counter(
    r["source_tool"]
    for r in selected_keyed
)

# Because every selected method was balanced in the original
# dataset, whole-method selection preserves global balance.
assert tool_counts == Counter({
    "OCA": 50,
    "DAIKON": 50,
}), tool_counts


project_counts = Counter(
    r["project"]
    for r in selected_keyed
)

assert project_counts == Counter(
    PROJECT_TARGETS
), project_counts


# Every selected method must remain contiguous.
positions = {}

for i, row in enumerate(
    selected_keyed
):

    key = method_key(row)

    positions.setdefault(
        key,
        []
    ).append(i)

for key, pos in positions.items():

    assert pos == list(
        range(
            min(pos),
            max(pos) + 1,
        )
    ), (
        "Non-contiguous method block: "
        + repr(key)
    )


# Each selected method remains balanced between tools.
per_method_tools = {}

for row in selected_keyed:

    key = method_key(row)

    per_method_tools.setdefault(
        key,
        Counter(),
    )[row["source_tool"]] += 1

for key, counts in per_method_tools.items():

    assert counts["OCA"] == counts["DAIKON"], (
        key,
        counts,
    )


# ============================================================
# 7. Write outputs
# ============================================================

blind_fields = [
    "review_id",
    "project",
    "class_name",
    "method_name",
    "parameters",
    "program_point",
    "invariant",
]

keyed_fields = [
    "review_id",
    "project",
    "class_name",
    "method_name",
    "parameters",
    "program_point",
    "invariant",
    "source_tool",
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

    for row in selected_blind:

        writer.writerow({
            field: row[field]
            for field in blind_fields
        })


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

    for row in selected_keyed:

        writer.writerow({
            field: row[field]
            for field in keyed_fields
        })


# ============================================================
# 8. Report selected method blocks
# ============================================================

print()
print("=" * 72)
print("100-INVARIANT REVIEW SAMPLE CREATED")
print("=" * 72)

print(
    "Total:",
    len(selected_keyed)
)

print(
    "OCA:",
    tool_counts["OCA"]
)

print(
    "Daikon:",
    tool_counts["DAIKON"]
)

print(
    "Selected methods:",
    len(positions)
)

print()
print(
    "Rows by project:",
    dict(project_counts),
)

print()
print("Selected method blocks:")

seen = set()

for row in selected_keyed:

    key = method_key(row)

    if key in seen:
        continue

    seen.add(key)

    block = [
        r
        for r in selected_keyed
        if method_key(r) == key
    ]

    print(
        f"{row['project']:7s} "
        f"{len(block):2d} rows  "
        f"{block[0]['review_id']} - "
        f"{block[-1]['review_id']}  "
        f"{row['class_name']}.{row['method_name']}"
    )


print()
print("Blind reviewer file:")
print(BLIND_OUT)

print()
print("Private keyed file:")
print(KEYED_OUT)
