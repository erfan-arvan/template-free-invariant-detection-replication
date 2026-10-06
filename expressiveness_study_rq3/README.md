# RQ3: Expressiveness (Section 5.2, Table 5)

An invariant is expressive if it calls a project-specific method (PSPM) or relates more than three variables
(V>3). Both tools run on the same project version and test suite; Oca uses the Few-Shot prompt strategy with the
Class-Aware context.

| File | Contents |
|---|---|
| `summarize_expressiveness.py` | Prints Table 5. |
| `daikon_counts.csv` | Number of invariants Daikon reports per project (N_D), at method entries and exits. |
| `benchmarks/` | `CountDaikonInvariants.java`, which counts the printable invariants at entry and exit program points of a Daikon `.inv.gz` file, and the SLURM job `count_daikon.sh` that runs it. |
| `defects4j/` | Scripts that run Oca and Daikon on the Defects4J projects (see `defects4j/README.md`). |

The Oca results of the benchmark projects are the Class-Aware runs in
`../prompt_context_study_rq1_rq2/results/context/class_aware/`. For each held invariant,
`invariant_metrics.jsonl.gz` records the number of variables it relates (`varCount2`) and the project-specific
methods it calls (`pspmCount`).

| Command | Prints |
|---|---|
| `python3 summarize_expressiveness.py` | Table 5 |
| `python3 summarize_expressiveness.py --check` | Also compare every number with the paper; exits with status 1 on a mismatch |
