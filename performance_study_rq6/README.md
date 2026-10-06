# RQ6: Performance (Section 5.5, Table 8)

| File | Contents |
|---|---|
| `table8.csv` | Time and disk usage of Daikon and Oca per project. |
| `summarize_performance.py` | Prints Table 8 with its totals. |
| `oca_token_costs.md` | LLM token usage and API cost of Oca per project. |

For Daikon, time is the wall-clock time of Chicory tracing plus Daikon inference, and disk usage is the size of
Chicory's trace files and Daikon's logs. For Oca, time is the wall-clock time of one end-to-end run, including
the LLM queries, filtering, compilation, and test execution, and disk usage is the size of the instrumented copy
of the project plus Oca's output and logs.

| Command | Prints |
|---|---|
| `python3 summarize_performance.py` | Table 8 |
| `python3 summarize_performance.py --check` | Also compare the totals with the paper; exits with status 1 on a mismatch |
