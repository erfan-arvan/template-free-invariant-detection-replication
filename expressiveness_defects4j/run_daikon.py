import argparse
import os
import re
from pathlib import Path

import d4j


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("--version", choices=("b", "f"), required=True)
    ap.add_argument("--bug", default=None)
    ap.add_argument("--out-root", default="results/daikon")
    args = ap.parse_args()
    jar = os.environ["DAIKON_JAR"]
    bug = args.bug or d4j.latest_bug(args.project)
    version = f"{bug}{args.version}"
    out = Path(args.out_root).resolve() / f"{args.project}_{version}"
    out.mkdir(parents=True, exist_ok=True)
    log = out / "run.log"
    work = Path(os.environ.get("WORK_ROOT", "work")).resolve() / f"{args.project}-{version}_daikon"
    info = d4j.prepare(args.project, version, work, log)
    cp = f"{info['cp']}:{os.environ['JUNIT_JAR']}"
    runner = d4j.compile_runner(cp, out, log)
    select = d4j.package_pattern(work / info["src"])
    omit = d4j.OMIT + "|" + "|".join(re.escape(c) for c in info["classes"])
    trace = d4j.chicory(jar, runner, cp, select, omit, info["classes"], work, out / "trace.dtrace.gz", log)
    d4j.infer(jar, args.project, select, trace, out / "inv.inv.gz", out / "invariants.txt", log)
    print(f"{args.project}_{version}: done -> {out}")


if __name__ == "__main__":
    main()
