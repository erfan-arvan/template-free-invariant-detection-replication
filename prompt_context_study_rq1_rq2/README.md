# RQ1 and RQ2: Prompt Strategy and Context Configuration (Section 3, Tables 2 and 4)

| File | Goal |
|---|---|
| `run_prompt_study.sh` | RQ1: runs Oca on every benchmark with each prompt strategy, using the Local context. |
| `run_context_study.sh` | RQ2: runs Oca on every benchmark with each context configuration, using the Few-Shot strategy. |
| `submit_prompt_study.sh`, `submit_context_study.sh` | SLURM jobs that run the two studies. |
| `PROMPTS.md` | The exact prompt template of every strategy. |

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

Requires Java 23 and Maven. Place the Oca sources in `oca-artifact/` (or set `OCA_DIR`) and the
benchmark runner scripts `run_oca_<benchmark>.sh` next to these scripts. Each run writes
`results<Study>/<config>/<benchmark>/` with `oca_registry.jsonl`, `oca_outcomes.jsonl`, and `run.log`.
