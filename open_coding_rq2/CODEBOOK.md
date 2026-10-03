# Codebook: Context Provided to LLMs

The codes characterize **what information is given to the model**, not how the model reasons about it.
They are grouped into six families. A paper receives every code that applies to the input of its LLM.

| Family | Codes |
|---|---|
| Local Code Context (LC) | LC-SUBSRC, LC-FUNC, LC-STRUCT, LC-IR |
| Structural Expansion Context (SE) | SE-ANALYSIS, SE-GRAPH |
| Documentation & Retrieval Context (DOC/RET) | DOC-NL, DOC-SPEC, RET-CODE, RET-KB |
| Historical/Temporal Context (HIST) | HIST-CHANGE, HIST-DEV, HIST-INTERACT |
| Semantic Context (SEM) | SEM-ABSTRACT, SEM-INTENT, SEM-EXPLANATION, SEM-FEEDBACK |
| Testing & Execution Context (TEST) | TEST-EXEC (with subcode TEST-RENDER), TEST-IO, TEST-CODE |

## 1. Local Code Context (LC)

The amount and representation of program code given directly to the LLM, without further expansion or analysis.

- **LC-SUBSRC: Sub-source context.** Source code smaller than a complete function, e.g., an incomplete snippet.
- **LC-FUNC: Function-level context.** A complete function or method body, e.g., a full Java method or Python function.
- **LC-STRUCT: Structural unit context.** Code larger than a single function, with its surrounding structure: a class definition, a module or file, package-level context, several related methods and fields.
- **LC-IR: Non-source representation context.** Program logic in a non-source format: AST, bytecode, or intermediate representation.

## 2. Structural Expansion Context (SE)

Context derived from program analysis or structural modeling, exposing relationships not visible in linear code.

- **SE-ANALYSIS: Program analysis context.** Output of automated static analysis or type systems given alongside or instead of raw code: dataflow facts, inferred types, variable-usage summaries, coupling metrics, analysis warnings, symbolic summaries.
- **SE-GRAPH: Dependency/graph context.** Program structure as explicit graphs: call graphs, dependency graphs, context graphs, API dependency graphs, hypergraphs.

## 3. Documentation & Retrieval Context (DOC/RET)

Non-code artifacts describing program intent, or knowledge retrieved from outside the input program.

- **DOC-NL: Natural-language documentation.** Human-written text about the software: source comments, issue descriptions, reviewer feedback, problem statements.
- **DOC-SPEC: Specification context.** Structured or rule-based documentation of expected behavior: API documentation, OpenAPI or RFC specifications, coding standards, DSL specifications, refactoring rules, smell definitions.
- **RET-CODE: Retrieved code context.** Code retrieved from repositories or datasets to augment the input: similar functions, repository file retrieval, cross-file dependencies, RAG code examples, project-specific context expansion.
- **RET-KB: External knowledge-base retrieval.** Retrieval from curated external sources rather than code repositories: vulnerability databases, smell knowledge bases, domain rule repositories, curated expert datasets.

## 4. Historical/Temporal Context (HIST)

Context derived from software evolution and development history.

- **HIST-CHANGE: Code evolution context.** Changes to source code across versions: git diffs, patches, before/after versions, historical bug fixes, prior repair examples.
- **HIST-DEV: Development activity context.** Artifacts of developer workflow and collaboration: issue-tracker discussions, pull requests, editing history, recently opened files, development-timeline metadata.
- **HIST-INTERACT: Interaction history context.** Previous interaction rounds between users and the LLM: conversational repair loops, iterative refinement, multi-turn editing sessions.

## 5. Semantic Context (SEM)

Abstract representations that compress or formalize program meaning, rather than raw artifacts.

- **SEM-ABSTRACT: Semantic abstraction context.** Higher-level representations derived from code: natural-language function summaries, behavioral descriptions, semantic units, inferred logical relations, abstract operation representations.
- **SEM-INTENT: Intent representation context.** Explicit representation of developer or task goals: task descriptions, reviewer intentions, change objectives, repair-intent specifications.
- **SEM-EXPLANATION: Reasoning trace context.** Explanatory artifacts used as context: reasoning traces, explanation annotations, commit explanations, structured reasoning outputs.
- **SEM-FEEDBACK: Semantic feedback context.** Evaluation or correction signals given after model output: validation feedback, corrected outputs, user corrections, evaluation results used for refinement.

## 6. Testing & Execution Context (TEST)

Context obtained by executing or testing the program.

- **TEST-EXEC: Execution-derived context.** Information produced by running or compiling the program: failing tests, generated unit tests, run-time traces, compiler errors.
  - **TEST-RENDER: Rendered interface.** Properties of a rendered user interface. Added after the initial coding for one frontend-repair paper; counted under TEST-EXEC in the tree.
- **TEST-IO: Test input/output.** Pairs of expected inputs and outputs.
- **TEST-CODE: Test suite context.** Existing test code given directly as input: unit test files, regression suites, benchmark tests.
