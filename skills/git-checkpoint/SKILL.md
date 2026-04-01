---
name: git-checkpoint
description: "Safe git commit, branch, and state management protocols for AI agents. Prevents destructive operations, enforces selective staging, and provides patterns for multi-agent parallel work. Use when committing code, managing branches, or coordinating with other agents."
license: MIT
metadata:
  pattern: git-safety
  origin: badlogic/pi-mono, snarktank/ralph
---

# Git Checkpoint: Safe State Management for Agents

Agents must treat git as their persistent memory. These protocols prevent data loss, support multi-agent work, and keep history clean.

## Core Rule

**State lives in git, not in context.** Commit frequently. Every commit is a checkpoint that the next iteration (or agent) can pick up from.

## Selective Staging (The #1 Rule)

**NEVER use `git add -A` or `git add .`**

Always stage specific files:

```bash
# Check what changed
git status

# Stage ONLY files you modified
git add src/api/users.ts
git add src/api/users.test.ts
git add CHANGELOG.md

# Verify before committing
git diff --cached --stat

# Commit
git commit -m "feat: add user CRUD endpoints"
```

Why: Other agents or humans may have uncommitted work. Sweeping `git add -A` stages their changes into your commit.

## Forbidden Operations

These destroy state and are NEVER safe for agents to run:

| Command | Why It's Dangerous |
|---------|--------------------|
| `git reset --hard` | Destroys all uncommitted changes |
| `git checkout .` | Discards all unstaged modifications |
| `git clean -fd` | Deletes untracked files permanently |
| `git stash` | Captures ALL changes, including other agents' work |
| `git push --force` | Rewrites remote history |
| `git commit --no-verify` | Bypasses pre-commit hooks |
| `git rebase -i` | Interactive -- requires terminal input |
| `git add -A` / `git add .` | Stages other agents' uncommitted work |

## Commit Message Format

Use conventional commits. Include issue references when applicable:

```
feat: add user registration endpoint

closes #42
```

For ralph-loop iterations:
```
ralph: US-003 - add status filter dropdown
```

Prefixes: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`, `ralph:`

## Branch Workflow

### Creating a feature branch
```bash
git checkout -b feature/short-name main
```

### Working on an existing branch
```bash
git checkout feature/short-name
git pull --rebase origin feature/short-name
```

### Pushing
```bash
git push -u origin feature/short-name
```

### If rebase conflicts occur
- Resolve conflicts ONLY in files you modified
- If conflict is in a file you did not touch, abort and ask the user
- NEVER force push to resolve conflicts

## Multi-Agent Protocol

When multiple agents work in the same repo simultaneously:

### Track Your Files
Maintain a mental list of files you created or modified. Only commit those.

### Safe Workflow
```bash
# 1. See the full picture
git status

# 2. Stage ONLY your files
git add path/to/your/file1.ts
git add path/to/your/file2.ts

# 3. Commit
git commit -m "feat(module): description"

# 4. Push (pull --rebase if needed)
git pull --rebase && git push
```

### Parallel Worktrees (for isolation)
```bash
# Create isolated worktree for a task
git worktree add ../task-branch-name -b task-branch-name

# Work in isolation
cd ../task-branch-name

# Clean up when done
cd ..
git worktree remove task-branch-name
```

## Checkpoint Pattern for Long Tasks

Commit at natural boundaries, not just at the end:

```bash
# After schema change
git add migrations/ src/db/schema.ts
git commit -m "feat: add notifications table"

# After service layer
git add src/services/notifications.ts src/services/notifications.test.ts
git commit -m "feat: notification service with send/mark-read"

# After UI
git add src/components/NotificationBell.tsx
git commit -m "feat: notification bell component"
```

If context rotates or the agent crashes, the next iteration picks up from the last commit.

## Pre-Commit Checks

Before every commit, run the project's quality checks:

```bash
# Detect the project's check command
# npm/node projects:
npm run check   # or: npm test
# Python projects:
pytest           # or: make test
# Rust projects:
cargo check && cargo test
# Go projects:
go vet ./... && go test ./...
```

Do NOT commit if checks fail. Fix first, then commit.

## Linking Commits to Issues

When closing an issue via commit:
```
fix: resolve race condition in session handler

fixes #123
```

GitHub/GitLab auto-closes the issue when the commit merges.

## Inspecting State

```bash
# Recent history
git log --oneline -10

# What changed in last commit
git show --stat HEAD

# What's uncommitted
git diff --stat

# Who changed a file recently
git log --oneline -5 -- path/to/file.ts
```
