# RQ4: False-Positive Analysis (Section 5.3, Table 6)

A manual review of 100 held invariants, 50 from Oca and 50 from Daikon, sampled from the
benchmark projects of section 3.1. It checks whether each invariant is semantically valid or a false positive:
reported as held only because the test executions never exposed a counterexample.

| File | Contents |
|---|---|
| `combined-invariant-reviews-all-100-final.xlsx` | The 100 sampled invariants with both reviewers' verdicts and reasoning, and the final verdict. |
| `analyze_reviews.py` | Reproduces Table 6, the inter-rater agreement, and Cohen's kappa from the spreadsheet. |

## Reproducing the results

Requires Python 3 and `openpyxl` (`pip install openpyxl`).

| Command | Prints |
|---|---|
| `python3 analyze_reviews.py` | Table 6, sample breakdown, agreement and Cohen's kappa |
| `python3 analyze_reviews.py --disagreements` | Also list the invariants the reviewers disagreed on |
| `python3 analyze_reviews.py --check` | Also compare every number with the paper; exits with status 1 on a mismatch |

## Spreadsheet columns

| Column | Meaning |
|---|---|
| `review_id` | Identifier of the sampled invariant. |
| `project`, `class_name`, `method_name`, `parameters`, `method_signature` | Where the invariant was inferred. |
| `program_point` | `ENTRY` (precondition) or `EXIT` (postcondition). |
| `invariant` | The invariant as a Java expression. Daikon invariants were rewritten from Daikon's notation into semantically equivalent Java, so reviewers could not tell the tools apart. |
| `source_tool` | `OCA` or `DAIKON`. Hidden from the reviewers. |
| `Reviewer1 Verdict`, `Reviewer2 Verdict` | Independent verdicts: `T` valid, `F` false positive. A trailing `?` marks an uncertain verdict, and a blank or `?` means no verdict. |
| `Reviewer1 Reasoning`, `Reviewer2 Reasoning` | Each reviewer's justification. |
| `Final Verdict` | Verdict after resolution, used for Table 6. |
| `Final Reasoning` | `Both reviewers agreed.`, the reason a definite verdict was used over an uncertain one, or the third author's justification for resolving a disagreement. |

## Procedure

1. **Sampling.** 50 held invariants per tool from 19 methods of the six benchmark projects, stratified
   across projects and methods, including methods exercised with different numbers of inputs. Each
   method contributes invariants from both tools:

   | Project | Oca | Daikon |
   |---|---:|---:|
   | Apollo | 9 | 9 |
   | Dubbo | 6 | 6 |
   | Hudi | 11 | 11 |
   | libGDX | 11 | 11 |
   | Netty | 7 | 7 |
   | Spring | 6 | 6 |

2. **Blinding.** One author removed the tool name and rewrote Daikon invariants as equivalent Java expressions.
3. **Review.** Two other authors independently examined the program point and source code of each invariant
   and judged whether it follows from the program's semantics and the programmer's intent, rather than only
   holding on the observed executions.
4. **Resolution.** A third author resolved each disagreement.

## Agreement and Cohen's kappa

Agreement and kappa are computed on the reviewers' verdicts before resolution, normalized as follows:

- surrounding whitespace is ignored (`"T "` is `T`);
- an uncertain verdict (`T?`, `F?`) or a missing one (blank, `?`) is not counted as a disagreement:
  it takes the other reviewer's definite verdict.

## Expected output

```
Table 6: False-positive analysis of the manually inspected sample (RQ4)
  Tool     False pos.  Valid  Total   Rate
  Oca               9     41     50    18%
  Daikon           38     12     50    76%

Inter-rater agreement (before resolution)
  agreed:    89 (89%)
  disagreed: 11 (11%), resolved by a third author
  Cohen's kappa: 0.780
```
