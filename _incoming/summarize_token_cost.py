#!/usr/bin/env python3

import re
from pathlib import Path

RESULTS = Path("resultsOfTokenCostFewshotClassDoc")

INPUT_PRICE_PER_M = 0.40
OUTPUT_PRICE_PER_M = 1.60

PROJECTS = [
    "apollo",
    "dubbo",
    "netty",
    "hudi",
    "spring",
    "libgdx",
]

input_re = re.compile(r"TOTAL input tokens\s*:\s*(\d+)")
output_re = re.compile(r"TOTAL output tokens\s*:\s*(\d+)")

total_input = 0
total_output = 0
total_cost = 0.0

print(
    f"{'Project':<10}"
    f"{'Input tokens':>15}"
    f"{'Output tokens':>16}"
    f"{'Input cost':>14}"
    f"{'Output cost':>15}"
    f"{'Total cost':>14}"
)
print("-" * 84)

for project in PROJECTS:
    log = RESULTS / project / "run.log"

    if not log.is_file():
        print(f"{project:<10} MISSING: {log}")
        continue

    text = log.read_text(encoding="utf-8", errors="replace")

    input_matches = input_re.findall(text)
    output_matches = output_re.findall(text)

    if not input_matches or not output_matches:
        print(f"{project:<10} ERROR: token totals not found")
        continue

    input_tokens = int(input_matches[-1])
    output_tokens = int(output_matches[-1])

    input_cost = input_tokens / 1_000_000 * INPUT_PRICE_PER_M
    output_cost = output_tokens / 1_000_000 * OUTPUT_PRICE_PER_M
    cost = input_cost + output_cost

    total_input += input_tokens
    total_output += output_tokens
    total_cost += cost

    print(
        f"{project:<10}"
        f"{input_tokens:>15,}"
        f"{output_tokens:>16,}"
        f"${input_cost:>13.4f}"
        f"${output_cost:>14.4f}"
        f"${cost:>13.4f}"
    )

print("-" * 84)

total_input_cost = total_input / 1_000_000 * INPUT_PRICE_PER_M
total_output_cost = total_output / 1_000_000 * OUTPUT_PRICE_PER_M

print(
    f"{'TOTAL':<10}"
    f"{total_input:>15,}"
    f"{total_output:>16,}"
    f"${total_input_cost:>13.4f}"
    f"${total_output_cost:>14.4f}"
    f"${total_cost:>13.4f}"
)

print()
print(f"Total input tokens : {total_input:,}")
print(f"Total output tokens: {total_output:,}")
print(f"Total tokens       : {total_input + total_output:,}")
print(f"Total input cost   : ${total_input_cost:.4f}")
print(f"Total output cost  : ${total_output_cost:.4f}")
print(f"TOTAL COST         : ${total_cost:.4f}")
