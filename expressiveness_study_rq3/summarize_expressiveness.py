#!/usr/bin/env python3
"""Print Table 5 (section 5.2): expressiveness of the invariants held by Daikon and Oca.

N_D is the number of invariants Daikon reports, N_O the number of invariants Oca reports as held,
V>3 the held Oca invariants that relate more than three variables, and PSPM the held Oca invariants
that call at least one project-specific method. Total rows give macro-averaged percentages.

Usage:
  python3 summarize_expressiveness.py           Table 5
  python3 summarize_expressiveness.py --check   also compare every number with the paper
"""
import argparse
import csv
import gzip
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OCA_BENCHMARK_RESULTS = HERE.parent / "prompt_context_study_rq1_rq2" / "results" / "context" / "class_aware"
OCA_DEFECTS4J_RESULTS = HERE / "defects4j" / "results"

SUITES = [
    ("benchmark", "Benchmark projects (prompt/context study)", OCA_BENCHMARK_RESULTS,
     [("apollo", "Apollo"), ("dubbo", "Dubbo"), ("netty", "Netty"), ("hudi", "Hudi"), ("libgdx", "libGDX"),
      ("spring", "Spring")]),
    ("defects4j", "Defects4J projects (fixed versions)", OCA_DEFECTS4J_RESULTS,
     [("cli", "Cli"), ("codec", "Codec"), ("collections", "Collections"), ("gson", "Gson"), ("math", "Math")]),
]

PAPER = {
    "apollo": (59316, 1543, 53, 237), "dubbo": (19730, 9384, 378, 4091), "netty": (75756, 1021, 48, 215),
    "hudi": (312607, 332, 2, 6), "libgdx": (21101, 1819, 101, 329), "spring": (9590, 6419, 194, 2569),
    "cli": (6389, 1929, 87, 513), "codec": (45147, 4049, 257, 1231), "collections": (122046, 18549, 1071, 7975),
    "gson": (418757, 3426, 231, 1021), "math": (18789, 5522, 337, 1990),
}
PAPER_TOTALS = {
    "benchmark": (498100, 20518, 776, "4%", 7447, "23%"),
    "defects4j": (611128, 33475, 1983, "6%", 12730, "33%"),
}


def read_jsonl_gz(path):
    with gzip.open(path, "rt") as f:
        return [json.loads(line) for line in f if line.strip()]


def oca_metrics(results, project):
    held = {o["id"] for o in read_jsonl_gz(results / project / "outcomes.jsonl.gz") if o["verdict"] == "HELD"}
    rows = [m for m in read_jsonl_gz(results / project / "invariant_metrics.jsonl.gz") if m["id"] in held]
    return len(rows), sum(m["varCount2"] > 3 for m in rows), sum(m["pspmCount"] > 0 for m in rows)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="compare every number with the paper")
    args = ap.parse_args()

    with open(HERE / "daikon_counts.csv") as f:
        daikon = {r["project"]: r for r in csv.DictReader(f)}

    ours, totals = {}, {}
    print("Table 5: Expressiveness results")
    print(f"  {'Project':<14}{'N_D':>10}{'N_O':>9}{'V>3':>13}{'PSPM':>15}")
    for suite, title, results, projects in SUITES:
        projects = [(p, name) for p, name in projects if (results / p).is_dir()]
        if not projects:
            continue
        print(f"  {title}")
        v_pct, p_pct = [], []
        for p, name in projects:
            n_d = int(daikon[p]["n_d"])
            n_o, v3, pspm = oca_metrics(results, p)
            ours[p] = (n_d, n_o, v3, pspm)
            v_pct.append(v3 / n_o)
            p_pct.append(pspm / n_o)
            mark = "†" if daikon[p]["trace"] == "sampled" else ""
            print(f"  {name + mark:<14}{n_d:>10,}{n_o:>9,}{f'{v3:,} ({v3 / n_o:.0%})':>13}{f'{pspm:,} ({pspm / n_o:.0%})':>15}")
        t = [sum(ours[p][i] for p, _ in projects) for i in range(4)]
        vm, pm = f"{sum(v_pct) / len(v_pct):.0%}", f"{sum(p_pct) / len(p_pct):.0%}"
        totals[suite] = (t[0], t[1], t[2], vm, t[3], pm)
        print(f"  {'Total':<14}{t[0]:>10,}{t[1]:>9,}{f'{t[2]:,} ({vm})':>13}{f'{t[3]:,} ({pm})':>15}")
    print("  † Daikon ran on a sampled trace (-sample-start=5).")

    if args.check:
        bad = [(p, PAPER[p], v) for p, v in ours.items() if PAPER[p] != v]
        bad += [(s, PAPER_TOTALS[s], v) for s, v in totals.items() if PAPER_TOTALS[s] != v]
        print()
        if bad:
            for key, paper, got in bad:
                print(f"MISMATCH {key}: paper {paper}, artifact {got}")
            sys.exit(1)
        print(f"All {len(ours) + len(totals)} rows match the paper.")


if __name__ == "__main__":
    main()
