# RQ1 and RQ2: Prompt Strategy and Context Configuration (Section 3, Tables 2 and 4)

| File | Goal |
|---|---|
| `run_prompt_study.sh` | RQ1: runs Oca on every benchmark with each prompt strategy, using the Local context. |
| `run_context_study.sh` | RQ2: runs Oca on every benchmark with each context configuration, using the Few-Shot strategy. |
| `submit_prompt_study.sh`, `submit_context_study.sh` | SLURM jobs that run the two studies. |
| `PROMPTS.md` | The exact prompt template of every strategy. |
| `results/` | Outcomes of every run (see below). |
| `summarize_studies.py` | Prints Tables 2 and 4. |

Both studies use `gpt-4.1-mini` with K = 5.

| Prompt strategy (Table 1) | `DP_PROMPT_STRATEGY` |
|---|---|
| Zero-Shot | `baseline` |
| Few-Shot | `fewshot` |
| Chain-of-Thought | `cot` |
| Stepwise | `stepwise` |
| Self-Refinement | `self_refine` |
| Multi-Sample | `multi_sample` |

| Context configuration (Table 3) | `DP_CONTEXTS` |
|---|---|
| Local | `METHOD_BODY,SCOPE` |
| Documented | `METHOD_BODY,SCOPE,METHOD_JAVADOC` |
| Class-Aware | `METHOD_BODY,SCOPE,CLASS_DOC` |
| Type-Aware | `METHOD_BODY,SCOPE,TYPE_DOC` |
| Usage-Aware | `METHOD_BODY,SCOPE,CALL_SITE` |
| Example-Driven | `METHOD_BODY,SCOPE,IO_EXAMPLES` |

## Running

```bash
export OPENAI_API_KEY=...
sbatch submit_prompt_study.sh
sbatch submit_context_study.sh
```

Requires Java 23 and Maven. The scripts build Oca from `oca-artifact/` (or `OCA_DIR`) and run it on each
benchmark through `run_oca_<benchmark>.sh`, which builds the project and runs its test suite. Each run writes
`oca_registry.jsonl`, `oca_outcomes.jsonl`, and `run.log` to `resultsOfPromptStudy/<strategy>/<benchmark>/` or
`resultsOfContextStudy/<configuration>/<benchmark>/`.

## Results

`results/<study>/<configuration>/<project>/` holds the output of one Oca run:

| File | Contents |
|---|---|
| `registry.jsonl.gz` | Every accepted candidate: `id`, `expr`, `rationale`, `kind`, `element`, `file`. |
| `outcomes.jsonl.gz` | The verdict of every candidate: `HELD`, `FALSIFIED`, `NEVER_EXECUTED`, or `FAILED_TO_COMPILE`. |
| `invariant_metrics.jsonl.gz` | For each held invariant, the variables it relates and the methods it calls. |

`<study>` is `prompt` (Table 2, one folder per `DP_PROMPT_STRATEGY`) or `context` (Table 4, one folder per
configuration). `results/run_summaries.csv` gives the totals Oca reports at the end of each run. The Local
configuration is the Few-Shot run of the prompt study, and the Class-Aware row counts the `HELD` verdicts in
`outcomes.jsonl.gz`, as Table 5 does.

| Command | Prints |
|---|---|
| `python3 summarize_studies.py` | Tables 2 and 4 |
| `python3 summarize_studies.py --check` | Also compare every number with the paper; exits with status 1 on a mismatch |
