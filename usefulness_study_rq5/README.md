# RQ5: Usefulness via Simulated Property-Based Testing (Section 5.4, Table 7)

Do the inferred invariants expose real bugs? For the latest five bugs of five Defects4J projects
(Cli, Codec, Collections, Gson, Math; 25 bugs), each tool:

1. infers invariants from the buggy version's test suite **without** the bug-revealing tests, keeping the held ones;
2. runs the bug-revealing tests and keeps the invariants they falsify;
3. checks those invariants on the fixed version's full test suite and keeps the ones it does not falsify.

A bug is **exposed** if at least one invariant survives all three steps.

| File | Contents |
|---|---|
| `exposed.csv` | Bugs exposed per project and tool (Table 7). |
| `hits.csv` | Invariants that expose the bugs: `tool`, `project`, `bug`, `program_point`, `method`, `invariant`. |
| `summarize_hits.py` | Prints Table 7 and the invariants. |
| `pipeline/` | The scripts that run the three steps for both tools (see `pipeline/README.md`). |
| `pilot/` | The pilot run on the latest bug of each Defects4J project, used to select the subject projects (section 5.1). |

## Reproducing Table 7

Requires only Python 3.

| Command | Prints |
|---|---|
| `python3 summarize_hits.py` | Table 7 |
| `python3 summarize_hits.py --hits` | Also list the invariants that expose each bug |
| `python3 summarize_hits.py --check` | Also compare every number with the paper; exits with status 1 on a mismatch |

## Expected output

```
Table 7: Bugs exposed per project (RQ5)
  Project      Bugs       Oca    Daikon
  Cli             5         0         0
  Codec           5         2         1
  Collections     5         5         1
  Gson            5         1         0
  Math            5         1         2
  Total          25   9 (36%)   4 (16%)
```

## Running the pipeline

`pipeline/submit_usefulness.sh` is a SLURM array job with one task per bug in `pipeline/bugs.csv`.
Each task runs `oca_usefulness.py` and then `daikon_usefulness.py`, which write
`results/{oca,daikon}/<bug>/result.json`. `pipeline/summarize_usefulness.py` tabulates these files.
Oca uses `gpt-4.1-mini` with K = 5, the Few-Shot prompt strategy, and the Class-Aware context.
Steps 2 and 3 replay the LLM responses recorded in step 1.
