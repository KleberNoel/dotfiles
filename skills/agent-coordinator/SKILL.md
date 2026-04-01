---
name: agent-coordinator
description: "Parallel agent orchestration: decompose complex tasks, dispatch sub-agents with isolated git worktrees, collect and synthesize results. Covers the Research-Synthesis-Implementation-Verification phase model, worktree lifecycle, sub-agent tool scoping, recursion prevention, and result merging. Use when a task benefits from parallel execution or exceeds a single agent's scope."
license: MIT
metadata:
  pattern: agent-coordinator
  sources: claude-code
---

# Agent Coordinator: Parallel Orchestration with Worktree Isolation

When a task is too large for one agent, a coordinator decomposes it and dispatches sub-agents to work in parallel. Each sub-agent gets its own git worktree for isolation, its own context window, and a scoped set of tools. The coordinator collects results, resolves conflicts, and synthesizes the final output.

## When to Use Coordinator Mode

- Task involves 3+ independent components that can be worked on simultaneously
- Research phase needs to explore multiple areas of a codebase in parallel
- Implementation spans multiple packages/services in a monorepo
- Task would exceed a single agent's context window
- Time-sensitive work that benefits from parallelism

## When NOT to Use Coordinator Mode

- Simple, linear tasks (adding a function, fixing a bug)
- Tasks where steps are strictly sequential (each depends on the previous)
- Exploration tasks where the agent needs to build context iteratively
- Small codebases where parallel work creates more overhead than value

## The Four-Phase Model

### Phase 1: Research (Parallel)

The coordinator dispatches multiple sub-agents to gather information:

```
Coordinator:
  "I need to understand the codebase before implementing.
   Dispatching 3 research agents in parallel."

Agent A → "Read all files in src/auth/ and summarize the auth architecture"
Agent B → "Read all test files and identify the testing patterns used"
Agent C → "Read package.json, tsconfig.json, and document the build setup"
```

**Rules:**
- Research agents are READ-ONLY (Plan mode)
- Each agent gets a focused, non-overlapping scope
- Results are structured summaries, not raw file contents

### Phase 2: Synthesis (Coordinator Only)

The coordinator processes research results and creates an implementation plan:

```
Coordinator:
  "Based on research results:
   - Auth uses JWT with refresh tokens (Agent A)
   - Tests use Jest + supertest for API tests (Agent B)
   - Build is ESM-only TypeScript with strict mode (Agent C)

   Implementation plan:
   1. Create new auth middleware (Worker 1)
   2. Create API endpoints (Worker 2)
   3. Create tests (Worker 3)"
```

**Rules:**
- Only the coordinator runs during synthesis
- Plan must account for dependencies between workers
- Each worker's scope must be clearly defined

### Phase 3: Implementation (Parallel)

Workers execute the plan in isolated worktrees:

```
Worker 1 → [worktree: wt-auth-middleware]
           Create src/middleware/rate-limit.ts
           Modify src/auth/index.ts

Worker 2 → [worktree: wt-api-endpoints]
           Create src/routes/admin.ts
           Create src/routes/admin.test.ts

Worker 3 → [worktree: wt-integration-tests]
           Create tests/integration/admin-flow.test.ts
```

**Rules:**
- Each worker operates in its own git worktree
- Workers should NOT modify the same files (scope separation)
- Workers have Write + Execute permissions within their worktree
- Workers cannot dispatch sub-agents (recursion prevention)

### Phase 4: Verification (Coordinator)

The coordinator collects results, merges worktrees, and verifies:

```
Coordinator:
  1. Collect results from all workers
  2. Merge worktree changes into main branch
  3. Resolve any conflicts (should be rare with good scoping)
  4. Run full test suite
  5. Fix any integration issues
  6. Clean up worktrees
```

## The Agent Tool

The coordinator dispatches sub-agents via an `AgentTool`:

### Input Schema

