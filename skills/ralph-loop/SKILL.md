---
name: ralph-loop
description: "Autonomous iteration loop with context rotation. Runs a task repeatedly in fresh context windows until all criteria pass. State persists in files and git, not in LLM memory. Use when building features autonomously, running multi-step implementations, or when a task exceeds a single context window."
license: MIT
metadata:
  pattern: ralph
  origin: ghuntley.com/ralph
---

# Ralph Loop: Autonomous Iteration with Context Rotation

Run a task repeatedly in fresh agent contexts until done. Progress lives in **files and git**, not in the LLM's memory. When context fills up or gets polluted, rotate to a clean slate.

## Core Principle

```
while tasks_remain; do
  cat TASK.md | agent
done
```

Each iteration is a fresh agent. The only memory between iterations is:
- Git history (commits from previous iterations)
- `progress.md` (what was accomplished, learnings)
- `guardrails.md` (accumulated failure-driven rules)
- The task file itself (which criteria are done)

## When To Use This

- Feature implementation that spans multiple focused sessions
- Any task too large for a single context window
- Autonomous overnight/background execution
- Tasks with verifiable completion criteria

## Setup

Create a task file at the project root. Name it `RALPH_TASK.md`, `TASK.md`, or whatever suits the project:

```markdown
---
task: Short description of the goal
test_command: "npm test"  # or pytest, make check, cargo test, etc.
---

# Task: [Name]

[Description of what needs to be built]

## Success Criteria

1. [ ] First verifiable criterion
2. [ ] Second verifiable criterion
3. [ ] All tests pass
4. [ ] Typecheck/lint passes
```

**Use `[ ]` checkboxes.** Completion is tracked by counting unchecked boxes.

## State Directory

Create a `.ralph/` directory (or `.loop/`, `.state/` -- the name is cosmetic):

```
.ralph/
  progress.md      # Append-only log of what each iteration accomplished
  guardrails.md    # Failure-driven rules (see guardrails skill)
  activity.log     # Optional: tool call log for monitoring
  errors.log       # Optional: failure log for gutter detection
```

## The Iteration Protocol

Each iteration follows this exact sequence:

### 1. Orient
- Read the task file for unchecked criteria
- Read `progress.md` for what's already done (especially Codebase Patterns section)
- Read `guardrails.md` for rules to follow
- Check git log for recent commits

### 2. Execute
- Pick ONE unchecked criterion (highest priority, or next in dependency order)
- Implement it with focused, minimal changes
- Run the project's quality checks (test, typecheck, lint)
- Fix any failures before moving on

### 3. Checkpoint
- `git add` only the specific files you changed (NEVER `git add -A`)
- Commit with message: `ralph: [criterion] - [short description]`
- Mark the criterion as `[x]` in the task file

### 4. Record
Append to `progress.md`:
```markdown
## Iteration N - [Criterion ID]
- What was implemented
- Files changed
- **Learnings:**
  - Patterns discovered
  - Gotchas encountered
---
```

If a learning is general and reusable, also add it to the **Codebase Patterns** section at the top of `progress.md`.

### 5. Evaluate
- If all criteria are `[x]`: signal COMPLETE
- If context is getting large: signal ROTATE (wrap up, commit, let next iteration continue)
- If stuck on the same error 3+ times: signal GUTTER (context is polluted, must start fresh)

## Signals

| Signal | Meaning | Action |
|--------|---------|--------|
| COMPLETE | All `[ ]` are `[x]` | Stop the loop |
| ROTATE | Context is filling up or task boundary reached | Commit state, start fresh iteration |
| GUTTER | Stuck in a failure loop, context polluted | Add guardrail, start fresh iteration |
| DEFER | Rate limit or transient error | Wait with backoff, retry same task |

## Sizing Rules

Each criterion must be completable in ONE iteration (one context window).

**Right-sized:**
- Add a database column and migration
- Create a single UI component
- Implement one API endpoint
- Add tests for one module

**Too big (split these):**
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API layer"

**Rule of thumb:** If you cannot describe the change in 2-3 sentences, it is too big.

## Dependency Ordering

Criteria execute top-to-bottom. Earlier criteria must not depend on later ones.

**Correct order:**
1. Schema / data layer changes
2. Backend logic / services
3. UI components that consume the backend
4. Integration / polish / docs

## Running The Loop

### With opencode
Paste the task file content as a prompt. When the agent completes an iteration, start a new conversation with the same prompt. The agent reads state from files.

### With a shell wrapper
```bash
#!/usr/bin/env bash
MAX_ITERATIONS=${1:-10}
for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo "=== Iteration $i ==="
  opencode -p "Load the ralph-loop skill. Read RALPH_TASK.md and continue the loop." \
    --output-format stream-json 2>&1
  # Check if complete
  if ! grep -q '\[ \]' RALPH_TASK.md; then
    echo "All criteria complete."
    break
  fi
done
```

### With cursor-agent
```bash
cursor-agent -p "$(cat RALPH_TASK.md)" --model opus-4.5-thinking
```

## Monitoring

```bash
# Watch progress in real-time
tail -f .ralph/progress.md

# Check remaining work
grep -c '\[ \]' RALPH_TASK.md

# See recent commits
git log --oneline -10
```
