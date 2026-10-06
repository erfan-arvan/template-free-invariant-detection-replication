#!/usr/bin/env python3
"""
Bug 4 fix (decl/data desync), part 2 of 2: make Runtime.java actually use
ClassInfo.declFailed (added by patch_classinfo_declfailed.py).

Background: Bug 1's fix (patch_chicory_runtime.py) stops a failure while
processing one class's declaration from crashing the whole instrumented
program -- it catches the exception and skips printing that class's decl.
But Runtime.enter()/exit() don't know the decl was skipped, so they go on
writing ENTER/EXIT/etc. trace DATA for that class's methods anyway. The
resulting dtrace then references a program point with no declaration, and
daikon.Daikon fails with:

    UserError: No declaration was provided for program point <class>.<method>:::ENTER

This happened concretely on dubbo-s5's fixed-jar retrace: Bug 1 caught a
ClassCircularityError for org.apache.dubbo.common.compiler.support.HelloServiceImpl12,
correctly skipped its declaration, but Runtime.enter()/exit() still wrote its
<clinit> ENTER/EXIT data, and daikon.Daikon then rejected the trace.

This patch makes three changes to Runtime.java:
  1. In the existing Bug 1 `catch (Throwable t)` block inside
     process_new_classes(), set `class_info.declFailed = true;` in addition
     to the existing warning print.
  2. In enter(), right after re-fetching `mi` (and before `mi.call_cnt++`),
     return early if `mi.class_info.declFailed`.
  3. In exit(), add the same fetch-and-check, at the equivalent point
     (right after process_new_classes() is called, before any
     thread_to_callstack manipulation, so enter()/exit() stay symmetric --
     enter() never pushes onto that callstack for a declFailed class, so
     exit() must never try to pop from it either).

Run from the root of the daikon clone (same convention as
patch_chicory_runtime.py / patch_dtracewriter.py), AFTER both
patch_chicory_runtime.py (Bug 1) and patch_classinfo_declfailed.py have been
applied, and before `make daikon.jar`:

    cd "$DAIKONDIR"
    python3 /path/to/patch_runtime_declfailed.py

Verified (see accompanying write-up): built daikon.jar with this fix, ran a
white-box repro forcing one class's decl to fail via ClassInfo/MethodInfo
fixtures added directly to Runtime's queues, and confirmed:
  - Without this patch: the resulting dtrace contains ENTER/EXIT data for
    the failed class with no matching decl, and daikon.Daikon fails with
    exactly the "No declaration was provided" error above.
  - With this patch: no decl AND no data appear for the failed class, and
    daikon.Daikon completes cleanly ("Exiting Daikon.") on the same trace.
  - A control class that processes normally is unaffected either way.
"""
import sys
from pathlib import Path


def main():
    path = Path("java") / "daikon" / "chicory" / "Runtime.java"
    content = path.read_text()

    # --- Change 1: set the flag in the Bug 1 catch block. ---
    # Anchor on the catch block's opening line only (not its comment text,
    # which may have been worded differently by patch_chicory_runtime.py)
    # plus the distinctive warning message, to make sure we're patching the
    # right catch block and only once.
    catch_anchor = "} catch (Throwable t) {"
    count = content.count(catch_anchor)
    if count != 1:
        print(
            f"ERROR: expected exactly 1 occurrence of {catch_anchor!r} in Runtime.java "
            f"(the Bug 1 catch block in process_new_classes()), found {count}. "
            "Has patch_chicory_runtime.py been applied, or has the code changed?",
            file=sys.stderr,
        )
        sys.exit(1)
    if "Warning: Chicory failed to process class" not in content:
        print(
            "ERROR: could not find the Bug 1 warning message in Runtime.java. "
            "Has patch_chicory_runtime.py been applied?",
            file=sys.stderr,
        )
        sys.exit(1)
    if "class_info.declFailed = true;" in content:
        print("ERROR: Runtime.java already contains the Bug 4 patch (declFailed = true).", file=sys.stderr)
        sys.exit(1)

    content = content.replace(
        catch_anchor,
        catch_anchor + "\n        class_info.declFailed = true;",
        1,
    )

    # --- Change 2: enter() early-return. ---
    old_enter = """      synchronized (SharedData.methods) {
        mi = SharedData.methods.get(mi_index);
      }
      mi.call_cnt++;"""
    new_enter = """      synchronized (SharedData.methods) {
        mi = SharedData.methods.get(mi_index);
      }

      // If this class's declaration failed to be written (see
      // process_new_classes()), its trace data must be skipped too, or
      // daikon.Daikon will later fail with "No declaration was provided
      // for program point ...". Nothing has been pushed onto
      // thread_to_callstack yet for this call, so exit() must perform the
      // identical check at the same point, before it touches the callstack,
      // to stay symmetric.
      if (mi.class_info.declFailed) {
        return;
      }

      mi.call_cnt++;"""
    count = content.count(old_enter)
    if count != 1:
        print(f"ERROR: expected exactly 1 match for enter() anchor, found {count}", file=sys.stderr)
        sys.exit(1)
    content = content.replace(old_enter, new_enter)

    # --- Change 3: exit() early-return. ---
    old_exit = """      if (num_new_classes > 0) {
        process_new_classes();
      }

      // Skip this call if it was not sampled at entry to the method"""
    new_exit = """      if (num_new_classes > 0) {
        process_new_classes();
      }

      // Mirror the check in enter(): if this class's declaration failed to
      // be written, skip its trace data too. This must happen before any
      // thread_to_callstack manipulation below, since enter() never pushed
      // an entry for this call in that case either.
      synchronized (SharedData.methods) {
        mi = SharedData.methods.get(mi_index);
      }
      if (mi.class_info.declFailed) {
        return;
      }

      // Skip this call if it was not sampled at entry to the method"""
    count = content.count(old_exit)
    if count != 1:
        print(f"ERROR: expected exactly 1 match for exit() anchor, found {count}", file=sys.stderr)
        sys.exit(1)
    content = content.replace(old_exit, new_exit)

    path.write_text(content)
    print(f"patched {path}")


if __name__ == "__main__":
    main()
