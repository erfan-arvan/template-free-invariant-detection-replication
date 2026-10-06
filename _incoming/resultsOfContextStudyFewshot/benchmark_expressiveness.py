#!/usr/bin/env python3
import json
import re
from pathlib import Path

PROJECTS = ("apollo", "dubbo", "netty", "hudi", "libgdx", "spring")
ROOT = Path("class_doc")

def read_jsonl(path):
    with path.open() as f:
        return [json.loads(line) for line in f if line.strip()]

def get_status(row):
    for key in ("verdict", "status", "outcome", "result", "state"):
        if key in row:
            return str(row[key]).upper().replace("_", "-")
    return None

rows = []

for project in PROJECTS:
    folder = ROOT / project
    metrics = {
        item["id"]: item
        for item in read_jsonl(folder / "daikonpp_invariant_metrics.jsonl")
    }
    outcomes = read_jsonl(folder / "daikonpp_outcomes.jsonl")

    held_ids = {
        item["id"]
        for item in outcomes
        if get_status(item) in {"HELD", "OBSERVED-HELD"}
    }

    if not held_ids:
        statuses = sorted({str(get_status(item)) for item in outcomes})
        raise ValueError(
            f"{project}: no held outcomes found. "
            f"Statuses: {statuses}; sample: {outcomes[0] if outcomes else None}"
        )

    missing = held_ids - metrics.keys()
    if missing:
        raise ValueError(f"{project}: {len(missing)} held IDs have no metrics")

    log = (folder / "run.log").read_text(errors="replace")
    reported = re.findall(r"observed-held=(\d+)", log)
    if not reported:
        raise ValueError(f"{project}: run.log has no observed-held total")
    if len(held_ids) != int(reported[-1]):
        print(
            f"WARNING {project}: {len(held_ids)} HELD outcome IDs, "
            f"but final run.log total is {reported[-1]}",
            file=__import__("sys").stderr,
        )

    no = len(held_ids)
    v3 = sum(int(metrics[id]["varCount2"]) > 3 for id in held_ids)
    pspm = sum(int(metrics[id]["pspmCount"]) > 0 for id in held_ids)
    rows.append((project, no, v3, pspm))

print("Project       N_O    V>3   PSPM   Var>3%   PSPM%")
for project, no, v3, pspm in rows:
    print(
        f"{project:<10} {no:>6} {v3:>6} {pspm:>6}"
        f" {100 * v3 / no:>8.2f} {100 * pspm / no:>8.2f}"
    )

total_no = sum(no for _, no, _, _ in rows)
total_v3 = sum(v3 for _, _, v3, _ in rows)
total_pspm = sum(pspm for _, _, _, pspm in rows)
macro_v3 = sum(100 * v3 / no for _, no, v3, _ in rows) / len(rows)
macro_pspm = sum(100 * pspm / no for _, no, _, pspm in rows) / len(rows)

print("\nLaTeX rows:")
for project, no, v3, pspm in rows:
    name = "libGDX" if project == "libgdx" else project.capitalize()
    print(
        f"{name} & \\todo{{$N_D$}} & {no:,} & {v3:,} & {pspm:,} & "
        f"{100 * v3 / no:.2f}\\% & {100 * pspm / no:.2f}\\% \\\\"
    )
print(
    f"Total / Macro avg. & \\todo{{total $N_D$}} & {total_no:,} & "
    f"{total_v3:,} & {total_pspm:,} & "
    f"{macro_v3:.2f}\\% & {macro_pspm:.2f}\\% \\\\"
)
