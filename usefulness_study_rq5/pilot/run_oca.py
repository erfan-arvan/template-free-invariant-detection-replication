import argparse
import os
from pathlib import Path

import d4j
import oca


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("--version", choices=("b", "f"), required=True)
    ap.add_argument("--bug", default=None)
    ap.add_argument("--relaxed", action="store_true")
    ap.add_argument("--out-root", default="results/oca")
    ap.add_argument("--cassettes", default="cassettes")
    args = ap.parse_args()
    bug = args.bug or d4j.latest_bug(args.project)
    version = f"{bug}{args.version}"
    out = Path(args.out_root).resolve() / f"{args.project}_{version}"
    work = Path(os.environ.get("WORK_ROOT", "work")).resolve() / f"{args.project}-{version}_oca"
    info = d4j.prepare(args.project, version, work, out / "d4j.log")
    oca.run_oca(os.environ["OCA_JAR"], work, info, out, "run", oca.full_suite_runner(out),
                Path(args.cassettes).resolve() / args.project, False, args.relaxed)
    print(f"{args.project}_{version}: done -> {out}")


if __name__ == "__main__":
    main()
