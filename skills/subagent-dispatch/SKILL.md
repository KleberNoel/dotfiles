---
name: subagent-dispatch
description: "Multi-agent task delegation with quality gates. Dispatch fresh sub-agents per task, run spec-compliance and code-quality reviews before proceeding. Use when executing implementation plans, running parallel work, or coordinating multiple agents on a codebase."
license: MIT
metadata:
  pattern: subagent-driven-development
  origin: nousresearch/hermes-agent, opencode task tool, badlogic/pi-mono
---

# Subagent Dispatch: Multi-Agent Task Delegation

Break work into tasks. Dispatch a fresh agent per task. Review before merging. Never let one agent's context pollution infect the next task.

## Core Principle

**One fresh agent per task. Two reviews per task. No exceptions.**

A single long-running agent accumulates context debt. Subagent dispatch keeps each unit of work isolated and reviewed.

## When To Use This

- Executing an implementation plan with 3+ tasks
- Parallel feature development across a codebase
- Any workflow where quality gates matter (not just "get it done")
- When context window limits prevent doing everything in one shot

## The Protocol

### For each task in the plan:

```
1. DISPATCH   -> Fresh agent implements the task
2. REVIEW-1   -> Fresh agent checks spec compliance
3. REVIEW-2   -> Fresh agent checks code quality
4. GATE       -> Both reviews pass? Commit. Either fails? Fix and re-review.
```

### Step 1: Dispatch Implementer

Spawn a fresh agent with:
- The task description (from the plan)
- Relevant file paths and context
- The project's AGENTS.md and guardrails
- The specific acceptance criteria to meet

**Provide full context.** The subagent has no memory of previous tasks. Everything it needs must be in the prompt.

#### With opencode (task tool):
The task tool spawns a subagent automatically. Use the `general` agent type for implementation work, `explore` for read-only research.

#### With hermes (delegate_task):
```
delegate_task: "Implement US-003: Add status filter dropdown.
Files: src/components/TaskList.tsx, src/api/tasks.ts
Criteria: [paste from plan]
Follow AGENTS.md conventions. Run tests before reporting done."
```

#### With cursor-agent (CLI):
```bash
cursor-agent -p "Implement US-003: ..." --model sonnet-4.5-thinking
```

#### With shell (any agent):
```bash
opencode run -p "Implement US-003: ..." --format json
```

### Step 2: Spec Compliance Review

Spawn a DIFFERENT fresh agent to verify:

- [ ] Every acceptance criterion from the plan is met
- [ ] No criteria were skipped or partially implemented
- [ ] The implementation matches the spec, not just the tests
- [ ] Edge cases from the spec are handled

Prompt template:
```
Review this implementation for spec compliance.

SPEC:
[paste acceptance criteria]

FILES CHANGED:
[list files]

Read each changed file. For each criterion, state PASS or FAIL with evidence.
Do NOT suggest improvements -- only verify spec compliance.
```

### Step 3: Code Quality Review

Spawn ANOTHER fresh agent to check:

- [ ] Security: no hardcoded secrets, inputs validated, auth checked
- [ ] Error handling: failures caught, logged, cleaned up
- [ ] Code quality: SRP, descriptive names, no duplication
- [ ] Testing: new code has tests, existing tests not broken
- [ ] Conventions: follows AGENTS.md patterns, style matches codebase

Prompt template:
```
Review this code for quality issues.

FILES CHANGED:
[list files]

Check: security, error handling, code quality, testing, conventions.
For each issue found, state SEVERITY (critical/warning/info) and LOCATION.
```

### Step 4: Gate

**Both reviews must PASS before committing.**

If either review fails:
1. Read the failure feedback
2. Dispatch a new implementer agent with the original task + the review feedback
3. Re-run both reviews on the updated code
4. Repeat until both pass (max 3 attempts, then escalate to human)

## Task Sizing

Each task should be **2-10 minutes of focused agent work**. If it's bigger, split it.

**Right-sized:**
- Add one API endpoint with validation
- Create one UI component
- Write tests for one module
- Add one database migration

**Too big:**
- "Build the user system"
- "Refactor the frontend"
- "Add comprehensive tests"

## Parallel Dispatch

Independent tasks can run in parallel:

```
Plan:
  US-001: Add notifications table        (no dependencies)
  US-002: Create notification service     (depends on US-001)
  US-003: Add user preferences page       (no dependencies)

Execution:
  Batch 1 (parallel): US-001, US-003
  Batch 2 (sequential): US-002 (after US-001 merges)
```

### Parallel safety rules:
- Each agent works on different files (no overlap)
- Use git worktrees for true isolation if available
- Merge sequentially after all agents in a batch complete
- Run full test suite after merge

## Context Template

Every subagent dispatch should include:

```
## Task
[What to implement]

## Acceptance Criteria
[Verifiable checklist]

## Context Files
[Specific files to read]

## Conventions
[From AGENTS.md -- relevant subset]

## Guardrails
[From guardrails.md -- relevant signs]

## Quality Checks
[Commands to run: test, typecheck, lint]
```

## Integration with Other Skills

- **prd** produces the plan that this skill executes
- **tdd** governs how each implementer agent writes code
- **code-review** provides the review checklist for Step 2-3
- **git-checkpoint** governs how commits are made after the gate passes
- **guardrails** captures lessons learned from review failures
- **ralph-loop** can use subagent-dispatch within each iteration for complex criteria
