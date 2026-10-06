#!/usr/bin/env python3

import argparse
import json
import random
import re
from pathlib import Path
from collections import defaultdict


BASE = Path(__file__).resolve().parent

OCA_BASE = BASE / "resultsOfContextStudyFewshot" / "class_doc"

DAIKON_FILES = {
    "apollo": BASE / "apollo-daikon-out" / "apollo-invariants.txt",

    "hudi": BASE / "hudi-daikon-out" / "hudi-invariants.txt",

    "spring": BASE / "spring-daikon-out" / "spring-invariants.txt",

    "libgdx": (
        BASE
        / "libgdx-s5-daikon-out"
        / "libgdx-s5-invariants.txt"
    ),

    "dubbo": (
        BASE
        / "dubbo-s5-daikon-quickfix-out"
        / "dubbo-s5-quickfix-invariants.txt"
    ),

    "netty": (
        BASE
        / "netty-s5-daikon-quickfix-out"
        / "netty-s5-quickfix-invariants.txt"
    ),
}

PROJECTS = [
    "apollo",
    "hudi",
    "spring",
    "libgdx",
    "dubbo",
    "netty",
]

DAIKON_SEPARATOR = "=" * 75


# ============================================================
# JSONL
# ============================================================

def read_jsonl(path):
    records = []

    with open(
        path,
        "r",
        encoding="utf-8",
        errors="replace",
    ) as f:

        for lineno, line in enumerate(f, 1):

            line = line.rstrip("\n")

            if not line.strip():
                continue

            try:
                obj = json.loads(line, strict=False)
                records.append(obj)

            except Exception as e:
                print(
                    f"WARNING: could not parse "
                    f"{path}:{lineno}: {e}"
                )

    return records


# ============================================================
# TYPE NORMALIZATION
# ============================================================

def split_parameters(s):
    """
    Split:

        Map<String, String>, TypeDescriptor, List<Foo>

    without splitting commas inside <...>.
    """

    s = s.strip()

    if not s:
        return []

    result = []
    current = []

    angle = 0
    paren = 0
    bracket = 0

    for ch in s:

        if ch == "<":
            angle += 1

        elif ch == ">":
            angle = max(0, angle - 1)

        elif ch == "(":
            paren += 1

        elif ch == ")":
            paren = max(0, paren - 1)

        elif ch == "[":
            bracket += 1

        elif ch == "]":
            bracket = max(0, bracket - 1)

        if (
            ch == ","
            and angle == 0
            and paren == 0
            and bracket == 0
        ):
            result.append(
                "".join(current).strip()
            )
            current = []

        else:
            current.append(ch)

    if current:
        result.append(
            "".join(current).strip()
        )

    return result


def strip_generics(s):
    """
    Map<String, Foo> -> Map
    Class<? extends Annotation> -> Class
    """

    result = []
    depth = 0

    for ch in s:

        if ch == "<":
            depth += 1
            continue

        if ch == ">":
            depth = max(0, depth - 1)
            continue

        if depth == 0:
            result.append(ch)

    return "".join(result)


def normalize_type(t):
    """
    Normalize both OCA and Daikon types to a simple erased form.

    Examples:

      java.lang.String
        -> String

      org.springframework.core.convert.TypeDescriptor
        -> TypeDescriptor

      Map<String, String>
        -> Map

      java.lang.String[]
        -> String[]

      String @Nullable []
        -> String[]
    """

    t = t.strip()

    # Remove annotations such as @Nullable.
    t = re.sub(
        r"@\w+(?:\([^)]*\))?",
        "",
        t,
    )

    t = t.strip()

    # varargs -> array
    t = t.replace("...", "[]")

    # Remove generics.
    t = strip_generics(t)

    # Normalize spaces.
    t = re.sub(r"\s+", "", t)

    # Preserve array dimensions.
    dims = ""

    while t.endswith("[]"):
        dims += "[]"
        t = t[:-2]

    # Handle wildcard-ish leftovers conservatively.
    t = re.sub(
        r"^\?extends",
        "",
        t,
    )

    t = re.sub(
        r"^\?super",
        "",
        t,
    )

    # Convert fully qualified class to simple class.
    if "." in t:
        t = t.rsplit(".", 1)[1]

    return t + dims


# ============================================================
# OCA METHOD PARSING
# ============================================================

def parse_oca_element(element):
    """
    Example:

      org.springframework.util.ResourceUtils
      #getFile(String):File

    ->

      (
        org.springframework.util.ResourceUtils,
        getFile,
        ("String",)
      )
    """

    if "#" not in element:
        return None

    class_name, rest = element.split("#", 1)

    open_paren = rest.find("(")
    close_paren = rest.rfind(")")

    if open_paren < 0 or close_paren < open_paren:
        return None

    method_name = rest[:open_paren]

    params_text = rest[
        open_paren + 1:
        close_paren
    ]

    params = tuple(
        normalize_type(x)
        for x in split_parameters(params_text)
    )

    # Some instrumentation schemes represent constructors
    # using <init>.
    if method_name == "<init>":
        method_name = class_name.rsplit(".", 1)[-1]

        if "$" in method_name:
            method_name = method_name.rsplit("$", 1)[-1]

    return (
        class_name,
        method_name,
        params,
    )


