#!/usr/bin/env python3

import argparse
import csv
import json
import random
import re
from pathlib import Path
from collections import defaultdict


BASE = Path(__file__).resolve().parent

OCA_BASE = BASE / "resultsOfContextStudyFewshot/class_doc"

SELECTED_METHODS = (
    BASE
    / "oca_daikon_matched_samples"
    / "selected-methods.tsv"
)

DAIKON_FILES = {
    "apollo":
        BASE / "apollo-daikon-out/apollo-invariants.txt",

    "hudi":
        BASE / "hudi-daikon-out/hudi-invariants.txt",

    "spring":
        BASE / "spring-daikon-out/spring-invariants.txt",

    "libgdx":
        BASE / "libgdx-s5-daikon-out/libgdx-s5-invariants.txt",

    "dubbo":
        BASE
        / "dubbo-s5-daikon-quickfix-out"
        / "dubbo-s5-quickfix-invariants.txt",

    "netty":
        BASE
        / "netty-s5-daikon-quickfix-out"
        / "netty-s5-quickfix-invariants.txt",
}


# ============================================================
# JSONL
# ============================================================

def read_jsonl(path):
    records = []

    with open(
        path,
        "r",
        encoding="utf-8",
        errors="replace",
    ) as f:

        for lineno, line in enumerate(f, 1):

            line = line.rstrip("\n")

            if not line.strip():
                continue

            try:
                records.append(
                    json.loads(
                        line,
                        strict=False,
                    )
                )

            except Exception as e:
                print(
                    f"WARNING: could not parse "
                    f"{path}:{lineno}: {e}"
                )

    return records


# ============================================================
# LOAD FIXED 60 METHODS
# ============================================================

def load_selected_methods(path):

    rows = []

    with open(
        path,
        "r",
        encoding="utf-8",
        errors="replace",
        newline="",
    ) as f:

        reader = csv.DictReader(
            f,
            delimiter="\t",
        )

        for row in reader:

            rows.append({
                "project":
                    row["project"],

                "sample_index":
                    int(row["sample_index"]),

                "oca_method":
                    row["oca_method"],

                "daikon_method":
                    row["daikon_method"],
            })

    return rows


# ============================================================
# LOAD OCA OBSERVED-HELD INVARIANTS
# ============================================================

def load_oca_held(project):

    project_dir = (
        OCA_BASE / project
    )

    registry_path = (
        project_dir
        / "daikonpp_registry.jsonl"
    )

    outcomes_path = (
        project_dir
        / "daikonpp_outcomes.jsonl"
    )

    registry = {}

    for x in read_jsonl(
        registry_path
    ):
        if "id" in x:
            registry[x["id"]] = x

    held_by_method = defaultdict(list)

    for outcome in read_jsonl(
        outcomes_path
    ):

        if not (
            outcome.get("verdict") == "HELD"
            and outcome.get("compiled") is True
            and outcome.get("executed") is True
        ):
            continue

        inv_id = outcome.get("id")

        metadata = registry.get(
            inv_id
        )

        if metadata is None:
            continue

        element = metadata.get(
            "element"
        )

        if not element:
            continue

        held_by_method[
            element
        ].append({
            "id":
                inv_id,

            "kind":
                metadata.get("kind"),

            "expr":
                metadata.get("expr"),

            "rationale":
                metadata.get("rationale"),

            "file":
                metadata.get("file"),
        })

    return dict(
        held_by_method
    )


# ============================================================
# LOAD DAIKON INVARIANTS
# ============================================================

def is_method_program_point(
    program_point
):
    if ":::" not in program_point:
        return False

    suffix = program_point.split(
        ":::",
        1,
    )[1]

    return (
        suffix == "ENTER"
        or suffix.startswith("EXIT")
    )


