#!/usr/bin/env python3

import json
import re
from pathlib import Path

ROOT = Path(".").resolve()
PARENT = ROOT.parent

METHODS = [
    (
        "apollo",
        "com.ctrip.framework.apollo.biz.entity.InstanceConfig#setInstanceId(long):void",
    ),
    (
        "dubbo",
        "org.apache.dubbo.common.URLBuilder#removeParameters(String):URLBuilder",
    ),
    (
        "hudi",
        "org.apache.hudi.table.action.deltacommit.JavaInsertDeltaCommitActionExecutor#execute():HoodieWriteMetadata<List<WriteStatus>>",
    ),
    (
        "netty",
        "io.netty.util.concurrent.UnorderedThreadPoolEventExecutor#shutdownGracefully():Future<?>",
    ),
    (
        "spring",
        "org.springframework.core.annotation.PackagesAnnotationFilter#matches(String):boolean",
    ),
    (
        "dubbo",
        "org.apache.dubbo.common.utils.UrlUtils#isMatchGlobPattern(String,String,URL):boolean",
    ),
    (
        "dubbo",
        "org.apache.dubbo.common.resource.GlobalResourcesRepository#getInstance():GlobalResourcesRepository",
    ),
    (
        "dubbo",
        "org.apache.dubbo.common.extension.ExtensionLoader#setLoadingStrategies(LoadingStrategy):void",
    ),
    (
        "dubbo",
        "org.apache.dubbo.common.convert.Converter#getSourceType():Class<S>",
    ),

    # Paper's motivating example
    (
        "spring",
        "org.springframework.core.convert.support.CollectionToObjectConverter#convert(Object,TypeDescriptor,TypeDescriptor):Object",
    ),
]


# Prefer the S5 IO files because those correspond to the context-study data.
IO_FILES = {
    "apollo": PARENT / "apollo-s5_io_examples.json",
    "dubbo": PARENT / "dubbo-s5_io_examples.json",
    "hudi": PARENT / "hudi-s5_io_examples.json",
    "netty": PARENT / "netty-s5_io_examples.json",
    "spring": PARENT / "spring-s5_io_examples.json",
}

CALLSITE_FILES = {
    "apollo": PARENT / "apollo_callsites.json",
    "dubbo": PARENT / "dubbo_callsites.json",
    "hudi": PARENT / "hudi_callsites.json",
    "netty": PARENT / "netty_callsites.json",
    "spring": PARENT / "spring_callsites.json",
}

REPOS = {
    "apollo": PARENT / "apollo",
    "dubbo": PARENT / "dubbo",
    "hudi": PARENT / "hudi",
    "netty": PARENT / "netty",
    "spring": PARENT / "spring-framework",
}


def load_json(path):
    if not path.exists():
        return {}
    with path.open(errors="replace") as f:
        return json.load(f)


def normalize_key(s):
    """
    Makes matching a little more tolerant of:
      - '$' nested-class vs flattened extractor names
      - whitespace
      - generic formatting
    """
    return (
        s.replace("$", "")
         .replace(" ", "")
         .replace("\\", "")
    )


def find_key(data, wanted):
    # Exact match first.
    if wanted in data:
        return wanted

    nw = normalize_key(wanted)

    # Normalized exact match.
    for k in data:
        if normalize_key(k) == nw:
            return k

    # Match by method name + class tail if extractor naming differs.
    method = wanted.split("#", 1)[1].split("(", 1)[0]
    clazz = wanted.split("#", 1)[0].split(".")[-1]

    candidates = [
        k for k in data
        if f"#{method}(" in k
        and clazz.replace("$", "") in k.replace("$", "")
    ]

    if len(candidates) == 1:
        return candidates[0]

    return None


def method_name(key):
    return key.split("#", 1)[1].split("(", 1)[0]


def class_simple_name(key):
    c = key.split("#", 1)[0].split(".")[-1]
    return c.split("$")[-1]


def find_java_file(repo, caller_key):
    cls = class_simple_name(caller_key)

    # Nested classes normally live in the outer-class source file.
    full_class = caller_key.split("#", 1)[0]
    outer = full_class.split(".")[-1].split("$")[0]

    names = [outer + ".java"]
    if cls != outer:
        names.append(cls + ".java")

    for name in names:
        matches = list(repo.rglob(name))
        if matches:
            return matches[0]

    return None