```json
{
  "description": "Research the authentication system architecture",
  "prompt": "Read all files in src/auth/ and return a structured summary...",
  "tools": ["read", "glob", "grep", "bash"],
  "system_prompt": "You are a research agent. Read-only. Return structured summaries.",
  "max_turns": 20,
  "model": "sonnet"
}
```

### Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `description` | string | yes | Brief description of the sub-task |
| `prompt` | string | yes | Full instructions for the sub-agent |
| `tools` | string[]? | no | Allowed tools (default: all minus AgentTool) |
| `system_prompt` | string? | no | Override system prompt for sub-agent |
| `max_turns` | int? | no | Max query loop iterations (default: 30) |
| `model` | string? | no | Model to use (default: same as coordinator) |

### Recursion Prevention

The AgentTool **always excludes itself** from the sub-agent's tool set:

```
function get_sub_agent_tools(requested_tools):
    available = requested_tools or all_tools()
    available = available.remove("agent")        # Cannot dispatch sub-agents
    available = available.remove("coordinator")   # Cannot enter coordinator mode
    available = available.remove("send_message")  # Cannot message user directly
    return available
```

This prevents infinite nesting: coordinator → agent → agent → agent → ...

## Git Worktree Isolation

Each implementation worker gets its own git worktree to prevent file conflicts:

### Creating a Worktree

```bash
# Create worktree from current branch
git worktree add ../wt-auth-middleware -b worker/auth-middleware

# Worker operates in ../wt-auth-middleware/
# Full copy of repo at the branch point
# Changes are isolated until explicitly merged
```

### Worktree Lifecycle

```
function dispatch_worker_with_worktree(task):
    worktree_name = f"wt-{sanitize(task.name)}"
    worktree_path = f"../{worktree_name}"
    branch_name = f"worker/{sanitize(task.name)}"

    # Create
    git worktree add {worktree_path} -b {branch_name}

    # Dispatch agent with worktree as working_dir
    result = agent_tool.execute(
        prompt=task.prompt,
        working_dir=worktree_path,
        tools=task.tools
    )

    # Collect changes
    changes = git log --oneline main..{branch_name}

    return WorkerResult(
        branch=branch_name,
        worktree=worktree_path,
        changes=changes,
        result=result
    )
```

### Merging Results

```
function merge_worker_results(workers):
    for worker in workers:
        # Merge worker branch into main
        git merge {worker.branch} --no-ff \
            -m "Merge {worker.branch}: {worker.description}"

        # If conflict:
        if merge_has_conflicts():
            # Coordinator resolves manually or dispatches a resolution agent
            resolve_conflicts(worker)

        # Clean up
        git worktree remove {worker.worktree}
        git branch -d {worker.branch}
```

### Worktree Rules

1. **One worktree per worker** — never share worktrees between agents
2. **Clean up on completion** — always remove worktrees and branches when done
3. **Scope separation** — workers should touch different files to minimize merge conflicts
4. **Branch from same point** — all worktrees branch from the same commit on main
5. **Merge order matters** — merge workers with fewer dependencies first

## Coordinator's Tool Set