def parse_daikon_file(path):
    """
    Returns:

      {
        method_signature: [
          {
            "program_point": "...:::ENTER",
            "expr": "x != null"
          },
          {
            "program_point": "...:::EXIT",
            "expr": "return != null"
          },
          ...
        ]
      }

    Important:
    Program-point headers themselves are NOT counted
    as invariants.

    Empty EXIT/ENTER blocks contribute zero invariants.
    """

    with open(
        path,
        "r",
        encoding="utf-8",
        errors="replace",
    ) as f:
        text = f.read()

    blocks = re.split(
        r"^={20,}\s*$",
        text,
        flags=re.MULTILINE,
    )

    by_method = defaultdict(list)

    for block in blocks:

        block = block.strip()

        if not block:
            continue

        lines = [
            x.strip()
            for x in block.splitlines()
        ]

        if not lines:
            continue

        program_point = lines[0]

        if not is_method_program_point(
            program_point
        ):
            continue

        method = program_point.split(
            ":::",
            1,
        )[0]

        # Every non-empty line after the
        # program-point header is an invariant.
        for expr in lines[1:]:

            expr = expr.strip()

            if not expr:
                continue

            by_method[
                method
            ].append({
                "program_point":
                    program_point,

                "expr":
                    expr,
            })

    return dict(
        by_method
    )


# ============================================================
# SAMPLING
# ============================================================

def sample_balanced(
    rng,
    oca_invariants,
    daikon_invariants,
):

    oca_count = len(
        oca_invariants
    )

    daikon_count = len(
        daikon_invariants
    )

    k = min(
        oca_count,
        daikon_count,
    )

    if k == 0:

        return (
            [],
            [],
            0,
        )

    if oca_count == k:
        selected_oca = list(
            oca_invariants
        )
    else:
        selected_oca = rng.sample(
            oca_invariants,
            k,
        )

    if daikon_count == k:
        selected_daikon = list(
            daikon_invariants
        )
    else:
        selected_daikon = rng.sample(
            daikon_invariants,
            k,
        )

    return (
        selected_oca,
        selected_daikon,
        k,
    )


# ============================================================
# RENDER
# ============================================================

def render_method(
    row,
    oca_all,
    daikon_all,
    oca_sample,
    daikon_sample,
    k,
):

    out = []

    out.append(
        "=" * 110
    )

    out.append(
        f"PROJECT: {row['project']}"
    )

    out.append(
        f"SAMPLE INDEX: {row['sample_index']}/10"
    )

    out.append("")

    out.append(
        f"OCA METHOD: {row['oca_method']}"
    )

    out.append(
        f"DAIKON METHOD: {row['daikon_method']}"
    )

    out.append("")

    out.append(
        f"OCA ORIGINAL OBSERVED-HELD COUNT: "
        f"{len(oca_all)}"
    )

    out.append(
        f"DAIKON ORIGINAL INVARIANT COUNT: "
        f"{len(daikon_all)}"
    )

    out.append(
        f"BALANCED COUNT PER TOOL: {k}"
    )

    out.append("")

    out.append(
        "-" * 110
    )

    out.append(
        f"OCA SAMPLED OBSERVED-HELD INVARIANTS ({k})"
    )

    out.append(
        "-" * 110
    )

    for i, inv in enumerate(
        oca_sample,
        1,
    ):

        out.append(
            f"OCA {i}/{k}"
        )

        out.append(
            f"PROGRAM POINT: "
            f"{inv.get('kind')}"
        )

        out.append(
            f"EXPR: "
            f"{inv.get('expr')}"
        )

        out.append(
            f"ID: "
            f"{inv.get('id')}"
        )

        if inv.get(
            "rationale"
        ):
            out.append(
                f"RATIONALE: "
                f"{inv['rationale']}"
            )

        if inv.get(
            "file"
        ):
            out.append(
                f"SOURCE FILE: "
                f"{inv['file']}"
            )

        out.append("")

    out.append(
        "-" * 110
    )

    out.append(
        f"DAIKON SAMPLED INVARIANTS ({k})"
    )

    out.append(
        "-" * 110
    )

    for i, inv in enumerate(
        daikon_sample,
        1,
    ):

        out.append(
            f"DAIKON {i}/{k}"
        )

        out.append(
            f"PROGRAM POINT: "
            f"{inv['program_point']}"
        )

        out.append(
            f"EXPR: "
            f"{inv['expr']}"
        )

        out.append("")

    out.append("")

    return "\n".join(out)


# ============================================================
# MAIN
# ============================================================

