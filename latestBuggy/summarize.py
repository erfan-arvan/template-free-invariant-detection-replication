import argparse
import glob
from collections import Counter
from pathlib import Path

import oca


def oca_stats(d):
    v = Counter(o["verdict"] for o in oca.records(d / "outcomes_run.jsonl"))
    regs = oca.records(d / "registry_run.jsonl")
    ppts = {(r["kind"], r["element"]) for r in regs}
    compiled = v["HELD"] + v["FALSIFIED"] + v["NEVER_EXECUTED"]
    return {"invariants": sum(v.values()), "program_points": len(ppts), "failed_to_compile": v["FAILED_TO_COMPILE"],
            "compiled": compiled, "never_executed": v["NEVER_EXECUTED"], "falsified": v["FALSIFIED"], "held": v["HELD"]}


def daikon_stats(d):
    ppts, invs = 0, 0
    for line in open(d / "invariants.txt", errors="replace"):
        s = line.strip()
        if not s or set(s) == {"="}:
            continue
        if ":::" in s:
            ppts += 1
            continue
        invs += 1
    return {"invariants": invs, "program_points": ppts}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="results")
    args = ap.parse_args()
    for tool, fn in (("oca", oca_stats), ("daikon", daikon_stats)):
        print(f"== {tool}")
        for d in sorted(Path(p) for p in glob.glob(f"{args.root}/{tool}/*")):
            try:
                print(f"{d.name:<24}", fn(d))
            except FileNotFoundError:
                print(f"{d.name:<24} incomplete")


if __name__ == "__main__":
    main()