The coordinator has a restricted set of tools (it delegates, doesn't implement):

```
COORDINATOR_TOOLS = [
    "agent",           # Dispatch sub-agents
    "task_stop",       # Signal task completion
    "send_message",    # Communicate with user
    "read",            # Read files (for planning and verification)
    "glob",            # Find files (for planning)
    "grep",            # Search files (for planning)
    "bash",            # Run commands (for verification: tests, builds)
]
```

The coordinator should NOT directly write files — that's the workers' job.

## Task Decomposition Strategy

### Good Decomposition

```
Task: "Add user authentication to the Express app"

Worker 1: Auth middleware + JWT utilities     (src/auth/*)
Worker 2: User model + database migration     (src/models/*, src/db/*)
Worker 3: Auth API endpoints                  (src/routes/auth/*)
Worker 4: Auth integration tests              (tests/auth/*)
```

Each worker has a clear, non-overlapping scope. Dependencies are minimal (Worker 3 needs Worker 1's middleware, but can stub it).

### Bad Decomposition

```
Task: "Add user authentication to the Express app"

Worker 1: "Do the first half of auth"
Worker 2: "Do the second half of auth"
```

Overlapping scope, undefined boundaries, guaranteed merge conflicts.

### Decomposition Rules

1. **Split by component/module**, not by percentage of work
2. **Define file boundaries** — each worker owns specific directories
3. **Minimize cross-worker dependencies** — if Worker B needs Worker A's output, they can't truly parallelize
4. **Include tests with implementation** — don't separate test writing from feature writing
5. **Cap at 5 workers** — more workers = more coordination overhead

## Error Handling

### Worker Failure

```
function handle_worker_failure(worker, error):
    match error:
        ContextExhausted:
            # Worker ran out of context — task was too big
            # Split into smaller sub-tasks and retry
            sub_tasks = decompose_further(worker.task)
            for sub in sub_tasks:
                dispatch_worker(sub)

        ToolError:
            # A tool failed — retry the worker with guidance
            dispatch_worker(worker.task,
                extra_prompt=f"Previous attempt failed: {error}. Try a different approach.")

        Timeout:
            # Worker took too long — check partial progress
            partial = collect_partial_results(worker)
            if partial.has_commits:
                # Use what we got, dispatch new worker for remainder
                dispatch_worker(remaining_task(worker.task, partial))
            else:
                # No progress — retry once, then report failure
                retry_or_fail(worker)
```

### Merge Conflicts

```
function resolve_conflicts(worker):
    conflicting_files = git diff --name-only --diff-filter=U

    if len(conflicting_files) <= 3:
        # Few conflicts — coordinator resolves directly
        for file in conflicting_files:
            content = read(file)
            # Use model to resolve conflict markers
            resolved = resolve_with_model(content)
            write(file, resolved)
        git add . && git commit -m "Resolve merge conflicts from {worker.branch}"
    else:
        # Many conflicts — scope was wrong, re-plan
        git merge --abort
        replan_with_better_scope(worker)
```

## Result Collection Format

Workers return structured results to the coordinator:

```json
{
  "status": "completed",
  "files_created": ["src/auth/middleware.ts", "src/auth/jwt.ts"],
  "files_modified": ["src/app.ts"],
  "tests_added": 5,
  "tests_passing": 5,
  "summary": "Created JWT auth middleware with token validation and refresh. Integrated into Express app via app.use(authMiddleware).",
  "issues": [],
  "dependencies": ["Worker 3 needs to import authMiddleware from src/auth/"]
}
```

## Integration Points

### With subagent-dispatch
`subagent-dispatch` defines the delegation mechanics (how to call sub-agents). `agent-coordinator` defines the strategic orchestration layer (when, why, and how to decompose).

### With context-management
Each sub-agent has its own context window. The coordinator should pass minimal context — just the task description and relevant file paths, not the full conversation history.

### With git-checkpoint
Workers commit their changes to their worktree branches. The coordinator merges branches using safe git operations from `git-checkpoint`.

### With permission-safety
Sub-agents inherit the coordinator's permission level or stricter. Workers in Plan mode (research phase) cannot write files.

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| Too many workers (10+) | Coordination overhead exceeds parallelism benefit | Cap at 5, decompose better |
| Workers sharing files | Merge conflicts guaranteed | Non-overlapping file boundaries |
| No verification phase | Merged code may not compile or pass tests | Always run tests after merging |
| Coordinator implementing directly | Defeats the purpose, wastes context | Delegate to workers |
| Sub-agents dispatching sub-agents | Uncontrolled recursion | Block AgentTool in sub-agents |
| Skipping worktrees | Workers overwrite each other's changes | Always isolate with worktrees |
