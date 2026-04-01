---
name: code-review
description: "Structured code review across four dimensions: security, error handling, code quality, and testing. Produces a Summary / Critical / Suggestions / Questions report. Use as a review gate in subagent-dispatch, for PR reviews, or when reviewing your own changes before committing."
license: MIT
metadata:
  pattern: review-checklist
  origin: nousresearch/hermes-agent
---

# Code Review: Structured Review Checklist

Review code across four dimensions. Produce a structured report. No vague "looks good" -- every point must cite specific code.

## When To Use This

- Reviewing changes before committing (self-review)
- As the review gate in subagent-dispatch (Step 2-3)
- PR review workflow
- Post-implementation quality check in ralph-loop

## The Four Dimensions

### 1. Security

- [ ] No hardcoded secrets (API keys, passwords, tokens)
- [ ] SQL queries use parameterized statements (no string interpolation)
- [ ] User input is validated and sanitized at boundaries
- [ ] File paths are validated (no path traversal: `../`)
- [ ] Authentication/authorization checks are present where needed
- [ ] Sensitive data is not logged or exposed in error messages
- [ ] Dependencies are from trusted sources, versions pinned

### 2. Error Handling

- [ ] External calls (network, filesystem, DB) have try/catch or error returns
- [ ] Error messages are descriptive (include context: what, where, why)
- [ ] Errors are logged at appropriate levels (not swallowed silently)
- [ ] Resources are cleaned up on failure (connections closed, files released)
- [ ] User-facing errors don't leak implementation details
- [ ] Async operations handle rejection/timeout

### 3. Code Quality

- [ ] Each function does one thing (Single Responsibility)
- [ ] Names are descriptive (variables, functions, types)
- [ ] No duplicated logic (DRY -- extract shared code)
- [ ] No dead code or commented-out blocks
- [ ] Control flow is straightforward (no deeply nested if/else)
- [ ] Types are specific (no `any` in TS, no bare `dict` in Python when structure is known)
- [ ] Constants are named, not magic numbers/strings
- [ ] Public API has documentation (functions other modules call)

### 4. Testing

- [ ] New code has corresponding tests
- [ ] Tests cover happy path AND error paths
- [ ] Edge cases are tested (empty input, null, boundary values)
- [ ] Tests are independent (no shared mutable state between tests)
- [ ] Existing tests still pass (no regressions)
- [ ] Test names describe the behavior being verified
- [ ] Mocks/stubs are minimal (don't mock what you don't own)

## Language-Specific Checks

### Python
- [ ] Type hints on function signatures
- [ ] `with` statements for resource management (files, connections)
- [ ] No bare `except:` (always catch specific exceptions)
- [ ] f-strings preferred over `.format()` or `%`

### JavaScript / TypeScript
- [ ] `const` by default, `let` when mutation needed, never `var`
- [ ] Strict equality `===` not loose `==`
- [ ] Async/await with proper error boundaries
- [ ] No `any` types (use `unknown` and narrow)

### C / C++
- [ ] No buffer overflows (bounds-checked access)
- [ ] Memory allocated is freed (no leaks)
- [ ] Pointers checked for NULL before dereference
- [ ] No undefined behavior (signed overflow, use-after-free)

### Rust
- [ ] `unwrap()` only in tests, never in library/production code
- [ ] `Result` and `Option` used for fallible operations
- [ ] No `unsafe` blocks without a safety comment explaining the invariant

### Go
- [ ] Errors checked immediately after each call (`if err != nil`)
- [ ] `defer` for cleanup (file close, mutex unlock)
- [ ] Context propagation for cancellation

### Java
- [ ] Resources in try-with-resources blocks
- [ ] Specific exception types (not bare `Exception`)
- [ ] Null checks or Optional usage

## Report Format

```markdown
## Summary
[1-2 sentences: what the changes do and overall quality assessment]

## Critical Issues
[Issues that MUST be fixed before merge. Security vulns, data loss risks, correctness bugs.]

- **[CRITICAL]** `path/to/file.py:42` -- SQL injection via string interpolation
  in `get_user()`. Use parameterized query instead.

## Suggestions
[Improvements that SHOULD be made. Code quality, performance, maintainability.]

- **[WARNING]** `path/to/file.py:67` -- Bare `except:` swallows all errors
  including KeyboardInterrupt. Catch `Exception` at minimum.

- **[INFO]** `path/to/file.py:12` -- `process_data` does validation AND
  transformation. Consider splitting into two functions.

## Questions
[Things the reviewer doesn't understand or needs clarification on.]

- `path/to/file.py:89` -- What is the expected behavior when `user_id` is None?
  The current code silently returns an empty dict.
```

## Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| **CRITICAL** | Security vulnerability, data loss, correctness bug | Must fix before merge |
| **WARNING** | Error handling gap, code smell, missing test | Should fix before merge |
| **INFO** | Style, naming, minor improvement | Nice to have, can defer |

## As a Quality Gate

In subagent-dispatch, the review is pass/fail:

- **PASS**: Zero CRITICAL issues, zero or few WARNINGs
- **FAIL**: Any CRITICAL issue, or 3+ WARNINGs

A failing review sends feedback to the implementer for a revision cycle.
