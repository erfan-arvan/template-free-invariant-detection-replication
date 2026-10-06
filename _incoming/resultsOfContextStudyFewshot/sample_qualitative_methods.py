#!/usr/bin/env python3

import json
import random
import re
from pathlib import Path
from collections import defaultdict

# ------------------------------------------------------------
# SETTINGS
# ------------------------------------------------------------

SEED = 42
N = 9

CONFIGS = [
    "call_site",
    "class_doc",
    "io_examples",
    "method_javadoc",
    "type_doc",
]

PROJECTS = [
    "apollo",
    "dubbo",
    "hudi",
    "libgdx",
    "netty",
    "spring",
]

# Methods we already manually inspected.
EXCLUDE_SUBSTRINGS = [
    "CollectionToObjectConverter#convert(",
    "AntPathStringMatcher#quote(",
    "AntPathMatcher#quote(",
]

ROOT = Path(".").resolve()
REPO_ROOT = ROOT.parent


# ------------------------------------------------------------
# LOAD HELD INVARIANTS
# ------------------------------------------------------------

def load_jsonl(path):
    with path.open(errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                # In case there are occasional NULs/binary-ish garbage.
                try:
                    yield json.loads(line.replace("\x00", ""))
                except Exception:
                    pass


def load_config_project(config, project):
    d = ROOT / config / project
    registry_file = d / "daikonpp_registry.jsonl"
    outcomes_file = d / "daikonpp_outcomes.jsonl"

    if not registry_file.exists() or not outcomes_file.exists():
        return {}

    registry = {}
    for obj in load_jsonl(registry_file):
        if "id" in obj:
            registry[obj["id"]] = obj

    held_ids = set()
    for obj in load_jsonl(outcomes_file):
        if (
            obj.get("verdict") == "HELD"
            and obj.get("compiled") is True
            and obj.get("executed") is True
        ):
            held_ids.add(obj.get("id"))

    result = defaultdict(list)

    for inv_id in held_ids:
        r = registry.get(inv_id)
        if not r:
            continue

        element = r.get("element")
        if not element:
            continue

        result[element].append({
            "id": inv_id,
            "kind": r.get("kind", ""),
            "expr": r.get("expr", ""),
            "rationale": r.get("rationale", ""),
            "file": r.get("file", ""),
        })

    return result


# data[project][config][method] = list of held invariants
data = defaultdict(dict)

for project in PROJECTS:
    for config in CONFIGS:
        data[project][config] = load_config_project(config, project)


# ------------------------------------------------------------
# FIND METHODS REPRESENTED IN EVERY CONFIGURATION
# ------------------------------------------------------------

eligible = []

for project in PROJECTS:
    method_sets = [
        set(data[project][config].keys())
        for config in CONFIGS
    ]

    if not method_sets:
        continue

    common = set.intersection(*method_sets)

    for method in sorted(common):
        if any(x in method for x in EXCLUDE_SUBSTRINGS):
            continue

        # Defensive check: at least one HELD invariant in every config.
        if all(data[project][c].get(method) for c in CONFIGS):
            eligible.append((project, method))


print(f"Eligible methods across all {len(CONFIGS)} configurations: {len(eligible)}")

if len(eligible) < N:
    raise SystemExit(
        f"Only {len(eligible)} eligible methods found; cannot sample {N}."
    )


# ------------------------------------------------------------
# RANDOM SAMPLE
# ------------------------------------------------------------

rng = random.Random(SEED)

# First, guarantee one method from each project.
sample = []
used = set()

for project in PROJECTS:
    candidates = [(p, m) for p, m in eligible if p == project]

    if not candidates:
        print(f"WARNING: no eligible method for project {project}")
        continue

    chosen = rng.choice(candidates)
    sample.append(chosen)
    used.add(chosen)

# Fill the remaining slots randomly from all unused eligible methods.
remaining = [x for x in eligible if x not in used]
sample.extend(rng.sample(remaining, N - len(sample)))


# ------------------------------------------------------------
# SOURCE LOOKUP
# ------------------------------------------------------------

source_cache = {}


def locate_source(project, relative_file):
    """
    Registry paths are often package-relative rather than repository-relative,
    e.g. io/netty/util/X.java while actual file may be
    common/src/main/java/io/netty/util/X.java.

    Find a Java file whose path ends with registry's `file`.
    """
    key = (project, relative_file)
    if key in source_cache:
        return source_cache[key]

    repo = REPO_ROOT / project
    if not repo.exists():
        source_cache[key] = None
        return None

    wanted = relative_file.replace("\\", "/")

    # First try direct path.
    direct = repo / wanted
    if direct.exists():
        source_cache[key] = direct
        return direct

    # Otherwise suffix match.
    basename = Path(wanted).name
    matches = []

    for p in repo.rglob(basename):
        if not p.is_file():
            continue
        rel = str(p.relative_to(repo)).replace("\\", "/")
        if rel.endswith(wanted):
            matches.append(p)

    # If exact suffix did not work, fall back to filename.
    if not matches:
        matches = [p for p in repo.rglob(basename) if p.is_file()]

    result = matches[0] if matches else None
    source_cache[key] = result
    return result


def method_name_from_element(element):
    # Class#method(args):return
    after_hash = element.split("#", 1)[1]
    return after_hash.split("(", 1)[0]


def extract_method(text, element):
    """
    Heuristic Java method extractor.
    Prints the declaration plus its brace-balanced body.

    Works well enough for manual qualitative inspection and avoids printing
    entire large source files.
    """
    name = method_name_from_element(element)

    lines = text.splitlines()

    # Candidate declaration lines.
    # Constructors and ordinary methods are handled the same way.
    candidates = []

    for i, line in enumerate(lines):
        # Avoid obvious invocation-only lines when possible.
        if re.search(r"\b" + re.escape(name) + r"\s*\(", line):
            candidates.append(i)

    for i in candidates:
        # Search a few lines around candidate for the opening brace.
        start = i
        j = i
        found_brace = False

        while j < min(len(lines), i + 12):
            combined = "\n".join(lines[i:j+1])

            if "{" in combined:
                found_brace = True
                break

            # Abstract/interface declaration.
            if ";" in combined:
                break

            j += 1

        if not found_brace:
            continue

        # Try to avoid call expressions by checking declaration-ish prefix.
        prefix = "\n".join(lines[max(0, i-2):j+1])
        declaration_signals = [
            "public ", "private ", "protected ", "static ",
            "final ", "synchronized ", "@Override",
        ]

        # Package-private methods are possible, so this is not mandatory.
        # We rely mostly on brace balancing.

        brace_count = 0
        started = False
        end = j

        for k in range(i, len(lines)):
            # Strip strings/comments only minimally; sufficient for display.
            line = lines[k]

            for ch in line:
                if ch == "{":
                    brace_count += 1
                    started = True
                elif ch == "}" and started:
                    brace_count -= 1

            if started and brace_count == 0:
                end = k
                break

        if started:
            # Include immediately preceding annotations/Javadoc only lightly.
            start = i
            while start > 0 and lines[start - 1].strip().startswith("@"):
                start -= 1

            return "\n".join(lines[start:end + 1])

    return None


# ------------------------------------------------------------
# OUTPUT
# ------------------------------------------------------------

out = []

out.append(f"Random seed: {SEED}")
out.append(f"Eligible methods: {len(eligible)}")
out.append(f"Sampled methods: {N}")
out.append("")

out.append("SELECTED METHODS")
out.append("=" * 100)

for idx, (project, method) in enumerate(sample, 1):
    out.append(f"{idx}. [{project}] {method}")

out.append("")
out.append("")


for idx, (project, method) in enumerate(sample, 1):
    out.append("#" * 120)
    out.append(f"METHOD {idx}/{N}")
    out.append(f"PROJECT: {project}")
    out.append(f"ELEMENT: {method}")
    out.append("#" * 120)
    out.append("")

    # Print all held invariants by context.
    for config in CONFIGS:
        invs = data[project][config][method]

        out.append(f"=== {config.upper()} : {len(invs)} HELD ===")

        # Entry first, then exit, then anything else.
        kind_order = {
            "METHOD_ENTRY": 0,
            "METHOD_EXIT": 1,
        }

        invs_sorted = sorted(
            invs,
            key=lambda x: (kind_order.get(x["kind"], 9), x["expr"])
        )

        for inv in invs_sorted:
            out.append(
                f"[{inv['kind']}] {inv['expr']}"
            )
            out.append(
                f"    id: {inv['id']}"
            )
            if inv["rationale"]:
                out.append(
                    f"    rationale: {inv['rationale']}"
                )

        out.append("")

    # Use file field from any configuration.
    relative_file = None
    for config in CONFIGS:
        invs = data[project][config][method]
        for inv in invs:
            if inv.get("file"):
                relative_file = inv["file"]
                break
        if relative_file:
            break

    out.append("=== SOURCE CODE ===")

    if not relative_file:
        out.append("No source file recorded in registry.")
        out.append("")
        continue

    out.append(f"Registry file: {relative_file}")

    source_path = locate_source(project, relative_file)

    if source_path is None:
        out.append("Could not locate source file in repository.")
        out.append("")
        continue

    out.append(f"Repository path: {source_path}")
    out.append("")

    try:
        text = source_path.read_text(errors="replace")
        method_src = extract_method(text, method)

        if method_src:
            out.append(method_src)
        else:
            out.append(
                "[Could not isolate method automatically; full source path above.]"
            )
    except Exception as e:
        out.append(f"[Error reading source: {e}]")

    out.append("")
    out.append("")


output_file = ROOT / f"qualitative_sample_{N}.txt"
output_file.write_text("\n".join(out))

print()
print("Selected methods:")
for i, (project, method) in enumerate(sample, 1):
    print(f"{i}. [{project}] {method}")

print()
print(f"Wrote: {output_file}")