# ============================================================
# DAIKON METHOD PARSING
# ============================================================

def parse_daikon_signature(signature):
    """
    Example:

      org.springframework.util.ResourceUtils.getFile(
          java.lang.String
      )

    ->

      (
        org.springframework.util.ResourceUtils,
        getFile,
        ("String",)
      )
    """

    open_paren = signature.find("(")
    close_paren = signature.rfind(")")

    if open_paren < 0 or close_paren < open_paren:
        return None

    before = signature[:open_paren]

    if "." not in before:
        return None

    class_name, method_name = before.rsplit(".", 1)

    params_text = signature[
        open_paren + 1:
        close_paren
    ]

    params = tuple(
        normalize_type(x)
        for x in split_parameters(params_text)
    )

    return (
        class_name,
        method_name,
        params,
    )


def daikon_base_method(program_point):
    return program_point.split(
        ":::",
        1,
    )[0]


def is_daikon_method_program_point(
    program_point
):
    if ":::" not in program_point:
        return False

    suffix = program_point.split(
        ":::",
        1,
    )[1]

    return (
        suffix == "ENTER"
        or suffix.startswith("EXIT")
    )


def parse_daikon_file(path):

    with open(
        path,
        "r",
        encoding="utf-8",
        errors="replace",
    ) as f:
        text = f.read()

    blocks = re.split(
        r"^={20,}\s*$",
        text,
        flags=re.MULTILINE,
    )

    methods_by_signature = defaultdict(list)

    for block in blocks:

        block = block.strip()

        if not block:
            continue

        lines = block.splitlines()

        if not lines:
            continue

        program_point = lines[0].strip()

        if not is_daikon_method_program_point(
            program_point
        ):
            continue

        signature = daikon_base_method(
            program_point
        )

        methods_by_signature[
            signature
        ].append(block)

    # Normalized key -> signatures
    normalized = defaultdict(list)

    for signature in methods_by_signature:

        key = parse_daikon_signature(
            signature
        )

        if key is not None:
            normalized[key].append(
                signature
            )

    return (
        dict(methods_by_signature),
        dict(normalized),
    )


# ============================================================
# OCA OBSERVED-HELD
# ============================================================

def load_oca_observed_held(project):

    base = OCA_BASE / project

    registry_path = (
        base / "daikonpp_registry.jsonl"
    )

    metrics_path = (
        base / "daikonpp_invariant_metrics.jsonl"
    )

    outcomes_path = (
        base / "daikonpp_outcomes.jsonl"
    )

    registry_records = read_jsonl(
        registry_path
    )

    metric_records = read_jsonl(
        metrics_path
    )

    outcome_records = read_jsonl(
        outcomes_path
    )

    registry = {
        x["id"]: x
        for x in registry_records
        if "id" in x
    }

    metrics = {
        x["id"]: x
        for x in metric_records
        if "id" in x
    }

    held_outcomes = []

    for o in outcome_records:

        if (
            o.get("verdict") == "HELD"
            and o.get("compiled") is True
            and o.get("executed") is True
        ):
            held_outcomes.append(o)

    by_method = defaultdict(list)

    missing_metadata = []

    registry_hits = 0
    metrics_fallback_hits = 0

    for o in held_outcomes:

        inv_id = o.get("id")

        metadata = registry.get(inv_id)

        source = "registry"

        if metadata is None:

            metadata = metrics.get(inv_id)
            source = "metrics"

        if metadata is None:

            missing_metadata.append(
                inv_id
            )
            continue

        if source == "registry":
            registry_hits += 1
        else:
            metrics_fallback_hits += 1

        element = metadata.get(
            "element"
        )

        kind = metadata.get(
            "kind"
        )

        expr = metadata.get(
            "expr"
        )

        if not element:
            missing_metadata.append(
                inv_id
            )
            continue

        by_method[element].append({
            "id": inv_id,
            "kind": kind,
            "expr": expr,
            "rationale":
                metadata.get(
                    "rationale"
                ),
            "file":
                metadata.get(
                    "file"
                ),
            "metadata_source":
                source,
        })

    diagnostics = {
        "registry_records":
            len(registry_records),

        "metric_records":
            len(metric_records),

        "outcomes_records":
            len(outcome_records),

        "held_outcomes":
            len(held_outcomes),

        "registry_hits":
            registry_hits,

        "metrics_fallback_hits":
            metrics_fallback_hits,

        "missing_metadata":
            len(missing_metadata),

        "eligible_methods":
            len(by_method),
    }

    return (
        dict(by_method),
        diagnostics,
        missing_metadata,
    )


