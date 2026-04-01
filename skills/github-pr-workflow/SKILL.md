---
name: github-pr-workflow
description: "End-to-end GitHub pull request lifecycle: branch strategy, conventional commits, PR creation, CI monitoring with auto-fix loops, code review, and merge. Covers both authoring PRs and reviewing others' PRs. Use when working with GitHub repos, submitting changes for review, or reviewing pull requests."
license: MIT
metadata:
  pattern: github-pr-workflow
  sources: hermes-agent, code-agents, opencode
---

# GitHub PR Workflow: Branch to Merge

Complete lifecycle for GitHub pull requests — from branch creation through CI green to merge. Covers both the author and reviewer roles.

## Branch Strategy

### Naming Convention

```
feat/short-description      # New feature
fix/short-description       # Bug fix
refactor/short-description  # Code restructure, no behavior change
docs/short-description      # Documentation only
test/short-description      # Test additions or fixes
chore/short-description     # Build, CI, dependency updates
```

### Branch Creation

Always branch from an up-to-date default branch:

```bash
git fetch origin
git checkout -b feat/add-user-auth origin/main
```

**Rules:**
- Never branch from a stale local main — always use `origin/main`
- One logical change per branch — don't mix features
- Keep branches short-lived (< 1 week ideally)

## Commit Quality

### Conventional Commits

Format: `type(scope): description`

```
feat(auth): add JWT token refresh endpoint
fix(api): handle null response from payment gateway
refactor(db): extract connection pool into shared module
test(auth): add integration tests for login flow
docs(readme): update deployment instructions
chore(deps): bump axios from 1.6.0 to 1.7.2
```

**Rules:**
- Subject line: imperative mood, lowercase, no period, max 72 chars
- Body (optional): explain WHY, not WHAT — the diff shows what changed
- Footer: reference issues with `Fixes #123` or `Closes #456`

### Atomic Commits

