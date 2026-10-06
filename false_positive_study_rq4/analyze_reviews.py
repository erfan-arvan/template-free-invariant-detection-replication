#!/usr/bin/env python3
"""Reproduce the RQ4 false-positive analysis (section 5.3, Table 6) from the review spreadsheet.

Each row is one sampled invariant with two independent verdicts and a final verdict:
T = semantically valid, F = false positive.

Usage:
  python3 analyze_reviews.py                   Table 6, sample, agreement, and Cohen's kappa
  python3 analyze_reviews.py --disagreements   also list the invariants the reviewers disagreed on
  python3 analyze_reviews.py --check           also compare every number with the paper
"""
import argparse
import sys
from collections import Counter
from pathlib import Path

import openpyxl

XLSX = Path(__file__).resolve().parent / "combined-invariant-reviews-all-100-final.xlsx"
TOOLS = [("OCA", "Oca"), ("DAIKON", "Daikon")]

PAPER = {
    "sampled invariants": 100, "distinct methods": 19,
    "Oca false positives": 9, "Oca valid": 41, "Daikon false positives": 38, "Daikon valid": 12,
    "agreements": 89, "disagreements": 11, "kappa": 0.780,
}


def load(xlsx):
    ws = openpyxl.load_workbook(xlsx, read_only=True, data_only=True).worksheets[0]
    it = ws.iter_rows(values_only=True)
    header = [str(h).strip() if h is not None else None for h in next(it)]
    return [{h: v for h, v in zip(header, r) if h} for r in it if r and r[0]]


def definite(verdict):
    """T or F; None for a missing or uncertain verdict (e.g. "T?", "F?", "?")."""
    v = str(verdict or "").strip()
    return v if v in ("T", "F") else None


def reviewer_pair(row):
    """The two reviewers' verdicts. A reviewer who gave no definite verdict defers to the other one."""
    r1, r2 = definite(row["Reviewer1 Verdict"]), definite(row["Reviewer2 Verdict"])
    return r1 or r2, r2 or r1


def cohen_kappa(pairs):
    n = len(pairs)
    observed = sum(a == b for a, b in pairs) / n
    first, second = Counter(a for a, _ in pairs), Counter(b for _, b in pairs)
    expected = sum(first[k] * second[k] for k in set(first) | set(second)) / n / n
    return (observed - expected) / (1 - expected)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--xlsx", type=Path, default=XLSX)
    ap.add_argument("--disagreements", action="store_true", help="list the invariants the reviewers disagreed on")
    ap.add_argument("--check", action="store_true", help="compare every number with the paper")
    args = ap.parse_args()

    rows = load(args.xlsx)
    ours = {"sampled invariants": len(rows),
            "distinct methods": len({r["method_signature"] for r in rows})}

    print(f"Sample: {len(rows)} invariants from {ours['distinct methods']} distinct methods")
    projects = sorted({r["project"] for r in rows})
    print(f"  {'Project':<10}" + "".join(f"{name:>8}" for _, name in TOOLS))
    for p in projects:
        print(f"  {p:<10}" + "".join(f"{sum(r['project'] == p and r['source_tool'] == t for r in rows):>8}"
                                     for t, _ in TOOLS))
    print()

    print("Table 6: False-positive analysis of the manually inspected sample (RQ4)")
    print(f"  {'Tool':<8}{'False pos.':>11}{'Valid':>7}{'Total':>7}{'Rate':>7}")
    for tool, name in TOOLS:
        final = Counter(definite(r["Final Verdict"]) for r in rows if r["source_tool"] == tool)
        total = sum(final.values())
        if set(final) - {"T", "F"}:
            sys.exit(f"{name}: rows without a definite final verdict")
        print(f"  {name:<8}{final['F']:>11}{final['T']:>7}{total:>7}{final['F'] / total:>7.0%}")
        ours[f"{name} false positives"], ours[f"{name} valid"] = final["F"], final["T"]
    print()

    pairs = [reviewer_pair(r) for r in rows]
    if any(a is None for a, _ in pairs):
        sys.exit("an invariant has no definite verdict from either reviewer")
    agree = sum(a == b for a, b in pairs)
    ours.update({"agreements": agree, "disagreements": len(pairs) - agree,
                 "kappa": round(cohen_kappa(pairs), 3)})
    print("Inter-rater agreement (before resolution)")
    print(f"  agreed:    {agree} ({agree / len(pairs):.0%})")
    print(f"  disagreed: {len(pairs) - agree} ({(len(pairs) - agree) / len(pairs):.0%}), resolved by a third author")
    print(f"  Cohen's kappa: {ours['kappa']:.3f}")

    if args.disagreements:
        print()
        print("Disagreements (Reviewer1 / Reviewer2 -> final)")
        for r, (a, b) in zip(rows, pairs):
            if a != b:
                print(f"  {r['review_id']}  {r['source_tool']:<6} {a} / {b} -> {definite(r['Final Verdict'])}  "
                      f"{r['program_point']} {r['class_name']}.{r['method_name']}: {r['invariant']}")

    if args.check:
        bad = [(k, v, ours.get(k)) for k, v in PAPER.items() if ours.get(k) != v]
        print()
        if bad:
            for k, paper, got in bad:
                print(f"MISMATCH {k}: paper {paper}, spreadsheet {got}")
            sys.exit(1)
        print(f"All {len(PAPER)} numbers match the paper.")


if __name__ == "__main__":
    main()
