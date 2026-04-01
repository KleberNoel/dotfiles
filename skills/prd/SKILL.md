---
name: prd
description: "Generate a structured Product Requirements Document from a feature description. Decomposes work into right-sized user stories with verifiable acceptance criteria. Output is ready for autonomous execution via ralph-loop or manual implementation."
license: MIT
metadata:
  pattern: prd-decomposition
  origin: snarktank/ralph
---

# PRD: Requirements Decomposition

Take a feature idea and produce a structured plan with right-sized, dependency-ordered tasks that have verifiable completion criteria.

## When To Use This

- Starting a new feature and need a plan before coding
- Breaking a large task into agent-sized pieces
- Creating a `RALPH_TASK.md` or `prd.json` for autonomous loops
- Turning a vague request into concrete acceptance criteria

## The Process

### Step 1: Clarify (3-5 questions max)

Ask only where the prompt is ambiguous. Use lettered options for fast answers:

```
1. What is the primary goal?
   A. [Option]
   B. [Option]
   C. [Option]

2. What is the scope?
   A. Minimal viable version
   B. Full implementation
   C. Backend only
   D. Frontend only
```

User responds "1A, 2B" -- fast iteration.

### Step 2: Decompose Into Stories

Each story must follow the sizing rule: **completable in one focused session** (one context window for agents, one sitting for humans).

#### Story Format

```markdown
### US-001: [Short Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific, verifiable criterion
- [ ] Another verifiable criterion
- [ ] Quality checks pass (typecheck/lint/test)
```

#### Sizing Guide

**Right-sized:**
- Add a column and migration
- Create one UI component
- Implement one endpoint with validation
- Add tests for one module

**Too big -- split these:**
- "Build the dashboard" -> schema, queries, components, filters, layout
- "Add auth" -> schema, middleware, login UI, session, password reset
- "Refactor the API" -> one story per endpoint or pattern

**Rule of thumb:** If you cannot describe the change in 2-3 sentences, split it.

#### Dependency Ordering

Stories execute in order. Earlier stories must not depend on later ones:

1. Schema / data layer
2. Backend logic / services
3. UI components consuming the backend
4. Integration, polish, documentation

### Step 3: Write Acceptance Criteria

Every criterion must be something an agent (or reviewer) can **verify**.

**Good (verifiable):**
- "Add `status` column with default `'pending'`"
- "GET /users returns 200 with JSON array"
- "Filter dropdown has options: All, Active, Completed"
- "Tests pass"

**Bad (vague):**
- "Works correctly"
- "Good UX"
- "Handles edge cases"

**Always include as final criterion:**
- "Typecheck/lint passes" (every story)
- "Tests pass" (stories with testable logic)
- "Verify in browser" (stories that change UI)

## Output Formats

### Markdown (for RALPH_TASK.md)

```markdown
---
task: [Feature Name]
test_command: "[project test command]"
---

# Task: [Feature Name]

[Brief description]

## Success Criteria

1. [ ] US-001: [criterion summary]
2. [ ] US-002: [criterion summary]
3. [ ] All tests pass
4. [ ] Typecheck passes

## Stories

### US-001: [Title]
...
```

### JSON (for prd.json / ralph.sh)

```json
{
  "project": "[Project Name]",
  "branchName": "ralph/[feature-kebab-case]",
  "description": "[Feature description]",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Criterion 1",
        "Criterion 2",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Cursor RALPH_TASK.md (for ralph-wiggum-cursor)

```markdown
---
task: [Feature Name]
test_command: "[project test command]"
---

# Task: [Feature Name]

[Brief description]

## Success Criteria

1. [ ] First criterion
2. [ ] Second criterion
3. [ ] All tests pass
```

Pick the format that matches your agent tooling. All three encode the same information.

## Splitting Large Features

**Original:** "Add user notification system"

**Split into:**
1. US-001: Add notifications table
2. US-002: Create notification service
3. US-003: Add notification bell to header
4. US-004: Create notification dropdown
5. US-005: Mark-as-read functionality
6. US-006: Notification preferences page

Each story is one focused change, independently verifiable.

## Checklist Before Saving

- [ ] Each story completable in one session/iteration
- [ ] Stories ordered by dependency (data -> logic -> UI -> polish)
- [ ] Every story has verifiable acceptance criteria
- [ ] Quality checks included (typecheck, tests)
- [ ] UI stories include browser verification
- [ ] No story depends on a later story
- [ ] Non-goals / scope boundaries documented