def extract_method(src, caller_key):
    """
    Heuristic brace-balanced extraction of the caller method.
    """
    name = method_name(caller_key)
    lines = src.splitlines()

    for i, line in enumerate(lines):
        if not re.search(r"\b" + re.escape(name) + r"\s*\(", line):
            continue

        # Look forward for method body's opening brace.
        signature = ""
        brace_line = None

        for j in range(i, min(len(lines), i + 15)):
            signature += lines[j] + "\n"

            if "{" in lines[j]:
                brace_line = j
                break

            if ";" in lines[j]:
                # Probably declaration without a body.
                break

        if brace_line is None:
            continue

        # Avoid obvious invocation lines.
        pre = " ".join(lines[i:brace_line + 1])
        declarationish = (
            re.search(
                r"\b(public|private|protected|static|final|synchronized|abstract|default)\b",
                pre,
            )
            or pre.strip().startswith(name + "(")
            or pre.strip().startswith("@")
        )

        # Package-private declarations are possible, so still allow if line
        # doesn't look like assignment/invocation.
        if not declarationish and "=" in lines[i]:
            continue

        depth = 0
        started = False
        end = brace_line

        for k in range(i, len(lines)):
            for ch in lines[k]:
                if ch == "{":
                    depth += 1
                    started = True
                elif ch == "}" and started:
                    depth -= 1

            if started and depth == 0:
                end = k
                break

        start = i

        # Include nearby annotations.
        while start > 0 and lines[start - 1].strip().startswith("@"):
            start -= 1

        return "\n".join(lines[start:end + 1])

    return None


io_cache = {}
cs_cache = {}

out = []

for idx, (project, wanted) in enumerate(METHODS, 1):

    out.append("=" * 120)
    out.append(f"METHOD {idx}/10")
    out.append(f"PROJECT: {project}")
    out.append(f"REQUESTED KEY: {wanted}")
    out.append("=" * 120)
    out.append("")

    # --------------------------------------------------------
    # IO EXAMPLES
    # --------------------------------------------------------

    if project not in io_cache:
        io_cache[project] = load_json(IO_FILES[project])

    io_data = io_cache[project]
    io_key = find_key(io_data, wanted)

    out.append("### IO EXAMPLES")

    if io_key is None:
        out.append("NO MATCHING IO-EXAMPLE KEY FOUND")
    else:
        out.append(f"Matched key: {io_key}")
        examples = io_data[io_key]
        out.append(f"Number of examples: {len(examples)}")
        out.append(json.dumps(examples, indent=2))

    out.append("")
    out.append("")

    # --------------------------------------------------------
    # CALL SITES
    # --------------------------------------------------------

    if project not in cs_cache:
        cs_cache[project] = load_json(CALLSITE_FILES[project])

    cs_data = cs_cache[project]
    cs_key = find_key(cs_data, wanted)

    out.append("### CALL SITES")

    if cs_key is None:
        out.append("NO MATCHING CALL-SITE KEY FOUND")
    else:
        out.append(f"Matched key: {cs_key}")
        sites = cs_data[cs_key]
        out.append(f"Number of call sites: {len(sites)}")

        for n, site in enumerate(sites, 1):
            out.append("")
            out.append(f"--- CALL SITE {n}/{len(sites)} ---")
            out.append(json.dumps(site, indent=2))

            caller = site.get("callerKey")

            if not caller:
                out.append("")
                out.append("CALLER IMPLEMENTATION: unavailable (callerKey is null)")
                continue

            repo = REPOS[project]
            java_file = find_java_file(repo, caller)

            out.append("")
            out.append(f"CALLER KEY: {caller}")

            if java_file is None:
                out.append("CALLER IMPLEMENTATION: source file not found")
                continue

            out.append(f"CALLER FILE: {java_file}")

            src = java_file.read_text(errors="replace")
            method_src = extract_method(src, caller)

            if method_src:
                out.append("")
                out.append("CALLER IMPLEMENTATION:")
                out.append(method_src)
            else:
                out.append("CALLER IMPLEMENTATION: method body could not be isolated")

    out.append("")
    out.append("")


output = ROOT / "qualitative_10_io_and_callsites.txt"
output.write_text("\n".join(out))

print(f"Wrote: {output}")
