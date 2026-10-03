import argparse
import json
import os
from pathlib import Path

import d4j
import oca


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("bug")
    ap.add_argument("--out-root", default="results/oca")
    ap.add_argument("--cassettes", default="cassettes")
    args = ap.parse_args()
    jar = os.environ["OCA_JAR"]
    work_root = Path(os.environ.get("WORK_ROOT", "work")).resolve()
    out = Path(args.out_root).resolve() / f"{args.project}_{args.bug}"
    out.mkdir(parents=True, exist_ok=True)
    cassettes = Path(args.cassettes).resolve() / args.project
    trig = d4j.triggering_tests(args.project, args.bug)
    log = out / "d4j.log"

    w1 = work_root / f"{args.project}-{args.bug}b_step1"
    i1 = d4j.prepare(args.project, f"{args.bug}b", w1, log)
    oca.disable_tests(w1 / i1["tests"], trig)
    reg, res = oca.run_oca(jar, w1, i1, out, "step1", oca.full_suite_runner(out), cassettes, False, True)
    held = {k for k, v in oca.verdicts(reg, res).items() if v == "HELD"}

    w2 = work_root / f"{args.project}-{args.bug}b_step2"
    i2 = d4j.prepare(args.project, f"{args.bug}b", w2, log)
    reg, res = oca.run_oca(jar, w2, i2, out, "step2", oca.selected_tests_runner(out, trig), cassettes, True, True)
    candidates = sorted(k for k, v in oca.verdicts(reg, res).items() if v == "FALSIFIED" and k in held)

    w3 = work_root / f"{args.project}-{args.bug}f_step3"
    i3 = d4j.prepare(args.project, f"{args.bug}f", w3, log)
    reg, res = oca.run_oca(jar, w3, i3, out, "step3", oca.full_suite_runner(out), cassettes, True, True)
    fixed = oca.verdicts(reg, res)
    fixed_methods = {k.split("|")[1] for k in fixed}
    rows = []
    for k in candidates:
        if k in fixed:
            status = "confirmed" if fixed[k] == "HELD" else "refuted" if fixed[k] == "FALSIFIED" else fixed[k]
        else:
            status = "undetermined" if k.split("|")[1] in fixed_methods else "confirmed_method_changed"
        rows.append({"invariant": k, "fixed": status})
    detected = any(r["fixed"] in ("confirmed", "confirmed_method_changed") for r in rows)
    (out / "result.json").write_text(json.dumps({"bug": f"{args.project}_{args.bug}", "triggering": trig,
                                                 "held_step1": len(held), "candidates_step2": len(candidates),
                                                 "detected": detected, "candidates": rows}, indent=1))
    print(f"{args.project}_{args.bug}: detected={detected} candidates={len(candidates)}")


if __name__ == "__main__":
    main()
