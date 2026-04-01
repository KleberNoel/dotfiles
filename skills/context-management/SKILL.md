---
name: context-management
description: "Manage LLM context window budget, auto-compaction, and memory persistence across sessions. Covers token awareness, HEAD/TAIL compaction algorithm, circuit breakers, memory tiers (short/medium/long-term), and the dream consolidation pattern. Use when building agents that must survive context limits, persist knowledge, or run multi-session workflows."
license: MIT
metadata:
  pattern: context-management
  sources: code-agents, claude-code, ralph
---

# Context Management: Budget, Compaction, and Memory Persistence

Agents die when they run out of context. This skill teaches how to monitor token budgets, auto-compact conversations, persist memory across sessions, and consolidate knowledge during idle periods.

## Context Window Awareness

Every model has a fixed context window. An agent must track usage and act before hitting the limit.

### Token Budget Constants

```
MODEL_CONTEXT_LIMITS:
  claude-opus:     200_000
  claude-sonnet:   200_000
  gpt-4o:          128_000
  gpt-4-turbo:     128_000

AUTOCOMPACT_TRIGGER_FRACTION = 0.90    # Compact at 90% usage
AUTOCOMPACT_WARNING_FRACTION = 0.85    # Warn at 85% usage
AUTOCOMPACT_BUFFER_TOKENS    = 13_000  # Reserve for compaction prompt + response
KEEP_RECENT_MESSAGES         = 10      # Tail messages preserved during compaction
MAX_CONSECUTIVE_FAILURES     = 3       # Circuit breaker threshold
```

### Monitoring Rules

1. **After every API response**, check `usage.total_tokens / model_context_limit`
2. At 85%: emit a warning — "Context at 85%, compaction imminent"
3. At 90%: trigger auto-compaction immediately
4. At 95% with compaction failed: signal ROTATE (start fresh context)

## Auto-Compaction Algorithm

When the trigger fires, split the conversation and summarize the older portion.

### Steps

```
1. SPLIT conversation into HEAD and TAIL
   - TAIL = last KEEP_RECENT_MESSAGES (10) messages (always preserved verbatim)
   - HEAD = everything before TAIL

2. SUMMARIZE HEAD
   - Send HEAD to the model with a compaction prompt
   - Request structured summary (see format below)
   - This costs AUTOCOMPACT_BUFFER_TOKENS from your budget

3. REPLACE conversation
   - New conversation = [system_prompt] + [compact_summary_message] + [TAIL]
   - The summary becomes a single "assistant" message at the top

4. VALIDATE
   - New total tokens < 50% of context limit (target)
   - All TAIL messages preserved exactly
   - Summary contains all critical state
```

### Summary Format

The compaction summary must be structured to preserve actionable state:

```xml
<compact-summary>
  <decisions>
    - Chose PostgreSQL over SQLite for concurrent access
    - Using repository pattern for data layer
  </decisions>
  <file-paths>
    - src/db/connection.py (created, connection pool)
    - src/models/user.py (modified, added email field)
    - tests/test_db.py (created, 3 passing tests)
  </file-paths>
  <codebase-patterns>
    - All models inherit from BaseModel in src/models/base.py
    - Tests use pytest fixtures from conftest.py
    - Environment config loaded from .env via python-dotenv
  </codebase-patterns>
  <current-task>
    Implementing user registration endpoint. Schema validated,
    DB migration written. Next: write the POST /register handler.
  </current-task>
  <blockers>
    - Email service not configured yet (needed for verification)
  </blockers>
</compact-summary>
```

### What Must Be Preserved

- Architectural decisions and their rationale
- File paths created, modified, or deleted (with brief description)
- Discovered codebase patterns and conventions
- Current task state and next steps
- Known blockers or failures
- Guardrail rules accumulated during session

### What Can Be Dropped

- Verbose tool outputs (file contents, command outputs)
- Exploratory dead ends that led nowhere
- Repeated back-and-forth on resolved questions
- Raw error traces (keep only the diagnosis)

## Circuit Breaker

