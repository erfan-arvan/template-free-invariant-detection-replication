#!/usr/bin/env python3
"""
Bug 5 fix: DTraceWriter.traverseValue() has a second unguarded reflective
call, sibling to the one Bug 3 already fixed. Bug 3 protects
curInfo.getDTraceValueString(val) (serializing a variable's own value); this
protects child.getMyValFromParentVal(val) a few lines later (extracting a
CHILD's value -- e.g. a field or array element -- to recurse into).

Both are reflective operations on a live object that another thread may be
concurrently mutating, and both can throw. Left unguarded, the exception
propagates out of traverseValue()/traverse() and out of
methodEntry()/methodExit() (which have no catch of their own), truncating
that one trace record mid-write. Since ENTER and EXIT don't necessarily hit
the race at the same instant, this can also leave an EXIT with no matching
ENTER elsewhere in the file.

This happened concretely on netty-full's re-traced trace:
  - "Mismatch between declaration and trace. Expected variable
    io.netty.util.concurrent.DefaultPromiseTest.logger, got
    io.netty.util.internal.logging.LocationAwareSlf4JLogger.debug(...):::ENTER"
  - "Didn't find call with nonce ... to match
    io.netty.util.internal.logging.LocationAwareSlf4JLogger.debug(...):::EXIT..."
Both point at the same root cause: traversing the arbitrary Object argument
passed to a logging call, racing with concurrent mutation elsewhere in
netty's heavily parallel test suite.

Run from the root of the daikon clone (same convention as
patch_chicory_runtime.py / patch_dtracewriter.py / the Bug 4 scripts), AFTER
patch_dtracewriter.py (Bug 3) has already been applied, and before
`make daikon.jar`:

    cd "$DAIKONDIR"
    python3 /path/to/patch_dtracewriter_bug5.py

Verified: built daikon.jar with this fix, wrote a white-box test forcing a
child's value-extraction to throw deterministically, and confirmed:
  - Without this patch: the exception propagates straight out of
    traverseValue(), matching the real netty crash's stack shape exactly.
  - With this patch: traversal completes, writing "nonsensical"/2 as a
    placeholder for the throwing child, keeping the record well-formed.
"""
import sys
from pathlib import Path


def main():
    path = Path("java") / "daikon" / "chicory" / "DTraceWriter.java"
    content = path.read_text()

    old = """    if (curInfo.dTraceShouldPrintChildren()) {
      for (DaikonVariableInfo child : curInfo) {
        Object childVal = child.getMyValFromParentVal(val);
        traverseValue(mi, child, childVal);
      }
    }"""
    new = """    if (curInfo.dTraceShouldPrintChildren()) {
      for (DaikonVariableInfo child : curInfo) {
        Object childVal;
        try {
          childVal = child.getMyValFromParentVal(val);
        } catch (Throwable t) {
          // Same hazard as the getDTraceValueString() call above: this
          // reflectively pulls a child value (e.g. a field or array element)
          // out of a live object that another thread may be concurrently
          // mutating, and can throw. Left unguarded, the exception propagates
          // out of traverseValue()/traverse() and out of methodEntry()/
          // methodExit(), which have no catch of their own -- silently
          // truncating this record (missing its remaining variables and
          // closing blank line) and, since ENTER and EXIT don't necessarily
          // hit this race at the same time, can leave an EXIT with no
          // matching ENTER. Substitute the same nonsensical placeholder
          // value used elsewhere and keep going instead of corrupting the
          // rest of the trace.
          childVal = nonsenseValue;
        }
        traverseValue(mi, child, childVal);
      }
    }"""

    count = content.count(old)
    if count != 1:
        print(f"ERROR: expected exactly 1 match, found {count}", file=sys.stderr)
        sys.exit(1)

    path.write_text(content.replace(old, new))
    print(f"patched {path}")


if __name__ == "__main__":
    main()
