#!/usr/bin/env python3
"""Print Table 2 (held invariants by prompt strategy) and Table 4 (held invariants by context configuration).

Usage:
  python3 summarize_studies.py           Tables 2 and 4
  python3 summarize_studies.py --check   also compare every number with the paper
"""
import argparse
import csv
import gzip
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESULTS = HERE / "results"
PROJECTS = ["apollo", "dubbo", "hudi", "libgdx", "netty", "spring"]
HEADERS = ["Apollo", "Dubbo", "Hudi", "libGDX", "Netty", "Spring"]

STRATEGIES = [
    ("baseline", "Zero-Shot (baseline)"),
    ("fewshot", "Few-Shot"),
    ("cot", "Chain-of-Thought"),
    ("stepwise", "Stepwise"),
    ("self_refine", "Self-Refinement"),
    ("multi_sample", "Multi-Sample"),
]
CONFIGURATIONS = [
    ("local", "Local (baseline)"),
    ("usage_aware", "Usage-Aware"),
    ("class_aware", "Class-Aware"),
    ("documented", "Documented"),
    ("type_aware", "Type-Aware"),
    ("example_driven", "Example-Driven"),
]

PAPER_TABLE2 = {
    "baseline": [1515, 8119, 316, 711, 1045, 5937],
    "fewshot": [1396, 9017, 257, 1673, 909, 6021],
    "cot": [1404, 8256, 561, 635, 837, 5219],
    "stepwise": [1378, 8328, 580, 672, 453, 4973],
    "self_refine": [1169, 7584, 549, 1624, 1095, 4670],
    "multi_sample": [638, 3972, 271, 978, 440, 2355],
}
PAPER_TABLE4 = {
    "local": [1396, 9017, 257, 1673, 909, 6021],
    "usage_aware": [1554, 9414, 255, 941, 824, 6173],
    "class_aware": [1543, 9384, 332, 1819, 1021, 6419],
    "documented": [1401, 9045, 262, 577, 880, 6230],
    "type_aware": [1396, 9067, 257, 751, 908, 6038],
    "example_driven": [1548, 8868, 333, 1046, 872, 6137],
}


def summaries():
    with open(RESULTS / "run_summaries.csv") as f:
        return {(r["study"], r["configuration"], r["project"]): int(r["observed_held"]) for r in csv.DictReader(f)}


def held_in_outcomes(study, configuration, project):
    with gzip.open(RESULTS / study / configuration / project / "outcomes.jsonl.gz", "rt") as f:
        return sum(1 for line in f if line.strip() and json.loads(line)["verdict"] == "HELD")


def table2(summary):
    return {s: [summary["prompt", s, p] for p in PROJECTS] for s, _ in STRATEGIES}


def table4(summary):
    rows = {}
    for c, _ in CONFIGURATIONS:
        if c == "local":
            rows[c] = [summary["prompt", "fewshot", p] for p in PROJECTS]
        elif c == "class_aware":
            rows[c] = [held_in_outcomes("context", c, p) for p in PROJECTS]
        else:
            rows[c] = [summary["context", c, p] for p in PROJECTS]
    return rows


def print_table(title, labels, rows):
    print(title)
    print(f"  {'':<22}" + "".join(f"{h:>8}" for h in HEADERS) + f"{'Total':>9}")
    for key, label in labels:
        print(f"  {label:<22}" + "".join(f"{v:>8,}" for v in rows[key]) + f"{sum(rows[key]):>9,}")
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="compare every number with the paper")
    args = ap.parse_args()

    summary = summaries()
    t2, t4 = table2(summary), table4(summary)
    print_table("Table 2: Held invariants by prompt strategy (Local context)", STRATEGIES, t2)
    print_table("Table 4: Held invariants by context configuration (Few-Shot prompt strategy)", CONFIGURATIONS, t4)

    if args.check:
        bad = []
        for name, ours, paper in [("Table 2", t2, PAPER_TABLE2), ("Table 4", t4, PAPER_TABLE4)]:
            for key, values in paper.items():
                for project, got, want in zip(HEADERS, ours[key], values):
                    if got != want:
                        bad.append((name, key, project, want, got))
        if bad:
            for name, key, project, want, got in bad:
                print(f"MISMATCH {name} {key} {project}: paper {want}, artifact {got}")
            sys.exit(1)
        print(f"All {12 * len(HEADERS)} cells match the paper.")


if __name__ == "__main__":
    main()
