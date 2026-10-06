#!/usr/bin/env python3
import sys
import gzip

PPT_MARKERS = (":::ENTER", ":::EXIT", ":::OBJECT", ":::CLASS")
META_PREFIXES = ("ppt-type", "parent ", "var-comparability", "decl-version")


def looks_like_ppt_header(line: str) -> bool:
    return any(m in line for m in PPT_MARKERS)


def is_blank_or_comment(line: str) -> bool:
    s = line.strip()
    return s == "" or s.startswith("//") or s.startswith("#")


def process_header_line(raw, fout, state_holder):
    fout.write(raw + "\n")
    if is_blank_or_comment(raw) or looks_like_ppt_header(raw):
        state_holder[0] = "HEADER"
    elif raw == "this_invocation_nonce":
        state_holder[0] = "EXPECT_NONCE_VALUE"
    elif raw.startswith(META_PREFIXES):
        state_holder[0] = "HEADER"
    else:
        state_holder[0] = "EXPECT_VALUE"


def repair(in_path, out_path, audit_path, sample_limit=200):
    repairs = 0
    state_holder = ["HEADER"]
    pending_name = [None]
    samples = []

    with gzip.open(in_path, "rt", encoding="utf-8", errors="surrogateescape") as fin, \
         gzip.open(out_path, "wt", encoding="utf-8", errors="surrogateescape") as fout:
        for lineno, line in enumerate(fin, 1):
            raw = line.rstrip("\n")
            state = state_holder[0]

            if state == "EXPECT_VALUE":
                if looks_like_ppt_header(raw) or is_blank_or_comment(raw):
                    fout.write("nonsensical\n")
                    fout.write("2\n")
                    repairs += 1
                    if len(samples) < sample_limit:
                        samples.append((lineno, pending_name[0], raw))
                    process_header_line(raw, fout, state_holder)
                else:
                    fout.write(raw + "\n")
                    state_holder[0] = "EXPECT_MODBIT"
                continue

            if state == "EXPECT_MODBIT":
                fout.write(raw + "\n")
                state_holder[0] = "HEADER"
                continue

            if state == "EXPECT_NONCE_VALUE":
                fout.write(raw + "\n")
                state_holder[0] = "HEADER"
                continue

            if state == "HEADER":
                if not (is_blank_or_comment(raw) or looks_like_ppt_header(raw) or raw == "this_invocation_nonce" or raw.startswith(META_PREFIXES)):
                    pending_name[0] = raw
                process_header_line(raw, fout, state_holder)

        if state_holder[0] == "EXPECT_VALUE":
            fout.write("nonsensical\n")
            fout.write("2\n")
            repairs += 1
            if len(samples) < sample_limit:
                samples.append(("EOF", pending_name[0], "<end of file>"))

    with open(audit_path, "w") as af:
        for lineno, name, trigger in samples:
            af.write(f"line {lineno}: name={name!r} triggered-by={trigger!r}\n")

    return repairs


if __name__ == "__main__":
    n = repair(sys.argv[1], sys.argv[2], sys.argv[3])
    print(f"repairs made: {n}")