# ============================================================
# OUTPUT
# ============================================================

def render_match(
    project,
    index,
    oca_method,
    oca_invariants,
    daikon_signature,
    daikon_blocks,
):

    out = []

    out.append(
        "=" * 110
    )

    out.append(
        f"SAMPLE {index}/10"
    )

    out.append(
        "=" * 110
    )

    out.append(
        f"PROJECT: {project}"
    )

    out.append("")

    out.append(
        f"OCA METHOD: {oca_method}"
    )

    out.append(
        f"DAIKON METHOD: {daikon_signature}"
    )

    out.append("")

    out.append(
        "-" * 110
    )

    out.append(
        "OCA OBSERVED-HELD INVARIANTS"
    )

    out.append(
        "-" * 110
    )

    for inv in oca_invariants:

        out.append(
            f"[{inv.get('kind')}] "
            f"{inv.get('expr')}"
        )

        out.append(
            f"ID: {inv.get('id')}"
        )

        if inv.get("rationale"):
            out.append(
                "Rationale: "
                + inv["rationale"]
            )

        if inv.get("file"):
            out.append(
                "Source file: "
                + inv["file"]
            )

        out.append("")

    out.append(
        "-" * 110
    )

    out.append(
        "DAIKON INVARIANTS"
    )

    out.append(
        "-" * 110
    )

    for block in daikon_blocks:

        out.append(
            DAIKON_SEPARATOR
        )

        out.append(
            block
        )

        out.append("")

    out.append("")

    return "\n".join(out)


# ============================================================
# MAIN
# ============================================================

