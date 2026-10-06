#!/usr/bin/env python3
"""
Streams a Daikon dtrace file and repairs a specific Chicory bug: a
variable's value+modbit lines silently dropped (DaikonVariableInfo.
getDTraceValueString / DTraceWriter.traverseValue -- the name line gets
written, then an exception during value serialization, e.g. a
concurrently-mutated array field, causes the value+modbit lines to never
be written at all).

Detection: a genuine ppt-header line (contains ':::ENTER', ':::EXIT',
':::OBJECT', ':::CLASS') or a blank/comment line should never legitimately
appear where a value is expected -- there's always a value line first. So
whenever we're expecting a value but see one of those instead, the previous
name's value+modbit got dropped: insert "nonsensical" / "2", the same
placeholder the DTraceWriter fix produces, then continue normally.

Handles daikon's dtrace record shapes:
  - ppt header / blank / comment lines: pass through, state stays HEADER
  - "this_invocation_nonce": name only, followed by exactly ONE value line
    (no modbit) -- handled as its own state so it's never mistaken for an
    ordinary variable name
  - ppt-type / parent / var-comparability / decl-version metadata lines:
    pass through, state stays HEADER
  - ordinary variable: name line, then value line, then modbit line

This is a targeted line-oriented repair for this one known corruption
shape, not a general dtrace validator. Streams gzip in and out; never loads
the whole file into memory.
"""
import sys
import gzip

PPT_MARKERS = (":::ENTER", ":::EXIT", ":::OBJECT", ":::CLASS")
META_PREFIXES = ("ppt-type", "parent ", "var-comparability", "decl-version")


def looks_like_ppt_header(line: str) -> bool:
    return any(m in line for m in PPT_MARKERS)


def is_blank_or_comment(line: str) -> bool:
    s = line.strip()
    return s == "" or s.startswith("//") or s.startswith("#")


def process_header_line(raw: str, fout, state_holder):
    """Handle a line known to be in HEADER state (or repaired into it). Writes it and sets next state."""
    fout.write(raw + "\n")
    if is_blank_or_comment(raw) or looks_like_ppt_header(raw):
        state_holder[0] = "HEADER"
    elif raw == "this_invocation_nonce":
        state_holder[0] = "EXPECT_NONCE_VALUE"
    elif raw.startswith(META_PREFIXES):
        state_holder[0] = "HEADER"
    else:
        state_holder[0] = "EXPECT_VALUE"


def repair(in_path: str, out_path: str) -> int:
    repairs = 0
    state_holder = ["HEADER"]

    with gzip.open(in_path, "rt", encoding="utf-8", errors="surrogateescape") as fin, \
         gzip.open(out_path, "wt", encoding="utf-8", errors="surrogateescape") as fout:
        for line in fin:
            raw = line.rstrip("\n")
            state = state_holder[0]

            if state == "EXPECT_VALUE":
                if looks_like_ppt_header(raw) or is_blank_or_comment(raw):
                    fout.write("nonsensical\n")
                    fout.write("2\n")
                    repairs += 1
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

            # state == HEADER
            process_header_line(raw, fout, state_holder)

        # EOF: if the file ends mid-record (a name line with nothing after
        # it), the dropped value+modbit never got a following line to be
        # detected against inside the loop. Repair it here too.
        if state_holder[0] == "EXPECT_VALUE":
            fout.write("nonsensical\n")
            fout.write("2\n")
            repairs += 1

    return repairs


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: repair_dtrace.py <in.dtrace.gz> <out.dtrace.gz>", file=sys.stderr)
        sys.exit(1)
    n = repair(sys.argv[1], sys.argv[2])
    print(f"repairs made: {n}")
