import json
import os
import re
import subprocess
from pathlib import Path

from d4j import run

RELAXED = {
    "DP_QUALITY_FILTER_SELF_COMPARISON": "false",
    "DP_QUALITY_FILTER_UNKNOWN_IDENTIFIER": "false",
    "DP_QUALITY_FILTER_REQUIRE_RESULT_AT_EXIT": "false",
    "DP_QUALITY_FILTER_REQUIRE_IN_SCOPE_NAME": "false",
    "DP_AUTOFILTER_MAX_MODIFY_PASSES": "200",
    "DP_AUTOFILTER_MAX_EXTRA_PASSES": "150",
}


def write_script(path, body):
    Path(path).write_text("#!/usr/bin/env bash\nset -e\n" + body + "\n")
    os.chmod(path, 0o755)
    return path


def full_suite_runner(out_dir):
    return write_script(Path(out_dir) / "run_tests.sh", "defects4j test")


def selected_tests_runner(out_dir, tests):
    return write_script(Path(out_dir) / "run_selected_tests.sh",
                        "\n".join(f"defects4j test -t {c}::{m}" for c, m in tests))


def compile_script(out_dir):
    return write_script(Path(out_dir) / "compile.sh", "defects4j compile")


def run_oca(oca_jar, work, info, out_dir, label, runner, cassettes, replay, relaxed, maxk=5):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update({
        "DP_OPENAI_MODEL": "gpt-4.1-mini",
        "DP_PROMPT_STRATEGY": "fewshot",
        "DP_CONTEXTS": "METHOD_BODY,SCOPE,CLASS_DOC",
        "DP_TEST_FILTER": "0",
        "DP_LLM_CASSETTES": str(cassettes),
        "DP_DISABLE_REAL_LLM": "1" if replay else "0",
        "DP_LLM_TOTAL_TIMEOUT_SEC": "14400",
        "DP_LLM_REQ_TIMEOUT_SEC": "30",
        "DP_REGISTRY": str(out_dir / f"registry_{label}.jsonl"),
        "DP_OUTCOMES": str(out_dir / f"outcomes_{label}.jsonl"),
        "DP_REGISTRY_RESET": "true",
        "DP_WORKDIR": str(out_dir / f"workdir_{label}"),
        "DP_EXTERNAL_COMPILE_CP": str(Path(work) / info["bin"]),
        "DP_COMPILE_MAIN_SCRIPT": str(compile_script(out_dir)),
        "DP_COMPILE_TEST_SCRIPT": str(compile_script(out_dir)),
    })
    if relaxed:
        env.update(RELAXED)
    run(["java", "-Xmx4g", "-jar", oca_jar, "--external-project", "--project-root", work,
         "--main-src", info["src"], "--test-src", info["tests"], "--runner-script", runner, str(maxk)],
        cwd=work, env=env, log=out_dir / f"{label}.log")
    return out_dir / f"registry_{label}.jsonl", out_dir / f"outcomes_{label}.jsonl"


def records(path):
    text, dec, i, out = Path(path).read_text(errors="replace"), json.JSONDecoder(strict=False), 0, []
    while i < len(text):
        while i < len(text) and text[i].isspace():
            i += 1
        if i >= len(text):
            break
        obj, i = dec.raw_decode(text, i)
        out.append(obj)
    return out


def key(r):
    return f'{r["kind"]}|{r["element"]}|{" ".join(r["expr"].split())}'


def verdicts(registry, outcomes):
    ids = {r["id"]: key(r) for r in records(registry)}
    return {ids[o["id"]]: o["verdict"] for o in records(outcomes) if o["id"] in ids}


def disable_tests(test_src, tests):
    for cls, method in tests:
        f = Path(test_src) / (cls.split("$")[0].replace(".", "/") + ".java")
        text = f.read_text(errors="replace")
        text, n = re.subn(rf"(public\s+void\s+){re.escape(method)}(\s*\()",
                          rf"@org.junit.Ignore \g<1>disabled_{method}\2", text, count=1)
        if not n:
            raise RuntimeError(f"cannot disable {cls}::{method}")
        f.write_text(text)
