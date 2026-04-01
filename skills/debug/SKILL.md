---
name: debug
description: "Systematic 4-phase debugging methodology: investigate root cause, analyze patterns, form and test hypotheses, implement a single fix. Prevents guess-and-check spirals. Use when a test fails, a bug is reported, or an agent is stuck in a failure loop."
license: MIT
metadata:
  pattern: systematic-debugging
  origin: nousresearch/hermes-agent
---

# Debug: Systematic Debugging Protocol

Stop guessing. Follow the protocol.

## When To Use This

- A test fails and the cause is not immediately obvious
- A bug is reported and needs investigation
- An agent has tried 2+ fixes that didn't work
- You're about to type "let me try..." -- stop, load this skill instead

## The Rule of Three

**If three attempted fixes have failed, STOP.** You are not debugging -- you are guessing. Step back and question your assumptions about the architecture.

## Phase 1: Root Cause Investigation

Do NOT write any code in this phase. Only read and observe.

### 1.1 Read the error
- Read the full error message and stack trace
- Note the exact file, line, and function
- Note the error type (TypeError, 404, segfault, panic, etc.)

### 1.2 Reproduce
- Run the failing test or trigger the bug manually
- Confirm you see the same error
- If you can't reproduce it, you can't fix it -- gather more information

### 1.3 Check recent changes
```bash
git log --oneline -10
git diff HEAD~3 -- <relevant-files>
```
Did a recent change cause this? What was working before?

### 1.4 Gather evidence
- Read the failing code path end-to-end
- Check inputs: what data reaches the failing function?
- Check assumptions: what does the code expect vs. what it gets?
- Check dependencies: did an API, schema, or config change?

### 1.5 Trace data flow
Follow the data from entry point to failure point:
```
Input -> [Function A] -> [Function B] -> [FAILURE HERE]
                                          ^
                                          What does it receive?
                                          What does it expect?
```

## Phase 2: Pattern Analysis

### 2.1 Find a working example
Look for similar code that DOES work:
- Same function called elsewhere successfully
- Similar endpoint that handles the same pattern
- Tests that pass for related functionality

### 2.2 Compare working vs. broken
```bash
# Diff the working version against the broken one
diff working_version.py broken_version.py
```
What is different? Focus on:
- Argument types and order
- Import paths
- Configuration values
- Environment variables

### 2.3 Identify the delta
The bug lives in the difference between working and broken. Write it down:

```
Working: Function receives UserID as int
Broken:  Function receives UserID as string
Delta:   Type mismatch at the boundary
```

## Phase 3: Hypothesis and Testing

### 3.1 Form ONE hypothesis
Based on evidence from Phase 1 and 2, state a single, testable hypothesis:

```
Hypothesis: The user_id is passed as a string from the URL parameter
but the database query expects an integer, causing the type error.
```

### 3.2 Test the hypothesis
Add a diagnostic (print, log, assert, debugger) at the exact point:

```python
# Diagnostic -- remove after confirming
print(f"DEBUG: user_id={user_id!r}, type={type(user_id)}")
```

```rust
// Diagnostic -- remove after confirming
dbg!(&user_id);
```

```go
// Diagnostic -- remove after confirming
fmt.Printf("DEBUG: user_id=%v, type=%T\n", userID, userID)
```

### 3.3 One variable at a time
Change ONE thing. Run the test. Observe the result. If it didn't fix it, **revert** and try the next hypothesis. NEVER stack multiple changes.

## Phase 4: Implementation

### 4.1 Write a failing test first
Before fixing the bug, write a test that reproduces it:

```python
def test_user_lookup_with_string_id():
    """Regression test: URL params are strings, DB expects int."""
    response = client.get("/users/42")
    assert response.status_code == 200
```

This test should FAIL now (confirming the bug).

### 4.2 Apply the single fix
Fix the root cause identified in Phase 3. One change, one location:

```python
# Fix: cast URL param to int at the boundary
user_id = int(request.params["user_id"])
```

### 4.3 Verify
```bash
# The regression test should now pass
pytest tests/test_user.py::test_user_lookup_with_string_id

# ALL other tests should still pass
pytest
```

### 4.4 Remove diagnostics
Delete all `print`, `dbg!`, `console.log` diagnostics added in Phase 3.

### 4.5 Commit
```bash
git add <specific-files>
git commit -m "fix: cast user_id to int at URL boundary

The URL parameter arrives as a string but the DB query expects
an integer. Added explicit int() cast at the route handler.

Regression test: test_user_lookup_with_string_id"
```

## Red Flags

Stop and reassess if:

- You're editing a file you don't understand
- The fix requires changing more than 3 files
- You're suppressing an error instead of fixing its cause
- You're adding a try/except or catch that swallows the error
- The "fix" is adding a special case or flag

These are signs you're treating symptoms, not the disease.

## Integration with Guardrails

After fixing the bug, ask: "Could a future agent make this same mistake?"

If yes, add a sign:
```markdown
## Sign: URL params are always strings
- **Trigger**: Reading parameters from HTTP request URLs
- **Instruction**: Always cast URL params to the expected type at the handler boundary. They arrive as strings.
- **Added after**: Debug session - TypeError from uncasted user_id
```

## Integration with Ralph Loop

When a ralph-loop iteration hits a failure:
1. Do NOT immediately retry with a different approach
2. Run this debug protocol
3. If Phase 1-3 identifies the root cause, fix it in Phase 4
4. If the Rule of Three triggers, signal GUTTER and add a guardrail
