# Prompt Templates (Table 1)

The exact text Oca sends to the LLM, from `oca-artifact/src/main/java/anonymous/oca/llm/prompt/`.
Every strategy uses the Zero-Shot template; the others add only the text in their own section.
`<...>` marks values filled in per program point.

| Strategy | Prompting technique | `DP_PROMPT_STRATEGY` | Where the addition goes |
|---|---|---|---|
| Zero-Shot | Zero-shot | `baseline` | — |
| Few-Shot | In-context learning | `fewshot` | end of the system message |
| Chain-of-Thought | Thought generation | `cot` | user message, after the program context |
| Stepwise | Decomposition | `stepwise` | user message, after the program context |
| Self-Refinement | Self-criticism | `self_refine` | user message, after the program context |
| Multi-Sample | Ensembling | `multi_sample` | user message, after the program context |

## Zero-Shot (`baseline`)

### System message

```
You are a program analysis assistant.

Task:
Generate candidate invariants for a Java program point.

Global rules:
- Return ONLY JSON matching the required schema.
- The JSON schema is:
  {
    "invariants": [
      { "expression": "<Java boolean expression>" }
    ]
  }
- Each invariant must be a valid Java boolean expression.
- Expressions must be valid at the program point.
- Use only the listed in-scope names.
- Do not introduce new variables, helper functions, or APIs.
- Expressions must be side-effect free.
```

### User message

```
PROGRAM POINT: <method id> [<METHOD_ENTRY | METHOD_EXIT>]

<program point explanation>
In-scope names:
- <name> : <type>
...

Note:
- These are base variables.
- Expressions derived from them (e.g., field accesses and method calls) are allowed if valid at this program point.

<note about 'result', METHOD_EXIT of non-void methods only>
Constraints specific to this program point:
- Single-line Java boolean expressions only.
- Method calls are allowed and encouraged if callable using listed names.
- Method calls may belong to the JDK or the project codebase.
- Field accesses (e.g., obj.field) are allowed if accessible using listed names.
- Do not invent methods or fields that are not available at this program point.
- Add null checks ONLY when required for safe evaluation.
- Do not use non-Java logical operators such as ==> or ⇒.
- Logical implication (A ⇒ B) must be expressed as (!A || B) using standard Java boolean operators.
- Prefer pure predicate-style method calls.
- Avoid redundant or trivially true expressions.
- Do NOT generate tautologies or self-comparisons (e.g., x == x, obj.method() == obj.method()).
- Avoid semantically duplicate invariants that differ only by operand order or equivalent comparison form (e.g., a == b vs b == a, a <= b vs b >= a).
- Do not focus solely on nullness-related invariants.
- Prioritize invariants that capture meaningful relationships among the in-scope names and reflect the behavior of the method at this program point.

===== PROGRAM CONTEXT =====
Consider the following context when generating invariants.
<context sections>
===========================

<strategy-specific addition, if any>

Generate up to <K> candidate invariants that are valid at this program point.
Return ONLY the JSON.
```

**Program point explanation.** At `METHOD_ENTRY`:

```
This program point represents the state immediately BEFORE the method executes.
Only parameters and object state are defined.
```

At `METHOD_EXIT`:

```
This program point represents the state immediately BEFORE the method returns.
Parameters, object state, and 'result' (if non-void) may be referenced.
```

**Note about `result`** (only when `result` is in scope):

```
Note about 'result':
- 'result' is a symbolic name for the value returned by the method.
- If the method has multiple return statements, 'result' refers to the value returned along any execution path.
- Any invariant involving 'result' must hold for all possible return values of the method.
```

**Context sections.** One labeled section per non-empty context component, in this order
(`(none)` if all are empty). The context configuration (Table 3) decides which are present.

| Section | `DP_CONTEXTS` component |
|---|---|
| `[Method Implementation]` | `METHOD_BODY` |
| `[Method Javadoc]` | `METHOD_JAVADOC` |
| `[Enclosing Class Documentation]` | `CLASS_DOC` |
| `[Type-Level Documentation]` | `TYPE_DOC` |
| `[Call-Site Context]` | `CALL_SITE` |
| `[Input-Output Examples]` | `IO_EXAMPLES` |

## Few-Shot (`fewshot`)

Appended to the system message, after a blank line. The examples depend on the program point kind.

### At `METHOD_ENTRY`

