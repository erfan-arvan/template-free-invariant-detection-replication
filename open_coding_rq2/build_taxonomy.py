#!/usr/bin/env python3
"""Rebuild the context taxonomy tree of Fig. 3 and its counts from the open-coding spreadsheet.

Every count is the number of coded papers that use the node's code or any code below it,
so a paper with several codes in one family counts once for that family.

Usage:
  python3 build_taxonomy.py            # tree as printed in the paper (HIST and SEM collapsed)
  python3 build_taxonomy.py --full     # also list the HIST and SEM subcodes
  python3 build_taxonomy.py --check    # also compare every number with the paper; exit 1 on mismatch
"""
import argparse
import re
import sys
from pathlib import Path

import openpyxl

XLSX = Path(__file__).resolve().parent / "papers_screened_open_coding.xlsx"

# (code, label, description, children, collapsed in the paper)
TREE = [
    ("LC", "Local Code Context (LC)", "Program code given directly to the model.", [
        ("LC-SUBSRC", "partial function code", []),
        ("LC-FUNC", "whole function or method", []),
        ("LC-STRUCT", "class, module, or file", []),
        ("LC-IR", "AST, bytecode, or IR", []),
    ], False),
    ("SE", "Structural Expansion Context (SE)", "Context derived from program analysis.", [
        ("SE-ANALYSIS", "static analysis, types", []),
        ("SE-GRAPH", "dependency graphs", []),
    ], False),
    ("DOC/RET", "Documentation & Retrieval Context (DOC/RET)", "Non-code artifacts or retrieved knowledge.", [
        ("DOC-NL", "natural-language docs", []),
        ("DOC-SPEC", "specs, APIs, standards", []),
        ("RET-CODE", "code from repositories", []),
        ("RET-KB", "curated knowledge bases", []),
    ], False),
    ("HIST", "Historical/Temporal Context (HIST)", "Software evolution and development history.", [
        ("HIST-CHANGE", "code evolution: diffs, patches, past fixes", []),
        ("HIST-DEV", "development activity: issues, PRs, edit history", []),
        ("HIST-INTERACT", "prior user-LLM interaction rounds", []),
    ], True),
    ("SEM", "Semantic Context (SEM)", "Abstractions capturing meaning or intent.", [
        ("SEM-ABSTRACT", "semantic summaries, abstractions", []),
        ("SEM-INTENT", "task or developer goals", []),
        ("SEM-EXPLANATION", "reasoning traces, explanations", []),
        ("SEM-FEEDBACK", "evaluation or correction signals", []),
    ], True),
    ("TEST", "Testing & Execution Context (TEST)", "Artifacts from program execution or testing.", [
        ("TEST-EXEC", "failures, traces, tests", [
            ("TEST-RENDER", "rendered UI", []),
        ]),
        ("TEST-IO", "input/output pairs", []),
        ("TEST-CODE", "existing test suites", []),
    ], False),
]

# Numbers reported in the paper (section 3.3.1 and Fig. 3).
PAPER = {
    "search results": 332, "candidate papers": 184, "not codable": 3, "coded papers": 181,
    "LC": 155, "LC-SUBSRC": 73, "LC-FUNC": 76, "LC-STRUCT": 43, "LC-IR": 4,
    "SE": 42, "SE-ANALYSIS": 31, "SE-GRAPH": 14,
    "DOC/RET": 112, "DOC-NL": 56, "DOC-SPEC": 40, "RET-CODE": 53, "RET-KB": 6,
    "HIST": 62, "SEM": 69,
    "TEST": 48, "TEST-EXEC": 32, "TEST-RENDER": 1, "TEST-IO": 9, "TEST-CODE": 18,
}


def descendants(code, children):
    """The node's own code plus every code below it."""
    out = {code}
    for child, _, grandchildren in children:
        out |= descendants(child, grandchildren)
    return out


def family_codes(family, children):
    codes = set()
    for child, _, grandchildren in children:
        codes |= descendants(child, grandchildren)
    return codes


ALL_CODES = set().union(*(family_codes(f, ch) for f, _, _, ch, _ in TREE))


def rows(ws):
    """Rows of a sheet as dicts keyed by the header row."""
    it = ws.iter_rows(values_only=True)
    header = [str(h).strip() if h is not None else None for h in next(it)]
    for r in it:
        yield {h: v for h, v in zip(header, r) if h}


def parse_codes(cell):
    return {t.strip().upper() for t in re.split(r"[\n,;]+", str(cell or "")) if t.strip()}


def norm_link(link):
    return str(link or "").strip().rstrip("/").lower()


