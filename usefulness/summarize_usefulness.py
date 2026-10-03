import json
from collections import defaultdict
from pathlib import Path

PROJECTS = ["Cli", "Codec", "Collections", "Gson", "Math"]


def main():
    table = defaultdict(lambda: {"oca": [0, 0], "daikon": [0, 0]})
    for tool in ("oca", "daikon"):
        for f in sorted(Path("results", tool).glob("*/result.json")):
            r = json.loads(f.read_text())
            project = r["bug"].split("_")[0]
            table[project][tool][0] += r["detected"]
            table[project][tool][1] += 1
    print(f"{'project':<12}{'Oca':>8}{'Daikon':>10}")
    tot = {"oca": [0, 0], "daikon": [0, 0]}
    for p in PROJECTS:
        o, d = table[p]["oca"], table[p]["daikon"]
        for t, v in (("oca", o), ("daikon", d)):
            tot[t][0] += v[0]
            tot[t][1] += v[1]
        print(f"{p:<12}{o[0]:>5}/{o[1]:<2}{d[0]:>7}/{d[1]:<2}")
    print(f"{'Total':<12}{tot['oca'][0]:>5}/{tot['oca'][1]:<2}{tot['daikon'][0]:>7}/{tot['daikon'][1]:<2}")


if __name__ == "__main__":
    main()