Each commit should:
1. Represent one logical change
2. Leave the codebase in a buildable, testable state
3. Pass all existing tests (don't break and fix in separate commits)

### Forbidden Commit Operations

| Operation | Why It's Dangerous | Safe Alternative |
|---|---|---|
| `git commit --amend` after push | Rewrites shared history | New commit with fix |
| `git push --force` to main/master | Destroys team history | Never. Period. |
| `git push --force` to shared branch | Overwrites others' work | `--force-with-lease` on your own branch |
| `--no-verify` | Skips safety hooks | Fix the hook issue properly |
| Committing `.env` or secrets | Credential leak | Add to `.gitignore`, use vault |

## PR Creation

### Using gh CLI

```bash
gh pr create \
  --title "feat(auth): add JWT token refresh" \
  --body "$(cat <<'EOF'
## Summary
- Add automatic JWT token refresh when access token expires
- Refresh happens transparently in the HTTP interceptor

## Changes
- `src/auth/interceptor.ts` — Added refresh logic before 401 retry
- `src/auth/token-service.ts` — New `refreshToken()` method
- `tests/auth/interceptor.test.ts` — 4 new test cases

## Testing
- All existing tests pass
- New tests cover: happy path, expired refresh token, concurrent refresh, network error
- Manual testing: verified token refresh in browser devtools

Fixes #142
EOF
)"
```

### PR Body Format

Every PR body should have:

```markdown
## Summary
1-3 bullet points explaining WHAT and WHY (not HOW)

## Changes
List of files changed with brief description of each

## Testing
How the changes were verified (automated tests, manual steps, both)

## Related
Links to issues, related PRs, or design docs
```

### Draft vs Ready

- Use `--draft` when you want early feedback before the code is complete
- Convert to ready with `gh pr ready`
- Drafts don't trigger required reviewers or auto-merge

## CI Monitoring Loop

After pushing, monitor CI and fix failures in a loop:

```
MAX_CI_FIX_ATTEMPTS = 3

for attempt in 1..MAX_CI_FIX_ATTEMPTS:
    push changes
    wait for CI to complete (gh pr checks --watch)

    if all checks pass:
        break  # Done

    # CI failed — diagnose and fix
    read CI logs (gh run view <run-id> --log-failed)
    identify failure root cause
    apply fix
    commit fix with message: "fix(ci): <description of what failed>"

if attempts exhausted and CI still fails:
    comment on PR explaining the persistent failure
    request human help
    do NOT merge
```

### Reading CI Logs

```bash
# Watch checks in real-time
gh pr checks --watch

# List recent workflow runs
gh run list --limit 5

# View failed job logs
gh run view <run-id> --log-failed

# View specific job
gh run view <run-id> --job <job-id> --log
```

### Common CI Failures and Fixes

| Failure Type | Diagnosis | Fix |
|---|---|---|
| Type errors | Read the error locations | Fix types, commit |
| Lint failures | Usually auto-fixable | Run linter with `--fix`, commit |
| Test failures | Read test output carefully | Fix code or update test expectations |
| Build failures | Missing dependency or config | Check imports, package.json, build config |
| Timeout | Test too slow or infinite loop | Optimize or add timeout |
| Flaky test | Passes sometimes, fails others | Add retry or fix race condition |

## Code Review (As Reviewer)

### Reading a PR

```bash
# View PR diff
gh pr diff <number>

# View PR details
gh pr view <number>

# Check out PR locally for testing
gh pr checkout <number>

# View specific file in the PR
gh api repos/{owner}/{repo}/pulls/{number}/files
```

### Review Checklist

For each PR, evaluate:

1. **Correctness** — Does the code do what it claims? Edge cases handled?
2. **Tests** — Are new behaviors tested? Are tests meaningful (not just coverage)?
3. **Security** — Input validation? Auth checks? No secrets in code?
4. **Performance** — Any O(n^2) loops on large data? Unnecessary allocations?
5. **Readability** — Clear naming? Comments where needed? Not over-engineered?
6. **Consistency** — Follows existing project conventions and patterns?

### Submitting Review

```bash
# Approve
gh pr review <number> --approve --body "Looks good. Clean implementation."

# Request changes
gh pr review <number> --request-changes --body "$(cat <<'EOF'
## Issues to Address

1. **Security**: The `userId` parameter in `GET /users/:id` is not validated.
   An attacker could pass SQL injection. Use parameterized queries.

2. **Test gap**: No test for the case where the user doesn't exist (404 path).

3. **Naming**: `doStuff()` in `handler.ts:45` — please give this a descriptive name.
EOF
)"

# Comment without approval/rejection
gh pr review <number> --comment --body "Minor suggestions, nothing blocking."
```

### Review Comment Guidelines

- Be specific — reference file and line number
- Explain WHY something is a problem, not just that it is
- Suggest a fix when possible
- Distinguish blocking issues from nits: prefix nits with `nit:` or `suggestion:`
- Never approve a PR that has known security issues or missing tests for critical paths

## Merge Strategy

### Choosing Merge Method

| Method | When to Use |
|---|---|
| **Squash merge** | Feature branches with messy/WIP commits. Creates clean single commit on main. |
| **Merge commit** | When individual commits are meaningful and clean. Preserves full history. |
| **Rebase** | Linear history preference. Each commit must be atomic and clean. |

### Pre-Merge Checklist

```
[ ] All CI checks pass (green)
[ ] Required reviewers have approved
[ ] No unresolved review comments
[ ] Branch is up to date with base branch
[ ] PR description accurately reflects final state
```

### Merge Commands

```bash
# Squash merge (most common for feature branches)
gh pr merge <number> --squash --delete-branch

# Merge commit
gh pr merge <number> --merge --delete-branch

# If branch is behind, update first
gh pr merge <number> --squash --delete-branch --auto
# --auto waits for checks and merges when ready
```

### Post-Merge Cleanup

```bash
# Switch back to main and pull
git checkout main && git pull origin main

# Delete local branch
git branch -d feat/add-user-auth

# Remote branch is deleted by --delete-branch flag above
```

## Forbidden Operations

These operations are NEVER acceptable:

1. **Force push to main/master** — Destroys shared history for the entire team
2. **Merge with failing CI** — Breaks main for everyone
3. **Skip hooks with `--no-verify`** — Hooks exist for a reason
4. **Delete remote branches you don't own** — Check with the author first
5. **Merge your own PR without review** — Unless repo policy explicitly allows it
6. **Commit secrets, tokens, or credentials** — Even if you revert, they're in git history
7. **Squash-merge a branch others are branched from** — Causes merge conflicts for everyone

## Integration Points

### With git-checkpoint

The `git-checkpoint` skill handles the safe-commit mechanics. This skill handles the GitHub layer on top:
- `git-checkpoint` = safe local git operations
- `github-pr-workflow` = PR lifecycle on GitHub

### With ralph-loop

During a ralph iteration, the agent may need to:
1. Create a branch and PR (first iteration)
2. Push additional commits (subsequent iterations)
3. Monitor CI and fix failures (each iteration)
4. Merge when all criteria pass (final iteration)

### With code-review

The `code-review` skill provides the detailed review checklist. This skill provides the GitHub mechanics for submitting that review.

## Quick Reference

```bash
# Full workflow in one sequence
git fetch origin
git checkout -b feat/my-feature origin/main
# ... make changes ...
git add -p && git commit -m "feat(scope): description"
git push -u origin feat/my-feature
gh pr create --title "feat(scope): description" --body "## Summary\n..."
gh pr checks --watch
gh pr merge --squash --delete-branch
```
