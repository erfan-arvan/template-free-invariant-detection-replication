import argparse
import json
import os
import re
from pathlib import Path

import d4j


def ppt_class(ppt):
    name = ppt.split(":::")[0]
    if "(" in name:
        name = name[:name.index("(")].rsplit(".", 1)[0]
    return name.split("$")[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("bug")
    ap.add_argument("--out-root", default="results/daikon")
    args = ap.parse_args()
    jar = os.environ["DAIKON_JAR"]
    work_root = Path(os.environ.get("WORK_ROOT", "work")).resolve()
    out = Path(args.out_root).resolve() / f"{args.project}_{args.bug}"
    out.mkdir(parents=True, exist_ok=True)
    log = out / "run.log"
    trig = d4j.triggering_tests(args.project, args.bug)
    trig_by_class = {}
    for c, m in trig:
        trig_by_class.setdefault(c, []).append(m)

    wb = work_root / f"{args.project}-{args.bug}b_daikon"
    ib = d4j.prepare(args.project, f"{args.bug}b", wb, log)
    cp = f"{ib['cp']}:{os.environ['JUNIT_JAR']}"
    runner = d4j.compile_runner(cp, out / "buggy", log)
    select = d4j.package_pattern(wb / ib["src"])
    omit = d4j.OMIT + "|" + "|".join(re.escape(c) for c in ib["classes"])

    specs_a = [f"{c}::" + ",".join("!" + m for m in trig_by_class[c]) if c in trig_by_class else c
               for c in ib["classes"]]
    trace_a = d4j.chicory(jar, runner, cp, select, omit, specs_a, wb, out / "traceA.dtrace.gz", log)
    inv = out / "invA.inv.gz"
    d4j.infer(jar, args.project, select, trace_a, inv, out / "invariantsA.txt", log)

    trace_t = d4j.chicory(jar, runner, cp, select, omit, [f"{c}::{m}" for c, m in trig], wb,
                          out / "traceTrig.dtrace.gz", log)
    step2 = d4j.falsified(jar, args.project, inv, trace_t, out / "step2_falsified.txt", log)

    detected = []
    if step2:
        wf = work_root / f"{args.project}-{args.bug}f_daikon"
        i_f = d4j.prepare(args.project, f"{args.bug}f", wf, log)
        cpf = f"{i_f['cp']}:{os.environ['JUNIT_JAR']}"
        runner_f = d4j.compile_runner(cpf, out / "fixed", log)
        narrow = "^(?:" + "|".join(sorted(re.escape(ppt_class(p)) for p, _ in step2)) + r")\b"
        omit_f = d4j.OMIT + "|" + "|".join(re.escape(c) for c in i_f["classes"])
        trace_f = d4j.chicory(jar, runner_f, cpf, narrow, omit_f, i_f["classes"], wf,
                              out / "traceFixed.dtrace.gz", log)
        step3 = d4j.falsified(jar, args.project, inv, trace_f, out / "step3_falsified.txt", log)
        detected = sorted(step2 - step3)

    (out / "result.json").write_text(json.dumps({
        "bug": f"{args.project}_{args.bug}", "triggering": [f"{c}::{m}" for c, m in trig],
        "falsified_by_triggering_tests": len(step2), "detected": bool(detected),
        "hits": [{"ppt": p, "invariant": i} for p, i in detected]}, indent=1))
    print(f"{args.project}_{args.bug}: detected={bool(detected)} hits={len(detected)}")


if __name__ == "__main__":
    main()