def main():

    parser = argparse.ArgumentParser(
        description=(
            "Balance OCA and Daikon invariant counts "
            "for the already-selected 60 methods."
        )
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=43,
        help=(
            "Invariant-sampling random seed "
            "(default: 43)"
        ),
    )

    parser.add_argument(
        "--output-dir",
        default=(
            "oca_daikon_balanced_invariants"
        ),
    )

    args = parser.parse_args()

    rng = random.Random(
        args.seed
    )

    output_dir = Path(
        args.output_dir
    )

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    selected_methods = (
        load_selected_methods(
            SELECTED_METHODS
        )
    )

    print(
        f"Loaded fixed selected methods: "
        f"{len(selected_methods)}"
    )

    if len(
        selected_methods
    ) != 60:

        print(
            "WARNING: expected 60 selected "
            f"methods, found "
            f"{len(selected_methods)}"
        )

    # Cache project-level raw data.
    oca_cache = {}
    daikon_cache = {}

    combined_output = []

    manifest_rows = []

    zero_rows = []

    totals = defaultdict(
        lambda: {
            "methods": 0,
            "oca_original": 0,
            "daikon_original": 0,
            "balanced_each": 0,
        }
    )

    for project in sorted(
        set(
            x["project"]
            for x in selected_methods
        )
    ):

        print()
        print(
            f"Loading project: {project}"
        )

        oca_cache[
            project
        ] = load_oca_held(
            project
        )

        daikon_cache[
            project
        ] = parse_daikon_file(
            DAIKON_FILES[
                project
            ]
        )

        print(
            f"  OCA methods with HELD: "
            f"{len(oca_cache[project])}"
        )

        print(
            f"  Daikon methods parsed: "
            f"{len(daikon_cache[project])}"
        )

    # Preserve original selected-method ordering.
    for row in selected_methods:

        project = row[
            "project"
        ]

        oca_method = row[
            "oca_method"
        ]

        daikon_method = row[
            "daikon_method"
        ]

        oca_all = (
            oca_cache[
                project
            ].get(
                oca_method,
                [],
            )
        )

        daikon_all = (
            daikon_cache[
                project
            ].get(
                daikon_method,
                [],
            )
        )

        (
            oca_sample,
            daikon_sample,
            k,
        ) = sample_balanced(
            rng,
            oca_all,
            daikon_all,
        )

        rendered = render_method(
            row,
            oca_all,
            daikon_all,
            oca_sample,
            daikon_sample,
            k,
        )

        combined_output.append(
            rendered
        )

        manifest_rows.append({
            "project":
                project,

            "sample_index":
                row["sample_index"],

            "oca_method":
                oca_method,

            "daikon_method":
                daikon_method,

            "oca_original_count":
                len(oca_all),

            "daikon_original_count":
                len(daikon_all),

            "balanced_count_each":
                k,

            "total_balanced_invariants":
                2 * k,
        })

        totals[
            project
        ]["methods"] += 1

        totals[
            project
        ]["oca_original"] += (
            len(oca_all)
        )

        totals[
            project
        ]["daikon_original"] += (
            len(daikon_all)
        )

        totals[
            project
        ]["balanced_each"] += k

        if k == 0:

            zero_rows.append({
                "project":
                    project,

                "sample_index":
                    row[
                        "sample_index"
                    ],

                "oca_method":
                    oca_method,

                "daikon_method":
                    daikon_method,

                "oca_count":
                    len(oca_all),

                "daikon_count":
                    len(daikon_all),
            })

    # ========================================================
    # COMBINED HUMAN-READABLE FILE
    # ========================================================

    combined_file = (
        output_dir
        / "all-projects-balanced-invariants.txt"
    )

    combined_file.write_text(
        "\n".join(
            combined_output
        )
        + "\n",
        encoding="utf-8",
    )

    # ========================================================
    # MANIFEST
    # ========================================================

    manifest_file = (
        output_dir
        / "balanced-invariant-manifest.tsv"
    )

    with open(
        manifest_file,
        "w",
        encoding="utf-8",
        newline="",
    ) as f:

        writer = csv.writer(
            f,
            delimiter="\t",
            lineterminator="\n",
        )

        writer.writerow([
            "project",
            "sample_index",
            "oca_method",
            "daikon_method",
            "oca_original_count",
            "daikon_original_count",
            "balanced_count_each",
            "total_balanced_invariants",
        ])

        for r in manifest_rows:

            writer.writerow([
                r["project"],
                r["sample_index"],
                r["oca_method"],
                r["daikon_method"],
                r["oca_original_count"],
                r["daikon_original_count"],
                r["balanced_count_each"],
                r["total_balanced_invariants"],
            ])

    # ========================================================
    # MACHINE-READABLE SAMPLED INVARIANTS
    # ========================================================

    jsonl_file = (
        output_dir
        / "balanced-invariants.jsonl"
    )

    # Re-run deterministic selection with the same RNG sequence
    # by resetting the RNG and traversing methods identically.
    rng_json = random.Random(
        args.seed
    )

    with open(
        jsonl_file,
        "w",
        encoding="utf-8",
    ) as f:

        for row in selected_methods:

            project = row[
                "project"
            ]

            oca_all = (
                oca_cache[
                    project
                ][
                    row["oca_method"]
                ]
            )

            daikon_all = (
                daikon_cache[
                    project
                ][
                    row["daikon_method"]
                ]
            )

            (
                oca_sample,
                daikon_sample,
                k,
            ) = sample_balanced(
                rng_json,
                oca_all,
                daikon_all,
            )

            record = {
                "project":
                    project,

                "sample_index":
                    row[
                        "sample_index"
                    ],

                "oca_method":
                    row[
                        "oca_method"
                    ],

                "daikon_method":
                    row[
                        "daikon_method"
                    ],

                "oca_original_count":
                    len(oca_all),

                "daikon_original_count":
                    len(daikon_all),

                "balanced_count_each":
                    k,

                "oca_sample":
                    oca_sample,

                "daikon_sample":
                    daikon_sample,
            }

            f.write(
                json.dumps(
                    record,
                    ensure_ascii=False,
                )
                + "\n"
            )

    # ========================================================
    # PROJECT SUMMARY
    # ========================================================

    summary_file = (
        output_dir
        / "balanced-summary.tsv"
    )

    with open(
        summary_file,
        "w",
        encoding="utf-8",
        newline="",
    ) as f:

        writer = csv.writer(
            f,
            delimiter="\t",
            lineterminator="\n",
        )

        writer.writerow([
            "project",
            "methods",
            "oca_original_invariants",
            "daikon_original_invariants",
            "balanced_oca_invariants",
            "balanced_daikon_invariants",
            "balanced_total",
        ])

        for project in sorted(
            totals
        ):

            x = totals[
                project
            ]

            writer.writerow([
                project,
                x["methods"],
                x["oca_original"],
                x["daikon_original"],
                x["balanced_each"],
                x["balanced_each"],
                2 * x["balanced_each"],
            ])

    # ========================================================
    # ZERO-BALANCE CASES
    # ========================================================

    zero_file = (
        output_dir
        / "zero-balanced-methods.tsv"
    )

    with open(
        zero_file,
        "w",
        encoding="utf-8",
        newline="",
    ) as f:

        writer = csv.writer(
            f,
            delimiter="\t",
            lineterminator="\n",
        )

        writer.writerow([
            "project",
            "sample_index",
            "oca_method",
            "daikon_method",
            "oca_count",
            "daikon_count",
        ])

        for r in zero_rows:

            writer.writerow([
                r["project"],
                r["sample_index"],
                r["oca_method"],
                r["daikon_method"],
                r["oca_count"],
                r["daikon_count"],
            ])

    print()
    print("=" * 80)
    print("DONE")
    print("=" * 80)

    print(
        f"Fixed methods processed: "
        f"{len(selected_methods)}"
    )

    print(
        f"Methods with balanced count 0: "
        f"{len(zero_rows)}"
    )

    print()
    print(
        f"Human-readable output: "
        f"{combined_file}"
    )

    print(
        f"Balanced manifest: "
        f"{manifest_file}"
    )

    print(
        f"Machine-readable sample: "
        f"{jsonl_file}"
    )

    print(
        f"Project summary: "
        f"{summary_file}"
    )

    print(
        f"Zero-count cases: "
        f"{zero_file}"
    )


if __name__ == "__main__":
    main()
