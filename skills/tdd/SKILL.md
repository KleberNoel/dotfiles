---
name: tdd
description: "Strict test-driven development loop: RED (write failing test) -> GREEN (minimum code to pass) -> REFACTOR. No production code without a failing test first. Language-agnostic -- detects test runner from project. Use when implementing features, fixing bugs, or when working in autonomous loops that must produce tested code."
license: MIT
metadata:
  pattern: red-green-refactor
  origin: nousresearch/hermes-agent
---

# TDD: Test-Driven Development Loop

Write the test first. Then the code. No exceptions.

## The Iron Law

**No production code exists without a failing test that demanded it.**

If you wrote code before the test, delete it and start over. This is not a suggestion.

## The Cycle

```
RED    -> Write a test that fails (proves the feature is missing)
GREEN  -> Write the minimum code to make the test pass (nothing more)
REFACTOR -> Clean up while keeping tests green
```

Each cycle should take 2-10 minutes. If it takes longer, the scope is too big.

## Phase 1: RED (Write a Failing Test)

1. Identify the next smallest behavior to implement
2. Write a test that asserts that behavior
3. Run the test -- it MUST fail
4. If it passes, the test is wrong (it's not testing new behavior)

```bash
# Run the test -- expect failure
pytest tests/test_feature.py::test_new_behavior     # Python
npm test -- --grep "new behavior"                    # JS/TS
cargo test test_new_behavior                         # Rust
go test -run TestNewBehavior ./...                   # Go
```

### What makes a good test

- Tests ONE behavior, not an entire feature
- Has a descriptive name that reads like a specification
- Follows Arrange-Act-Assert (or Given-When-Then)
- Does not depend on other tests
- Does not depend on external services (mock them)

### Test naming

```
test_<unit>_<scenario>_<expected_result>
```

Examples:
- `test_user_create_with_duplicate_email_returns_conflict`
- `test_cart_add_item_increments_quantity`
- `test_parse_empty_input_returns_none`

## Phase 2: GREEN (Make It Pass)

1. Write the **minimum** code to make the failing test pass
2. It is OK if the code is ugly -- that's what refactor is for
3. Do NOT add code for future tests
4. Run ALL tests -- everything must be green

```bash
# Run full suite -- all must pass
pytest                    # Python
npm test                  # JS/TS
cargo test                # Rust
go test ./...             # Go
make test                 # Generic
```

### Minimum means minimum

If the test expects `add(1, 2) == 3`, the minimum code is:
```python
def add(a, b):
    return a + b
```
NOT:
```python
def add(a, b):
    # validate inputs
    if not isinstance(a, (int, float)):
        raise TypeError(...)
    # handle edge cases
    ...
```
Edge cases get their own RED cycle.

## Phase 3: REFACTOR (Clean Up)

1. Tests are green -- now improve the code
2. Extract functions, rename variables, remove duplication
3. Run tests after EVERY change -- if anything breaks, undo immediately
4. Refactor the tests too (remove duplication, improve names)

### Refactor checklist
- [ ] No duplicated code (DRY)
- [ ] Functions do one thing (SRP)
- [ ] Names are descriptive
- [ ] No magic numbers/strings
- [ ] Tests still pass

## Detecting the Test Runner

Read the project root for clues:

| File | Runner | Command |
|------|--------|---------|
| `pyproject.toml` / `pytest.ini` / `setup.cfg` | pytest | `pytest` |
| `package.json` (scripts.test) | jest/vitest/mocha | `npm test` |
| `Cargo.toml` | cargo test | `cargo test` |
| `go.mod` | go test | `go test ./...` |
| `Makefile` (test target) | make | `make test` |
| `build.gradle` / `pom.xml` | JUnit | `./gradlew test` / `mvn test` |
| `CMakeLists.txt` | ctest | `cmake --build . && ctest` |

## Common Rationalizations (and rebuttals)

| Excuse | Rebuttal |
|--------|----------|
| "This is too simple to test" | Simple code gets complex. Test it now. |
| "I'll add tests later" | You won't. Write them first. |
| "The test is obvious" | If it's obvious, it takes 30 seconds to write. |
| "I need to explore first" | Explore in a scratch file. TDD the real code. |
| "It's just a refactor" | Refactors break things. Tests catch it. |
| "The framework makes it hard" | Find the seam. Mock the boundary. |
| "I'm prototyping" | Prototypes become production. Test from the start. |

## Integration with Ralph Loop

In a ralph-loop iteration, each criterion becomes a TDD cycle:

1. Read the criterion from the task file
2. RED: Write a test that verifies the criterion
3. GREEN: Implement the minimum code
4. REFACTOR: Clean up
5. Commit: `git add` test + implementation files
6. Mark criterion as `[x]`

The test is your proof that the criterion is met. No test = no checkmark.

## Integration with Guardrails

When a test fails unexpectedly during GREEN or REFACTOR:
1. Do NOT delete the test
2. Diagnose why it failed (use the debug skill if needed)
3. If it reveals a codebase convention, add a sign to `guardrails.md`
4. Fix the code, not the test (unless the test is genuinely wrong)