def load(xlsx):
    wb = openpyxl.load_workbook(xlsx, read_only=True, data_only=True)

    screened = [r for r in rows(wb["papers"]) if r.get("title")]
    include_rows = [r for r in screened if r.get("decision") == "include"]
    included = {norm_link(r["link"]) for r in include_rows}  # three papers are listed twice

    coded, not_codable, rounds = {}, [], [0, 0]
    # First round: the 40 randomly sampled papers coded to derive the taxonomy.
    for r in rows(wb["coded"]):
        if r.get("title"):
            coded[norm_link(r["link"])] = (r["title"], parse_codes(r.get("Tags")))
            rounds[0] += 1
    # Second round: the remaining 144 candidate papers.
    for r in rows(wb["Remaining 144 coded"]):
        if not r.get("Title"):
            continue
        rounds[1] += 1
        codes = parse_codes(r.get("Proposed tree codes"))
        if not codes:
            status = str(r.get("Evidence status") or "")
            if not status.lower().endswith("exclude"):
                sys.exit(f"paper without codes and not marked as excluded: {r['Title']}")
            not_codable.append((norm_link(r["Link"]), r["Title"].split(" | ")[0], status))
            continue
        coded[norm_link(r["Link"])] = (r["Title"], codes)

    unknown = {c for _, codes in coded.values() for c in codes} - ALL_CODES
    if unknown:
        sys.exit(f"codes not in the taxonomy: {sorted(unknown)}")
    candidates = set(coded) | {link for link, _, _ in not_codable}
    if candidates != included:
        sys.exit(f"coded papers differ from included papers: {sorted(candidates ^ included)}")
    return screened, include_rows, coded, not_codable, rounds


def count(coded, codes):
    return sum(1 for _, c in coded.values() if c & codes)


def build_counts(coded):
    counts = {}

    def walk(children):
        for code, _, grandchildren in children:
            counts[code] = count(coded, descendants(code, grandchildren))
            walk(grandchildren)

    for family, _, _, children, _ in TREE:
        counts[family] = count(coded, family_codes(family, children))
        walk(children)
    return counts


def print_tree(coded, counts, full):
    print(f"Context Provided to LLM [{len(coded)}]")
    for i, (family, label, desc, children, collapsed) in enumerate(TREE):
        last = i == len(TREE) - 1
        print(f"{'└' if last else '├'}── {label} [{counts[family]}]")
        pad = "    " if last else "│   "
        print(f"{pad}    {desc}")
        if collapsed and not full:
            continue

        def walk(nodes, prefix):
            for j, (code, desc, grandchildren) in enumerate(nodes):
                end = j == len(nodes) - 1
                width = 15 - (len(prefix) - len(pad))
                print(f"{prefix}{'└' if end else '├'}── {code:<{width}} [{counts[code]:>3}]  {desc}")
                walk(grandchildren, prefix + ("    " if end else "│   "))

        walk(children, pad)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--xlsx", type=Path, default=XLSX)
    ap.add_argument("--full", action="store_true", help="expand the HIST and SEM subcodes")
    ap.add_argument("--check", action="store_true", help="compare every number with the paper")
    args = ap.parse_args()

    screened, include_rows, coded, not_codable, rounds = load(args.xlsx)
    counts = build_counts(coded)
    candidates = len(coded) + len(not_codable)

    print(f"Search results (LLM in title or abstract): {len(screened)}")
    print(f"Candidate papers (LLM performs a task on source code): {candidates}"
          f"  ({len(include_rows)} 'include' rows, {len(include_rows) - candidates} of them duplicates)")
    print(f"  round 1, random sample that derived the taxonomy: {rounds[0]}")
    print(f"  round 2, remaining papers: {rounds[1]}")
    print(f"  not codable at study level: {len(not_codable)}")
    for _, title, status in not_codable:
        print(f"    - {title}  [{status}]")
    print(f"Coded papers: {len(coded)}")
    print()
    print_tree(coded, counts, args.full)

    if args.check:
        ours = dict(counts)
        ours.update({"search results": len(screened), "candidate papers": candidates,
                     "not codable": len(not_codable), "coded papers": len(coded)})
        bad = [(k, v, ours.get(k)) for k, v in PAPER.items() if ours.get(k) != v]
        print()
        if bad:
            for k, paper, got in bad:
                print(f"MISMATCH {k}: paper {paper}, spreadsheet {got}")
            sys.exit(1)
        print(f"All {len(PAPER)} numbers match the paper.")


if __name__ == "__main__":
    main()
