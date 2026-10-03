# Literature Review of LLM Context (Section 3.3.1, Fig. 3)

The literature review behind the context configurations of RQ2: which program context LLM-based
software engineering techniques give the model, coded on papers from the latest editions of FSE,
ICSE, ASE, and ISSTA.

| File | Contents |
|---|---|
| `papers_screened_open_coding.xlsx` | Search results, screening decisions, sampled papers, and per-paper codes with their justifications. |
| `CODEBOOK.md` | Definition and examples of every code. |
| `build_taxonomy.py` | Rebuilds the taxonomy tree and every count of Fig. 3 from the spreadsheet. |

## Reproducing Fig. 3

Requires Python 3 and `openpyxl` (`pip install openpyxl`).

```bash
python3 build_taxonomy.py            # tree as in the paper
python3 build_taxonomy.py --full     # also list the HIST and SEM subcodes
python3 build_taxonomy.py --check    # also compare every number with the paper (exit 1 on mismatch)
```

A node's count is the number of coded papers that use its code or any code below it, so a paper
with several codes in one family counts once for that family, and the parent counts are unions,
not sums. For space, the paper shows the HIST and SEM families without their subcodes, and shows
TEST-RENDER under TEST-EXEC; `--full` prints the HIST and SEM subcodes too.

## Procedure

1. **Search** (sheet `papers`): 332 papers with "LLM" or "large language model" in their title or abstract.
2. **Screening** (column `decision`): `include` when an LLM performs a task on source code
   (e.g., program repair, refactoring, code generation, reasoning about program behavior).
   This gives 184 candidate papers; three of them appear twice in the sheet, hence 187 `include` rows.
3. **Round 1: deriving the codes** (sheets `+randomNum`, `sampled`, `coded`, `freq`). Each paper got a
   frozen random number (`random_freezed`). Starting with 20 papers (about 10%) and adding five at a time
   in random order until a batch of five produced no new category gave 40 papers. Their context
   was grouped inductively into the codes of `CODEBOOK.md`. Sheet `freq` gives the code frequencies over
   these 40 papers only.
4. **Round 2: applying the codes** (sheet `Remaining 144 coded`) to the other 144 candidates.
   `Evidence status` records whether codes were verified against the PDF or the authors' method description.
   TEST-RENDER was added at this stage for a frontend-repair paper.
   Three papers received no study-level code and are excluded from the counts:
   a doctoral-symposium proposal with no implemented system, a study comparing 12 repair systems, and a
   ranker that gives no input to an LLM. This leaves **181 coded papers**.

One author coded the papers; the others reviewed the codes, and disagreements were resolved by discussion.

## Expected output

```
Context Provided to LLM [181]
├── Local Code Context (LC) [155]
│   ├── LC-SUBSRC       [ 73]  partial function code
│   ├── LC-FUNC         [ 76]  whole function or method
│   ├── LC-STRUCT       [ 43]  class, module, or file
│   └── LC-IR           [  4]  AST, bytecode, or IR
├── Structural Expansion Context (SE) [42]
│   ├── SE-ANALYSIS     [ 31]  static analysis, types
│   └── SE-GRAPH        [ 14]  dependency graphs
├── Documentation & Retrieval Context (DOC/RET) [112]
│   ├── DOC-NL          [ 56]  natural-language docs
│   ├── DOC-SPEC        [ 40]  specs, APIs, standards
│   ├── RET-CODE        [ 53]  code from repositories
│   └── RET-KB          [  6]  curated knowledge bases
├── Historical/Temporal Context (HIST) [62]
│   ├── HIST-CHANGE     [ 23]
│   ├── HIST-DEV        [ 18]
│   └── HIST-INTERACT   [ 37]
├── Semantic Context (SEM) [69]
│   ├── SEM-ABSTRACT    [ 18]
│   ├── SEM-INTENT      [ 21]
│   ├── SEM-EXPLANATION [ 18]
│   └── SEM-FEEDBACK    [ 19]
└── Testing & Execution Context (TEST) [48]
    ├── TEST-EXEC       [ 32]  failures, traces, tests
    │   └── TEST-RENDER [  1]  rendered UI
    ├── TEST-IO         [  9]  input/output pairs
    └── TEST-CODE       [ 18]  existing test suites
```

(Family descriptions omitted; the HIST and SEM subcodes appear only with `--full`.)
