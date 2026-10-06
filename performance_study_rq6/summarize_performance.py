#!/usr/bin/env python3
"""Print Table 8 (section 5.5): time and disk usage of Daikon and Oca per project.

Usage:
  python3 summarize_performance.py           Table 8
  python3 summarize_performance.py --check   also compare the totals with the paper
"""
import argparse
import csv
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SUITES = [("benchmark", "Benchmark projects (prompt/context study)"), ("defects4j", "Defects4J projects (fixed versions)")]
COLUMNS = ["daikon_min", "oca_min", "daikon_gb", "oca_gb"]

PAPER = {
    "benchmark": {"daikon_min": 1961.6, "oca_min": 389.4, "daikon_gb": 780.49, "oca_gb": 26.32},
    "defects4j": {"daikon_min": 855.0, "oca_min": 176.2, "daikon_gb": 46.60, "oca_gb": 0.30},
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="compare the totals with the paper")
    args = ap.parse_args()

    with open(HERE / "table8.csv") as f:
        rows = list(csv.DictReader(f))

    print("Table 8: Time and disk usage per project")
    print(f"  {'':<16}{'Time [min]':>20}{'Disk [GB]':>22}")
    print(f"  {'Project':<16}{'Daikon':>10}{'Oca':>10}{'Daikon':>12}{'Oca':>10}")
    totals = {}
    for suite, title in SUITES:
        print(f"  {title}")
        sel = [r for r in rows if r["suite"] == suite]
        for r in sel:
            mark = "†" if r["daikon_trace"] == "sampled" else ""
            print(f"  {r['project'] + mark:<16}{float(r['daikon_min']):>10,.1f}{float(r['oca_min']):>10,.1f}"
                  f"{float(r['daikon_gb']):>12,.2f}{float(r['oca_gb']):>10,.2f}")
            if r["daikon_full_failed_gb"]:
                star = "*" if r["daikon_full_failed_partial"] == "yes" else ""
                print(f"  {'  full (failed)':<16}{'–':>10}{'–':>10}{float(r['daikon_full_failed_gb']):>11,.2f}{star:<1}{'–':>10}")
        totals[suite] = {c: round(sum(float(r[c]) for r in sel), 2) for c in COLUMNS}
        t = totals[suite]
        print(f"  {'Total':<16}{t['daikon_min']:>10,.1f}{t['oca_min']:>10,.1f}{t['daikon_gb']:>12,.2f}{t['oca_gb']:>10,.2f}")
    print("  † Daikon ran on a sampled trace; the full (failed) row gives the size of the full-trace attempt,")
    print("    excluded from the totals. * Partial trace at the 72-hour limit.")

    if args.check:
        bad = [(s, c, v, totals[s][c]) for s, cols in PAPER.items() for c, v in cols.items() if totals[s][c] != v]
        print()
        if bad:
            for s, c, paper, got in bad:
                print(f"MISMATCH {s} {c}: paper {paper}, artifact {got}")
            sys.exit(1)
        print(f"All {sum(len(c) for c in PAPER.values())} totals match the paper.")


if __name__ == "__main__":
    main()
