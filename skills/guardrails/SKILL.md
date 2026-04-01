---
name: guardrails
description: "Failure-driven learning loop. When something goes wrong, add a 'sign' that prevents the same mistake in future iterations. Accumulates project-specific rules over time. Use when an agent makes a repeated mistake, when you want to encode a lesson learned, or when building autonomous loops that improve themselves."
license: MIT
metadata:
  pattern: signs
  origin: ghuntley.com/ralph, agrimsingh/ralph-wiggum-cursor
---

# Guardrails: Failure-Driven Learning

When an agent (or human) makes a mistake, record it as a **sign**. Signs accumulate in a `guardrails.md` file that every future iteration reads before starting work. The system gets smarter over time without requiring prompt changes.

## Core Idea

```
Error occurs -> Analyze root cause -> Write a sign -> Future iterations follow the sign
```

Like tuning a guitar: each adjustment makes the next note more accurate. You don't rewrite the song -- you adjust the instrument.

## When To Use This

- An agent repeats the same mistake across iterations
- You discover a non-obvious project gotcha
- A build/test failure reveals a convention that must be followed
- You want autonomous loops that self-correct

## The Signs File

Create `guardrails.md` (or `.ralph/guardrails.md`) in your project:

```markdown
# Guardrails

Rules learned from observed failures. Read this BEFORE starting work.

## Sign: [Short Name]
- **Trigger**: When [situation that causes the mistake]
- **Instruction**: [What to do instead]
- **Added after**: [When/why this was discovered]
```

## Writing Good Signs

### Structure

Every sign has three parts:

1. **Trigger** -- The specific situation where the mistake occurs. Be precise.
2. **Instruction** -- What to do instead. Must be actionable, not vague.
3. **Added after** -- Context for why this sign exists.

### Examples

```markdown
## Sign: Check imports before adding new ones
- **Trigger**: Adding an import statement to a file
- **Instruction**: Search the file for existing imports of the same module first. Duplicate imports cause build failures.
- **Added after**: Iteration 3 - duplicate import broke typecheck

## Sign: Run migrations before testing schema changes
- **Trigger**: Modifying database schema or adding columns
- **Instruction**: Run `npm run db:migrate` before running tests. Tests use the live schema.
- **Added after**: Iteration 7 - tests failed because new column didn't exist yet

## Sign: Use relative imports within a package
- **Trigger**: Importing from another file in the same package
- **Instruction**: Use `./foo` or `../foo`, never the package name. The package name only works after build.
- **Added after**: Iteration 2 - module resolution failed in dev mode

## Sign: Don't read entire large files
- **Trigger**: Needing to understand a file with 500+ lines
- **Instruction**: Use grep/search to find the relevant section first. Reading the whole file wastes context budget.
- **Added after**: Iteration 5 - context rotated too early due to large file reads

## Sign: Always seed test database
- **Trigger**: Writing or running integration tests
- **Instruction**: Call `setupTestDb()` in beforeEach. Tests are not isolated without it.
- **Added after**: Iteration 9 - flaky test failures from shared state
```

### Anti-Patterns (bad signs)

```markdown
## Sign: Be careful
- Trigger: Always
- Instruction: Be more careful
```
This is useless. No specific trigger, no actionable instruction.

```markdown
## Sign: Fix the bug in auth
- Trigger: When working on authentication
- Instruction: Don't introduce the bug
```
This doesn't explain what the bug is or how to avoid it.

## Gutter Detection

The "gutter" is when context is so polluted that the agent keeps making the same mistake in a loop, like a bowling ball stuck in the gutter.

**Detection signals:**
- Same command failed 3+ times in a row
- Same file written and rewritten 5+ times in 10 minutes
- Same error message appearing repeatedly
- Agent explicitly signals it's stuck

**Response:**
1. Stop the current iteration
2. Analyze the failure pattern
3. Write a new sign capturing the root cause
4. Start a fresh context (new iteration / new conversation)

The fresh context reads the new sign and avoids the gutter.

## Lifecycle of a Sign

```
1. Mistake occurs in iteration N
2. Agent (or human) writes a sign in guardrails.md
3. Iteration N+1 reads guardrails.md before starting
4. Sign prevents the same mistake
5. If sign is general enough, promote it to AGENTS.md
```

### Promotion to AGENTS.md

Signs that prove universally useful graduate to the project's AGENTS.md:

- Sign has prevented the same mistake 3+ times -> promote
- Sign describes a fundamental project convention -> promote
- Sign is temporary or context-specific -> keep in guardrails.md

## Integration With The Loop

### ralph-loop reads guardrails at step 1 (Orient):
```
1. Read task file
2. Read progress.md
3. Read guardrails.md  <-- signs inform this iteration's behavior
4. Check git log
```

### Agent updates guardrails at step 4 (Record):
```
If something failed:
  1. Diagnose root cause
  2. Write a sign in guardrails.md
  3. Commit the updated guardrails.md
```

## Bootstrapping

For a new project, start with an empty guardrails file:

```markdown
# Guardrails

Rules learned from observed failures. Read this BEFORE starting work.

<!-- Signs will be added here as failures are observed -->
```

Signs accumulate naturally as the agent works. After 10-20 iterations, you'll have a comprehensive set of project-specific rules that dramatically reduce repeated failures.

## File Locations

| Tool | Location |
|------|----------|
| ralph-loop | `.ralph/guardrails.md` |
| ralph-wiggum-cursor | `.ralph/guardrails.md` |
| Standalone | `guardrails.md` at project root |
| Global (cross-project) | `~/.config/opencode/guardrails.md` |