```
===== EXAMPLE 1 =====
PROGRAM POINT: Example1 [METHOD_ENTRY]

In-scope names:
- order : Order
- limit : int

===== PROGRAM CONTEXT =====
[Method Implementation]
public void process(Order order, int limit) {
  if (order.getQuantity() > limit) {
    throw new IllegalArgumentException();
  }
}
===========================

Expected Output:
{
  "invariants": [
    { "expression": "order != null" },
    { "expression": "order.getQuantity() <= limit" },
    { "expression": "order.getQuantity() >= 0" },
    { "expression": "limit >= 0" }
  ]
}
===== END EXAMPLE 1 =====

===== EXAMPLE 2 =====
PROGRAM POINT: Example2 [METHOD_ENTRY]

In-scope names:
- s : String
- start : int
- end : int

===== PROGRAM CONTEXT =====
[Method Implementation]
public String sub(String s, int start, int end) {
  if (start < 0 || end > s.length()) return "";
  return s.substring(start, end);
}
===========================

Expected Output:
{
  "invariants": [
    { "expression": "s != null" },
    { "expression": "start >= 0" },
    { "expression": "end <= s.length()" },
    { "expression": "start <= end" }
  ]
}
===== END EXAMPLE 2 =====
```

### At `METHOD_EXIT`

```
===== EXAMPLE 1 =====
PROGRAM POINT: Example1 [METHOD_EXIT]

In-scope names:
- order : Order
- result : double

===== PROGRAM CONTEXT =====
[Method Implementation]
public double total(Order order) {
  return order.getQuantity() * order.getUnitPrice();
}
===========================

Expected Output:
{
  "invariants": [
    { "expression": "order != null" },
    { "expression": "result == order.getQuantity() * order.getUnitPrice()" },
    { "expression": "order.getQuantity() == 0 || result / order.getQuantity() == order.getUnitPrice()" },
    { "expression": "!(result < 0 && order.getQuantity() >= 0 && order.getUnitPrice() >= 0)" }
  ]
}
===== END EXAMPLE 1 =====

===== EXAMPLE 2 =====
PROGRAM POINT: Example2 [METHOD_EXIT]

In-scope names:
- card : String
- expiry : String
- result : boolean

===== PROGRAM CONTEXT =====
[Method Implementation]
public boolean valid(String card, String expiry) {
  if (card == null || expiry == null) return false;
  return card.length() == 16 && expiry.length() == 5 && expiry.charAt(2) == '/';
}
===========================

Expected Output:
{
  "invariants": [
    { "expression": "!result || (card != null && expiry != null)" },
    { "expression": "!result || (card.length() == 16 && expiry.length() == 5 && expiry.charAt(2) == '/')" }
  ]
}
===== END EXAMPLE 2 =====
```

## Chain-of-Thought (`cot`)

```
Before producing the JSON, think internally about:
1) Which names are in-scope and their types.
2) Which expressions are evaluable safely (add null checks only when required).
3) What constraints are directly implied by the provided PROGRAM CONTEXT.
4) Prefer simple relations between parameters, fields, and result and safe pure method calls.

Do NOT include your reasoning in the output.
```

## Stepwise (`stepwise`)

```
Discover invariants in these internal steps (do not print the steps):
Step 1: Propose simple unary invariants (single variable properties) ONLY if implied by context.
Step 2: Propose relational invariants between two variables (including 'result' on METHOD_EXIT) ONLY if implied by context.
Step 3: Propose invariants using method calls ONLY when the call is side-effect free, callable from the listed in-scope names, and safely evaluable (add null checks only when required).

Then output only the final JSON.
```

## Self-Refinement (`self_refine`)

```
After drafting candidates, internally verify each invariant:
- Valid Java boolean expression?
- Uses only in-scope names?
- Evaluable at this program point (no locals; add null checks only when required)?
- Side-effect free?
- Not redundant or trivially true?

Remove or revise any invariant that fails these checks.
Return ONLY the final JSON (no intermediate drafts).
```

## Multi-Sample (`multi_sample`)

```
Within this single response, create three internal drafts with different focuses:
- Draft A: focus on simple parameter/field constraints.
- Draft B: focus on relations involving 'result' (if METHOD_EXIT) and parameters.
- Draft C: focus on safe, pure method-call predicates (if any are implied by context).

Then keep only invariants that appear in at least two drafts, or are clearly implied by context and non-redundant.
Return ONLY the final agreed JSON. Do not output the drafts.
```
