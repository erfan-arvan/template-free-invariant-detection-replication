# Defects4J Runs (Section 5.2)

Oca and Daikon on the latest fixed version of Cli, Codec, Collections, Gson and Math.

| File | Goal |
|---|---|
| `run_oca.py` | Runs Oca on one project version (`--version f`, latest bug by default) and keeps its registry and outcomes. |
| `run_daikon.py` | Traces the full test suite with Chicory and infers invariants with Daikon on one project version. |
| `summarize.py` | Invariant, program-point and outcome counts per run. |
| `oca.py` | Helpers to run Oca on a Defects4J checkout and read its outputs. |
| `d4j.py` | Defects4J, Chicory and Daikon helpers. |
| `SelectedTestsRunner.java` | JUnit runner used under Chicory. |
| `submit_expressiveness.sh` | SLURM array job: one task per project, Oca then Daikon. |
