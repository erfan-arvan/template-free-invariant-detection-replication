#!/usr/bin/env python3
"""Create wide and compact CSV summaries from prompt-study run.log files."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

METRICS = [
    "all",
    "compiled",
    "non-compiled",
    "executed",
    "falsified",
    "observed-held",
    "never-executed",
    "disabled-stale",
    "unreached",
]

TOTALS_RE = re.compile(
    r">>>\s*Totals:\s*"
    r"all=(?P<all>\d+)\s+"
    r"compiled=(?P<compiled>\d+)\s+"
    r"non-compiled=(?P<non_compiled>\d+)\s+"
    r"executed=(?P<executed>\d+)\s+"
    r"falsified=(?P<falsified>\d+)\s+"
    r"observed-held=(?P<observed_held>\d+)\s+"
    r"never-executed=(?P<never_executed>\d+)\s*"
    r"\(disabled-stale=(?P<disabled_stale>\d+)\s+"
    r"unreached=(?P<unreached>\d+)\)"
)

GROUP_TO_METRIC = {
    "all": "all",
    "compiled": "compiled",
    "non_compiled": "non-compiled",
    "executed": "executed",
    "falsified": "falsified",
    "observed_held": "observed-held",
    "never_executed": "never-executed",
    "disabled_stale": "disabled-stale",
    "unreached": "unreached",
}


def parse_totals(log_path: Path) -> dict[str, int] | None:
    last_match: re.Match[str] | None = None

    with log_path.open("r", encoding="utf-8", errors="replace") as log_file:
        for line in log_file:
            match = TOTALS_RE.search(line)
            if match:
                last_match = match

    if last_match is None:
        return None

    return {
        GROUP_TO_METRIC[group]: int(value)
        for group, value in last_match.groupdict().items()
    }


def compact_cell(values: dict[str, int]) -> str:
    return "\n".join(f"{metric}={values[metric]}" for metric in METRICS)


def print_ranking(
    title: str,
    values_by_strategy: dict[str, int],
) -> None:
    ranked = sorted(
        values_by_strategy.items(),
        key=lambda item: (-item[1], item[0]),
    )

    print(f"\n{title}")
    for rank, (strategy, value) in enumerate(ranked, start=1):
        print(f"  {rank}. {strategy}: {value}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument(
        "-o",
        "--output",
        default="prompt_study_results.csv",
    )
    parser.add_argument(
        "--compact-output",
        default="prompt_study_results_compact.csv",
    )
    parser.add_argument(
        "--exclude-project",
        action="append",
        default=[],
        help="Project to exclude from reports; may be specified multiple times.",
    )
    args = parser.parse_args()

    root = Path(args.root).expanduser().resolve()
    output = Path(args.output).expanduser()
    compact_output = Path(args.compact_output).expanduser()

    if not root.is_dir():
        print(f"ERROR: directory does not exist: {root}", file=sys.stderr)
        return 1

    strategies = sorted(
        path
        for path in root.iterdir()
        if path.is_dir()
    )

    excluded_projects = set(args.exclude_project)

    projects = sorted(
        {
            project_dir.name
            for strategy_dir in strategies
            for project_dir in strategy_dir.iterdir()
            if project_dir.is_dir()
            and (project_dir / "run.log").is_file()
            and project_dir.name not in excluded_projects
        }
    )

    if not projects:
        print("ERROR: no run.log files found", file=sys.stderr)
        return 1

    wide_fields = ["strategy"] + [
        f"{project}_{metric}"
        for project in projects
        for metric in METRICS
    ]
    compact_fields = ["strategy"] + projects

    wide_rows: list[dict[str, str | int]] = []
    compact_rows: list[dict[str, str]] = []
    warnings: list[str] = []

    # Combined observed-held total across all projects.
    observed_held_totals: dict[str, int] = {}

    # Per-project observed-held values:
    # {
    #     "hudi": {"baseline": 100, "fewshot": 90, ...},
    #     "rxjava": {"baseline": 200, "fewshot": 180, ...},
    # }
    observed_held_by_project: dict[str, dict[str, int]] = {
        project: {}
        for project in projects
    }

    for strategy_dir in strategies:
        strategy = strategy_dir.name
        wide_row: dict[str, str | int] = {"strategy": strategy}
        compact_row: dict[str, str] = {"strategy": strategy}

        observed_held_total = 0
        has_result = False

        for project in projects:
            log_path = strategy_dir / project / "run.log"
            values = parse_totals(log_path) if log_path.is_file() else None

            if values is None:
                warnings.append(
                    f"{'No valid Totals line' if log_path.is_file() else 'Missing log'}: "
                    f"{log_path}"
                )

                for metric in METRICS:
                    wide_row[f"{project}_{metric}"] = ""

                compact_row[project] = ""
                continue

            has_result = True
            observed_held = values["observed-held"]
            observed_held_total += observed_held

            observed_held_by_project[project][strategy] = observed_held

            for metric in METRICS:
                wide_row[f"{project}_{metric}"] = values[metric]

            compact_row[project] = compact_cell(values)

        wide_rows.append(wide_row)
        compact_rows.append(compact_row)

        if has_result:
            observed_held_totals[strategy] = observed_held_total

    output.parent.mkdir(parents=True, exist_ok=True)
    compact_output.parent.mkdir(parents=True, exist_ok=True)

    with output.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=wide_fields)
        writer.writeheader()
        writer.writerows(wide_rows)

    with compact_output.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=compact_fields)
        writer.writeheader()
        writer.writerows(compact_rows)

    print(f"Created: {output.resolve()}")
    print(f"Created: {compact_output.resolve()}")
    print(f"Strategies: {len(strategies)}")
    print(f"Projects: {', '.join(projects)}")

    # Print the combined ranking across all projects.
    print_ranking(
        "Observed-held totals by strategy across all projects:",
        observed_held_totals,
    )

    combined_ranked = sorted(
        observed_held_totals.items(),
        key=lambda item: (-item[1], item[0]),
    )

    if combined_ranked:
        best_total = combined_ranked[0][1]
        best = [
            strategy
            for strategy, total in combined_ranked
            if total == best_total
        ]

        if len(best) == 1:
            print(
                f"\nBest strategy across all projects: "
                f"{best[0]} ({best_total})"
            )
        else:
            print(
                f"\nBest strategies across all projects: "
                f"{', '.join(best)} ({best_total} each)"
            )

    # Print a separate ranking for each project.
    print("\nObserved-held rankings per project:")

    for project in projects:
        project_results = observed_held_by_project[project]

        print_ranking(
            f"{project}:",
            project_results,
        )

        if project_results:
            project_ranked = sorted(
                project_results.items(),
                key=lambda item: (-item[1], item[0]),
            )

            best_value = project_ranked[0][1]
            best_strategies = [
                strategy
                for strategy, value in project_ranked
                if value == best_value
            ]

            if len(best_strategies) == 1:
                print(
                    f"  Best for {project}: "
                    f"{best_strategies[0]} ({best_value})"
                )
            else:
                print(
                    f"  Best for {project}: "
                    f"{', '.join(best_strategies)} "
                    f"({best_value} each)"
                )

    for warning in warnings:
        print(f"WARNING: {warning}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
