import os
import re
import shutil
import subprocess
from pathlib import Path

JAVA_XMX = os.environ.get("JAVA_XMX", "64g")
OMIT = r"junit\.|org\.junit\.|sun\.|java\.|com\.sun\.proxy"
DAIKON_CONFIG = ["daikon.split.PptSplitter.disable_splitting=true"]
EXTRA_CONFIG = {"Gson": ["daikon.inv.ternary.threeScalar.LinearTernary.enabled=false",
                         "daikon.inv.ternary.threeScalar.LinearTernaryFloat.enabled=false"]}
HERE = Path(__file__).resolve().parent


def run(cmd, cwd=None, env=None, log=None):
    p = subprocess.run([str(c) for c in cmd], cwd=cwd, env=env, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, text=True, errors="replace")
    if log:
        Path(log).parent.mkdir(parents=True, exist_ok=True)
        with open(log, "a") as f:
            f.write(p.stdout)
    if p.returncode != 0:
        raise RuntimeError(f"{cmd[0]} {cmd[1] if len(cmd) > 1 else ''} failed:\n{p.stdout[-3000:]}")
    return p.stdout


def latest_bug(project):
    return str(max(int(x) for x in run(["defects4j", "bids", "-p", project]).split()))


def triggering_tests(project, bug):
    lines = run(["defects4j", "info", "-p", project, "-b", bug]).splitlines()
    out, inside = [], False
    for line in lines:
        if line.strip() == "Root cause in triggering tests:":
            inside = True
            continue
        if inside:
            m = re.match(r"\s*-\s*(\S+)::(\S+)", line)
            if m:
                out.append((m.group(1), m.group(2)))
            elif line.strip().startswith("---"):
                break
    return out


def test_classes(bin_tests):
    base = Path(bin_tests)
    return sorted(".".join(p.relative_to(base).with_suffix("").parts)
                  for p in base.rglob("*.class") if "$" not in p.name)


def package_pattern(src_dir):
    pkgs = set()
    for f in Path(src_dir).rglob("*.java"):
        m = re.search(r"^\s*package\s+([\w.]+)\s*;", f.read_text(errors="replace"), re.M)
        if m:
            pkgs.add(m.group(1))
    parts = [p.split(".") for p in pkgs]
    prefix = []
    for level in zip(*parts):
        if len(set(level)) != 1:
            break
        prefix.append(level[0])
    return "^(?:" + re.escape(".".join(prefix)) + r")\."


def prepare(project, version, work, log):
    shutil.rmtree(work, ignore_errors=True)
    run(["defects4j", "checkout", "-p", project, "-v", version, "-w", work], log=log)
    run(["defects4j", "compile"], cwd=work, log=log)
    info = {k: run(["defects4j", "export", "-p", p], cwd=work).strip() for k, p in (
        ("src", "dir.src.classes"), ("tests", "dir.src.tests"), ("bin_tests", "dir.bin.tests"),
        ("bin", "dir.bin.classes"), ("cp", "cp.test"))}
    if not test_classes(Path(work) / info["bin_tests"]):
        run(["defects4j", "compile"], cwd=work, log=log)
    info["classes"] = test_classes(Path(work) / info["bin_tests"])
    return info


def compile_runner(cp, out_dir, log):
    out = Path(out_dir) / "runner-classes"
    out.mkdir(parents=True, exist_ok=True)
    run(["javac", "-nowarn", "-cp", cp, "-d", out, HERE / "SelectedTestsRunner.java"], log=log)
    return out


def chicory(daikon_jar, runner, cp, select, omit, specs, work, dest, log):
    name = Path(dest).name
    run(["java", f"-Xmx{JAVA_XMX}", "-cp", f"{runner}:{cp}:{daikon_jar}", "daikon.Chicory",
         f"--ppt-select-pattern={select}", f"--ppt-omit-pattern={omit}", f"--dtrace-file={name}",
         "SelectedTestsRunner", *specs], cwd=work, log=log)
    shutil.move(str(Path(work) / name), str(dest))
    return Path(dest)


def daikon_config(project):
    return [a for o in DAIKON_CONFIG + EXTRA_CONFIG.get(project, []) for a in ("--config_option", o)]


def infer(daikon_jar, project, select, trace, inv, text, log):
    run(["java", f"-Xmx{JAVA_XMX}", "-cp", daikon_jar, "daikon.Daikon", "--no_show_progress",
         *daikon_config(project), f"--ppt-select-pattern={select}", "-o", inv, trace], log=log)
    Path(text).write_text(run(["java", f"-Xmx{JAVA_XMX}", "-cp", daikon_jar, "daikon.PrintInvariants", inv]))


def falsified(daikon_jar, project, inv, trace, out_txt, log):
    run(["java", f"-Xmx{JAVA_XMX}", "-cp", daikon_jar, "daikon.tools.InvariantChecker", "--verbose",
         "--output", out_txt, *daikon_config(project), inv, trace], log=log)
    pat = re.compile(r"^At ppt (.*?), Invariant '(.*)' invalidated by sample")
    hits = set()
    for line in open(out_txt, errors="replace"):
        m = pat.match(line)
        if m:
            hits.add((m.group(1), m.group(2)))
    return hits
