# usefulness

For each bug, the same three steps are applied to Oca and Daikon:
(1) infer candidate invariants from the buggy version's test suite without the bug-revealing tests and keep the held ones;
(2) run the bug-revealing tests and keep the candidates they falsify;
(3) check that those candidates are not falsified anywhere in the fixed version's full test suite.

| File | Goal |
|---|---|
| `bugs.csv` | The 25 bugs studied (latest 5 of Cli, Codec, Collections, Gson, Math). |
| `oca_usefulness.py` | The three steps for Oca on one bug; steps 2 and 3 replay the LLM responses recorded in step 1. Writes `results/oca/<bug>/result.json`. |
| `daikon_usefulness.py` | The three steps for Daikon on one bug (Chicory traces, Daikon inference, InvariantChecker). Writes `results/daikon/<bug>/result.json`. |
| `oca.py` | Helpers to run Oca on a Defects4J checkout and read its registry and outcomes. |
| `d4j.py` | Defects4J, Chicory and Daikon helpers. |
| `SelectedTestsRunner.java` | JUnit runner used under Chicory to run selected test classes and methods. |
| `submit_usefulness.sh` | SLURM array job: one task per bug, Oca then Daikon. |
| `summarize_usefulness.py` | Per-project detection counts for both tools. |
