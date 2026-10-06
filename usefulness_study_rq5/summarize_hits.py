#!/usr/bin/env python3
"""Print the RQ5 table of exposed bugs (section 5.4, Table 7) and the invariants that expose them.

Usage:
  python3 summarize_hits.py           Table 7
  python3 summarize_hits.py --hits    also list the invariants that expose each bug
  python3 summarize_hits.py --check   also compare every number with the paper
"""
import argparse
import csv
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = ["Oca", "Daikon"]

PAPER = {
    ("Cli", "Oca"): 0, ("Codec", "Oca"): 2, ("Collections", "Oca"): 5, ("Gson", "Oca"): 1, ("Math", "Oca"): 1,
    ("Cli", "Daikon"): 0, ("Codec", "Daikon"): 1, ("Collections", "Daikon"): 1, ("Gson", "Daikon"): 0,
    ("Math", "Daikon"): 2,
    ("Total", "Oca"): 9, ("Total", "Daikon"): 4, ("Total", "bugs"): 25,
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hits", action="store_true", help="list the invariants that expose each bug")
    ap.add_argument("--check", action="store_true", help="compare every number with the paper")
    args = ap.parse_args()

    with open(HERE / "exposed.csv") as f:
        table = list(csv.DictReader(f))

    ours = {}
    n_bugs = sum(int(r["bugs"]) for r in table)
    print("Table 7: Bugs exposed per project (RQ5)")
    print(f"  {'Project':<12}{'Bugs':>5}" + "".join(f"{t:>10}" for t in TOOLS))
    for r in table:
        print(f"  {r['project']:<12}{r['bugs']:>5}" + "".join(f"{r[t]:>10}" for t in TOOLS))
        for t in TOOLS:
            ours[r["project"], t] = int(r[t])
    totals = {t: sum(int(r[t]) for r in table) for t in TOOLS}
    print(f"  {'Total':<12}{n_bugs:>5}" + "".join(f"{f'{totals[t]} ({totals[t] / n_bugs:.0%})':>10}" for t in TOOLS))
    ours["Total", "bugs"] = n_bugs
    for t in TOOLS:
        ours["Total", t] = totals[t]

    if args.hits:
        with open(HERE / "hits.csv") as f:
            hits = list(csv.DictReader(f))
        for t in TOOLS:
            print(f"\n{t} hits")
            for h in hits:
                if h["tool"] == t:
                    print(f"  {h['bug']:<16}{h['program_point']:<6} {h['method']}: {h['invariant']}")

    if args.check:
        bad = [(k, v, ours.get(k)) for k, v in PAPER.items() if ours.get(k) != v]
        print()
        if bad:
            for (row, col), paper, got in bad:
                print(f"MISMATCH {row} {col}: paper {paper}, artifact {got}")
            sys.exit(1)
        print(f"All {len(PAPER)} numbers match the paper.")


if __name__ == "__main__":
    main()