def main():

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "-n",
        "--num-methods",
        type=int,
        default=10,
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=42,
    )

    parser.add_argument(
        "--output-dir",
        default="oca_daikon_matched_samples",
    )

    args = parser.parse_args()

    if args.num_methods <= 0:
        raise SystemExit(
            "--num-methods must be > 0"
        )

    output_dir = Path(
        args.output_dir
    )

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    # Global fixed seed.
    rng = random.Random(
        args.seed
    )

    combined = []

    summary_rows = []

    manifest_rows = []

    rejection_rows = []

    for project in PROJECTS:

        print()
        print("=" * 80)
        print(
            f"PROJECT: {project}"
        )
        print("=" * 80)

        # -----------------------
        # OCA
        # -----------------------

        (
            oca_methods,
            diagnostics,
            missing_metadata,
        ) = load_oca_observed_held(
            project
        )

        print(
            "OCA held invariants: "
            f"{diagnostics['held_outcomes']}"
        )

        print(
            "OCA eligible methods: "
            f"{diagnostics['eligible_methods']}"
        )

        print(
            "HELD metadata via registry: "
            f"{diagnostics['registry_hits']}"
        )

        print(
            "HELD metadata via metrics fallback: "
            f"{diagnostics['metrics_fallback_hits']}"
        )

        print(
            "HELD IDs without metadata: "
            f"{diagnostics['missing_metadata']}"
        )

        # -----------------------
        # DAIKON
        # -----------------------

        daikon_path = Path(
            DAIKON_FILES[project]
        )

        if not daikon_path.exists():
            raise SystemExit(
                f"Missing Daikon file: "
                f"{daikon_path}"
            )

        (
            daikon_methods,
            daikon_normalized,
        ) = parse_daikon_file(
            daikon_path
        )

        print(
            "Daikon methods: "
            f"{len(daikon_methods)}"
        )

        # -----------------------
        # RANDOM OCA ORDER
        # -----------------------

        candidates = sorted(
            oca_methods.keys()
        )

        rng.shuffle(
            candidates
        )

        selected = []
        rejected = []

        attempts = 0

        for oca_method in candidates:

            if (
                len(selected)
                >= args.num_methods
            ):
                break

            attempts += 1

            key = parse_oca_element(
                oca_method
            )

            if key is None:

                rejected.append({
                    "method":
                        oca_method,
                    "reason":
                        "OCA_PARSE_FAILED",
                })

                continue

            matches = daikon_normalized.get(
                key,
                [],
            )

            if len(matches) == 0:

                rejected.append({
                    "method":
                        oca_method,
                    "reason":
                        "NO_DAIKON_MATCH",
                })

                continue

            if len(matches) > 1:

                rejected.append({
                    "method":
                        oca_method,
                    "reason":
                        "AMBIGUOUS_DAIKON_MATCH:"
                        + "|".join(matches),
                })

                continue

            daikon_signature = (
                matches[0]
            )

            selected.append({
                "oca_method":
                    oca_method,

                "oca_invariants":
                    oca_methods[
                        oca_method
                    ],

                "daikon_signature":
                    daikon_signature,

                "daikon_blocks":
                    daikon_methods[
                        daikon_signature
                    ],
            })

        # -----------------------
        # REPORT
        # -----------------------

        print(
            f"Random candidates attempted: "
            f"{attempts}"
        )

        print(
            f"Rejected before reaching target: "
            f"{len(rejected)}"
        )

        print(
            f"Matched methods selected: "
            f"{len(selected)}"
        )

        if (
            len(selected)
            < args.num_methods
        ):
            print(
                "WARNING: could not obtain "
                f"{args.num_methods} matched "
                f"methods for {project}"
            )

        # -----------------------
        # PROJECT OUTPUT
        # -----------------------

        rendered = []

        for i, item in enumerate(
            selected,
            1,
        ):

            text = render_match(
                project,
                i,
                item["oca_method"],
                item["oca_invariants"],
                item[
                    "daikon_signature"
                ],
                item[
                    "daikon_blocks"
                ],
            )

            rendered.append(
                text
            )

            combined.append(
                text
            )

            manifest_rows.append({
                "project":
                    project,

                "sample_index":
                    i,

                "oca_method":
                    item[
                        "oca_method"
                    ],

                "daikon_method":
                    item[
                        "daikon_signature"
                    ],

                "oca_observed_held_count":
                    len(
                        item[
                            "oca_invariants"
                        ]
                    ),

                "daikon_program_point_count":
                    len(
                        item[
                            "daikon_blocks"
                        ]
                    ),
            })

        for r in rejected:

            rejection_rows.append({
                "project":
                    project,

                "oca_method":
                    r["method"],

                "reason":
                    r["reason"],
            })

        project_file = (
            output_dir
            / f"{project}-matched-sample.txt"
        )

        project_file.write_text(
            "\n".join(rendered)
            + "\n",
            encoding="utf-8",
        )

        summary_rows.append({
            "project":
                project,

            "oca_eligible_methods":
                len(oca_methods),

            "daikon_methods":
                len(daikon_methods),

            "random_attempts":
                attempts,

            "rejected":
                len(rejected),

            "selected":
                len(selected),
        })

        print(
            f"Output: {project_file}"
        )

    # ========================================================
    # COMBINED OUTPUT
    # ========================================================

    combined_file = (
        output_dir
        / "all-projects-matched-sample.txt"
    )

    combined_file.write_text(
        "\n".join(combined)
        + "\n",
        encoding="utf-8",
    )

    # ========================================================
    # MANIFEST
    # ========================================================

    manifest_file = (
        output_dir
        / "selected-methods.tsv"
    )

    with open(
        manifest_file,
        "w",
        encoding="utf-8",
    ) as f:

        f.write(
            "project\t"
            "sample_index\t"
            "oca_method\t"
            "daikon_method\t"
            "oca_observed_held_count\t"
            "daikon_program_point_count\n"
        )

        for r in manifest_rows:

            f.write(
                f"{r['project']}\t"
                f"{r['sample_index']}\t"
                f"{r['oca_method']}\t"
                f"{r['daikon_method']}\t"
                f"{r['oca_observed_held_count']}\t"
                f"{r['daikon_program_point_count']}\n"
            )

    # ========================================================
    # REJECTIONS
    # ========================================================

    rejection_file = (
        output_dir
        / "rejected-oca-methods.tsv"
    )

    with open(
        rejection_file,
        "w",
        encoding="utf-8",
    ) as f:

        f.write(
            "project\t"
            "oca_method\t"
            "reason\n"
        )

        for r in rejection_rows:

            f.write(
                f"{r['project']}\t"
                f"{r['oca_method']}\t"
                f"{r['reason']}\n"
            )

    # ========================================================
    # SUMMARY
    # ========================================================

    summary_file = (
        output_dir
        / "sampling-summary.tsv"
    )

    with open(
        summary_file,
        "w",
        encoding="utf-8",
    ) as f:

        f.write(
            "project\t"
            "oca_eligible_methods\t"
            "daikon_methods\t"
            "random_attempts\t"
            "rejected\t"
            "selected\n"
        )

        for r in summary_rows:

            f.write(
                f"{r['project']}\t"
                f"{r['oca_eligible_methods']}\t"
                f"{r['daikon_methods']}\t"
                f"{r['random_attempts']}\t"
                f"{r['rejected']}\t"
                f"{r['selected']}\n"
            )

    print()
    print("=" * 80)
    print("DONE")
    print("=" * 80)

    print(
        f"Combined sample: {combined_file}"
    )

    print(
        f"Selected-method manifest: {manifest_file}"
    )

    print(
        f"Rejected methods: {rejection_file}"
    )

    print(
        f"Summary: {summary_file}"
    )


if __name__ == "__main__":
    main()