Compaction can fail (model produces garbage, token count doesn't decrease, API error).

```
if consecutive_compaction_failures >= MAX_CONSECUTIVE_FAILURES (3):
    disable auto-compact for this session
    signal ROTATE to the orchestrator
    persist all state to disk before rotating
```

**Recovery after ROTATE:**
1. Write `progress.md` with current state
2. Commit all work to git
3. Start fresh agent context
4. New agent reads `progress.md` + git log to resume

This integrates directly with the `ralph-loop` skill — context rotation is a first-class event in the ralph iteration cycle.

## Memory Tiers

Agents need memory at three time scales.

### Tier 1: Short-Term (Session State)

Lives in `.state/` directory within the project. Ephemeral, per-session.

```
.state/
  session.json        # Current session ID, start time, iteration count
  conversation.jsonl  # Raw conversation log (append-only)
  tool-results/       # Cached tool outputs (keyed by hash)
  compact-history/    # Previous compaction summaries
```

**Rules:**
- `.state/` is gitignored
- Any agent can read `.state/` to warm-start
- Delete on explicit `reset` command

### Tier 2: Medium-Term (Project Memory)

Lives in project-local files that are git-tracked and discovered via directory walk.

**Discovery algorithm:**
```
Walk from CWD to filesystem root, collecting:
  CLAUDE.md, AGENTS.md, .cursorrules, .github/copilot-instructions.md

Merge order: root-most first, CWD-most last (closest wins on conflicts)
```

**What goes in CLAUDE.md / AGENTS.md:**
- Project conventions (naming, architecture, test patterns)
- Common commands (build, test, lint, deploy)
- Known gotchas and workarounds
- Dependencies and their purposes

**Rules:**
- Keep under 500 lines — agents read this every session start
- Update when you discover a new convention or gotcha
- Never store secrets or credentials

### Tier 3: Long-Term (Cross-Project Memory)

Lives in `~/.claude/memory/` (or `~/.agents/memory/`) with a `MEMORY.md` index.

```
~/.claude/memory/
  MEMORY.md           # Index file, max 200 lines (~25KB)
  topics/
    python-patterns.md
    git-workflows.md
    debugging-techniques.md
```

**MEMORY.md format:**
```markdown
# Agent Memory Index

## Python Patterns
- Always use `ruff` for linting in this user's projects
- User prefers pytest over unittest
- See: topics/python-patterns.md

## Git Workflows
- User uses conventional commits
- Squash merge preferred for feature branches
- See: topics/git-workflows.md
```

**Rules:**
- MEMORY.md index must stay under 200 lines
- Topic files should be focused and under 100 lines each
- Only store patterns confirmed across 2+ projects
- Prune entries not referenced in 30+ days

## Dream Pattern: Background Consolidation

The "dream" pattern consolidates scattered session learnings into long-term memory during idle periods.

### Three-Gate Trigger

ALL three conditions must be true to start a dream cycle:

```
1. TIME:     >= 24 hours since last dream
2. SESSIONS: >= 5 sessions completed since last dream
3. LOCK:     No other agent holds the dream lock file
```

### Four-Phase Process

```
Phase 1: ORIENT
  - Read MEMORY.md index
  - List all session logs from .state/compact-history/
  - Identify sessions since last dream

Phase 2: GATHER
  - Read compact summaries from recent sessions
  - Extract: decisions, patterns, file-paths, blockers
  - Deduplicate across sessions

Phase 3: CONSOLIDATE
  - Group findings by topic
  - Update existing topic files with new patterns
  - Create new topic files if a cluster emerges (3+ related findings)
  - Update MEMORY.md index

Phase 4: PRUNE
  - Remove topic entries not seen in 30+ days
  - Merge overlapping topics
  - Enforce line limits (MEMORY.md < 200 lines)
  - Record dream timestamp
```

### Safety Constraints

- **Read-only for project files** — dream only writes to `~/.claude/memory/`
- Dream must acquire a lock file (`~/.claude/memory/.dream.lock`) before starting
- If lock exists and is < 1 hour old, skip this dream cycle
- If lock exists and is > 1 hour old, assume stale, delete and proceed
- Dream should complete in under 60 seconds

## Integration Points

### With ralph-loop

Context rotation in ralph IS the compaction escape hatch:
```
ralph iteration:
  if context_warning(85%):
    commit progress
    write progress.md
  if context_critical(90%):
    attempt compact
    if compact_fails 3x:
      ROTATE (start new iteration)
```

### With subagent-dispatch

Sub-agents get a **separate context window**. The parent should:
1. Pass only the relevant subset of context to the sub-agent
2. Receive back a structured result (not raw conversation)
3. Integrate the result into its own compact summary

### With guardrails

Guardrail rules survive compaction — they are always included in the compact summary under `<codebase-patterns>` or as a dedicated `<guardrails>` section.

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| Stuffing entire files into context | Wastes tokens on unchanged code | Read only the relevant lines/functions |
| Never compacting | Context degrades, model gets confused | Set up auto-compact at 90% |
| Losing decisions during compaction | Repeating resolved debates | Always preserve `<decisions>` in summary |
| Storing everything in long-term memory | Index bloats, retrieval degrades | Only store patterns confirmed across 2+ projects |
| Compacting too aggressively | Lose important recent context | Keep last 10 messages verbatim |
| Ignoring compaction failures | Agent crashes at limit | Circuit breaker after 3 failures, then ROTATE |
