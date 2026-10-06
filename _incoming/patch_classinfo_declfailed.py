#!/usr/bin/env python3
"""
Bug 4 fix (decl/data desync), part 1 of 2: add a `declFailed` flag to
ClassInfo, next to the existing `shouldInclude` flag.

Run from the root of the daikon clone (same convention as
patch_chicory_runtime.py / patch_dtracewriter.py), AFTER
patch_chicory_runtime.py (Bug 1) has already been applied, and before
`make daikon.jar`:

    cd "$DAIKONDIR"
    python3 /path/to/patch_classinfo_declfailed.py

See patch_runtime_declfailed.py for the matching Runtime.java changes that
actually make use of this flag.
"""
import sys
from pathlib import Path

def main():
    path = Path("java") / "daikon" / "chicory" / "ClassInfo.java"
    content = path.read_text()

    old = """  /** True if any methods in this class were instrumented. */
  public boolean shouldInclude = false;

  /** Mapping from field name to string representation of its value. */"""
    new = """  /** True if any methods in this class were instrumented. */
  public boolean shouldInclude = false;

  /**
   * True if Runtime.process_new_classes() failed to process (and therefore skipped printing the
   * declaration for) this class. Once set, Runtime.enter()/exit() must skip writing trace data
   * for this class's methods too, or the missing declaration will cause daikon.Daikon to fail
   * later with "No declaration was provided for program point ...".
   */
  public boolean declFailed = false;

  /** Mapping from field name to string representation of its value. */"""

    count = content.count(old)
    if count != 1:
        print(f"ERROR: expected exactly 1 match, found {count}", file=sys.stderr)
        sys.exit(1)

    path.write_text(content.replace(old, new))
    print(f"patched {path}")

if __name__ == "__main__":
    main()
