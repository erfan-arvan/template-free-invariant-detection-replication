# Replication Package: Template-Free Dynamic Invariant Detection

This package contains Oca, a dynamic invariant detector that obtains candidate invariants from an LLM
instead of a fixed template grammar, together with the data and scripts for every study in the paper.

## Contents

| Directory | Paper | Contents |
|---|---|---|
| [`oca-artifact/`](oca-artifact/) | Sections 2 and 4 | Source code, tests, and documentation of Oca (also as `oca-artifact.zip`). |
| [`prompt_context_study_rq1_rq2/`](prompt_context_study_rq1_rq2/) | Section 3, Tables 1–4 | Prompt templates, scripts, and results of the prompt-strategy (RQ1) and context-configuration (RQ2) studies. |
| [`open_coding_rq2/`](open_coding_rq2/) | Section 3.3.1, Fig. 3 | Literature review of the context given to LLMs: screening, codes, codebook, and the script that rebuilds the taxonomy. |
| [`expressiveness_study_rq3/`](expressiveness_study_rq3/) | Section 5.2, Table 5 | Daikon invariant counts, the script that prints Table 5, and the Defects4J runs. |
| [`false_positive_study_rq4/`](false_positive_study_rq4/) | Section 5.3, Table 6 | The 100 manually reviewed invariants and the script that computes Table 6 and the inter-rater agreement. |
| [`usefulness_study_rq5/`](usefulness_study_rq5/) | Section 5.4, Table 7 | Simulated property-based testing on 25 Defects4J bugs: pipeline, exposing invariants, and the script that prints Table 7. |
| [`performance_study_rq6/`](performance_study_rq6/) | Section 5.5, Table 8 | Time and disk usage of both tools, and LLM token usage and cost of Oca. |

Each directory has its own README describing its files and how to run them.

## Requirements

- JDK 17+ to build and run Oca (`oca-artifact/README.md`); the benchmark studies use Java 23.
- Python 3 for the analysis scripts; `openpyxl` (`pip install openpyxl`) for the spreadsheets.
- An OpenAI API key (`OPENAI_API_KEY`) for new LLM queries. Recorded responses replay without one.
- Defects4J, Daikon, and a SLURM cluster for the Defects4J studies (RQ3, RQ5).

## Quick Start

```bash
cd oca-artifact && ./gradlew shadowJar
cd ../prompt_context_study_rq1_rq2 && python3 summarize_studies.py --check
cd ../open_coding_rq2 && python3 build_taxonomy.py --check
cd ../expressiveness_study_rq3 && python3 summarize_expressiveness.py --check
cd ../false_positive_study_rq4 && python3 analyze_reviews.py --check
cd ../usefulness_study_rq5 && python3 summarize_hits.py --check
cd ../performance_study_rq6 && python3 summarize_performance.py --check
```

## Configuration Used in the Paper

Unless a study varies them, all Oca runs use `gpt-4.1-mini`, at most K = 5 invariants per program point,
the Few-Shot prompt strategy, and the Class-Aware context:

```bash
export DP_OPENAI_MODEL=gpt-4.1-mini
export DP_PROMPT_STRATEGY=fewshot
export DP_CONTEXTS=METHOD_BODY,SCOPE,CLASS_DOC
```
