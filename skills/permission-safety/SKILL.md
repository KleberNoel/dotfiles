---
name: permission-safety
description: "Permission model, read-before-write enforcement, protected files, path safety, and risk classification for agent tool use. Prevents agents from overwriting files they haven't read, modifying system config without approval, or executing dangerous commands. Use when building agent tools, defining permission boundaries, or hardening agent safety."
license: MIT
metadata:
  pattern: permission-safety
  sources: code-agents, claude-code
---

# Permission Safety: Guarding Agent Tool Use

Agents have real power — file writes, shell execution, network access. This skill defines the safety model that prevents agents from causing harm through careless or unconstrained tool use.

## Permission Levels

Every tool operation has a permission level. These form a strict hierarchy:

```
Level 0: None         — No permissions needed (metadata, help)
Level 1: ReadOnly     — Read files, list directories, search
Level 2: Write        — Create/modify files within the project
Level 3: Execute      — Run shell commands, spawn processes
Level 4: Dangerous    — System config changes, force operations, network writes
```

### Classification Examples

| Operation | Level | Rationale |
|---|---|---|
| Read a file | ReadOnly | No side effects |
| Search codebase | ReadOnly | No side effects |
| List directory | ReadOnly | No side effects |
| Write project file | Write | Modifiable, but scoped to project |
| Create new file | Write | Scoped to project |
| Delete project file | Write | Reversible via git |
| Run tests | Execute | Spawns process, but read-only intent |
| Run build | Execute | Spawns process, may write artifacts |
| Run arbitrary shell | Execute | Unknown side effects |
| Edit `.bashrc` | Dangerous | System-wide impact |
| Edit `.gitconfig` | Dangerous | Affects all repos |
| `git push --force` | Dangerous | Destroys remote history |
| Install system package | Dangerous | Modifies OS state |
| Write to `.env` | Dangerous | May contain/overwrite secrets |

## Read-Before-Write Enforcement

**Core rule: Never write to a file you haven't read in this session.**

This prevents blind overwrites, ensures the agent understands what it's changing, and catches concurrent modifications.

### Implementation

Maintain a `readFileState` cache mapping file paths to their last-known state:

```
readFileState = {
  "src/auth/handler.ts": {
    mtime: 1711929600,      # Unix timestamp when we last read it
    size: 2847,             # File size at read time
    hash: "a1b2c3..."      # Content hash (optional, for extra safety)
  }
}
```

### Before Writing a File

```
function validateWrite(path):
    if path not in readFileState:
        ERROR: "Must read file before editing. Use Read tool first."

    current_mtime = stat(path).mtime
    cached_mtime  = readFileState[path].mtime

    if current_mtime != cached_mtime:
        ERROR: "File modified since last read (concurrent edit detected).
               Re-read the file to see current contents before editing."

    # Safe to proceed with write
    proceed()
    # Update cache after successful write
    readFileState[path].mtime = stat(path).mtime
```

### Special Cases

- **New file creation**: No read required (file doesn't exist yet). But check that the parent directory exists.
- **File deletion**: Read required — you must see what you're deleting.
- **Append-only files** (logs, JSONL): Read not strictly required, but recommended to check format.

## Protected Files

Certain files require elevated permission or explicit user approval before modification.

### System Configuration (Dangerous — always ask)

```
~/.bashrc           ~/.zshrc            ~/.profile
~/.bash_profile     ~/.gitconfig        ~/.ssh/*
~/.gnupg/*          /etc/*              ~/.config/systemd/*
```

### Secrets and Credentials (Dangerous — never write, never commit)

```
.env                .env.local          .env.production
*.pem               *.key               *.crt
credentials.json    service-account.json
~/.aws/credentials  ~/.netrc            ~/.npmrc (if contains token)
```

### Agent Configuration (Write — but warn before overwriting)

```
.claude.json        .mcp.json           CLAUDE.md
AGENTS.md           .cursorrules        .opencode/config.json
```

### Rules

1. **Never write secrets** — If generating config that needs secrets, write a `.env.example` with placeholder values
2. **Never commit secrets** — If a secret file is staged, unstage it and add to `.gitignore`
3. **Warn before overwriting agent config** — These files affect agent behavior globally
4. **Never modify system dotfiles without explicit request** — `.bashrc`, `.gitconfig`, etc.

## Path Safety

Agents receive paths from users, tool outputs, and their own reasoning. All paths must be validated.

### Path Resolution Rules

```
1. Resolve all paths relative to working_dir (project root)
2. Normalize the path (resolve .., remove //, etc.)
3. Verify the resolved path is within the allowed scope
4. Reject paths that escape the project directory (unless explicitly allowed)
```

### Attack Vectors to Defend Against

| Vector | Example | Defense |
|---|---|---|
| Path traversal | `../../etc/passwd` | Resolve and check prefix |
| URL-encoded chars | `..%2F..%2Fetc%2Fpasswd` | Decode before resolving |
| Unicode normalization | `..／etc／passwd` (fullwidth slash) | Normalize unicode first |
| Backslash injection | `..\\..\\etc\\passwd` | Convert `\` to `/` on all platforms |
| Null bytes | `file.txt\x00.jpg` | Strip null bytes |
| Symlink escape | `link -> /etc/passwd` | Check canonical path after resolution |
| Home dir expansion | `~/../../etc/passwd` | Expand `~` then validate |

### Allowed Scope

By default, an agent may access:
```
ALLOWED:
  - working_dir/**          (project files)
  - /tmp/**                 (temp files)
  - ~/.config/opencode/**   (own config)
  - ~/.claude/**            (own config)
  - ~/.agents/**            (own config)

DENIED (without explicit permission):
  - ~/* (other dotfiles)
  - /etc/*
  - /usr/*
  - /var/*
  - Other users' home directories
```

## Risk Classification

Classify each tool invocation by risk level to determine the appropriate permission check.

### LOW Risk (Auto-allow)

- Reading files within project scope
- Searching/grepping within project scope
- Listing directories
- Running read-only git commands (`status`, `log`, `diff`, `branch`)
- Viewing environment variables (non-secret)

### MEDIUM Risk (Allow in permissive mode, ask in default mode)

- Writing/editing project files
- Creating new files within project
- Deleting project files
- Running project-defined commands (`npm test`, `make build`, `pytest`)
- Git commits (with proper validation)

### HIGH Risk (Always ask unless bypass mode)

- Running arbitrary shell commands
- Installing packages (`npm install`, `pip install`, `apt install`)
- Network operations (HTTP requests, API calls)
- Git push operations
- Modifying files outside project scope
- Any operation on protected files

### CRITICAL Risk (Always ask, even in bypass mode — warn loudly)

- `git push --force` to any branch
- Deleting remote branches
- Modifying system configuration
- Writing credentials or secrets
- Operations that cannot be undone

## Permission Modes

Different contexts call for different strictness levels.

### Default Mode

```
ReadOnly:  auto-allow
Write:     ask for first write per file, then auto-allow same file
Execute:   ask every time
Dangerous: ask every time, show warning
```

### AcceptEdits Mode

```
ReadOnly:  auto-allow
Write:     auto-allow within project scope
Execute:   ask for non-project commands
Dangerous: ask every time, show warning
```

### Plan Mode (Read-Only)

```
ReadOnly:  auto-allow
Write:     DENY (hard block, no override)
Execute:   DENY (hard block, no override)
Dangerous: DENY (hard block, no override)
```

### Bypass Mode (Trusted Automation)

```
ReadOnly:  auto-allow
Write:     auto-allow
Execute:   auto-allow
Dangerous: ask + warn (still not auto-allowed)
```

## Practical Rules

These rules should be internalized by every agent:

### The Ten Commandments of Agent Safety

1. **Never write a file you haven't read** — Blind overwrites destroy work
2. **Check mtime before overwriting** — Someone else may have edited it
3. **Never commit secrets** — Check staged files for `.env`, keys, tokens
4. **Validate all paths** — Resolve, normalize, check scope
5. **Never force-push to main** — This is irreversible for the team
6. **Sandbox untrusted commands** — Unknown scripts get timeout + resource limits
7. **Preserve user's config** — Don't "fix" dotfiles without being asked
8. **Fail open for reads, closed for writes** — When in doubt about permissions, read is safe, write is not
9. **Log all write operations** — Every file write and command execution should be traceable
10. **Abort on confusion** — If you're unsure whether an operation is safe, ask the user

### Validation Before Tool Execution

Every tool invocation should pass through this gate:

```
function validateToolUse(tool, input, context):
    level = tool.permissionLevel()

    # Check mode allows this level
    if not context.mode.allows(level):
        return DENY("Operation not permitted in current mode")

    # Path safety check for file operations
    if tool.operatesOnFiles():
        path = resolvePath(input.path, context.working_dir)
        if not isWithinScope(path, context.allowed_paths):
            return DENY("Path outside allowed scope: " + path)
        if isProtectedFile(path):
            return ASK("This file is protected: " + path)

    # Read-before-write check
    if tool.isWriteOperation() and input.path:
        if not hasBeenRead(input.path, context.readFileState):
            return DENY("Must read file before writing")
        if isStale(input.path, context.readFileState):
            return DENY("File changed since last read, re-read first")

    # Risk classification
    risk = classifyRisk(tool, input, context)
    if risk >= CRITICAL:
        return ASK_WITH_WARNING(risk.message)
    if risk >= HIGH and not context.mode.autoAllowHigh():
        return ASK(risk.message)

    return ALLOW
```

## Integration Points

### With git-checkpoint

`git-checkpoint` uses permission-safety for:
- Validating staged files don't contain secrets
- Ensuring `--force` operations are blocked
- Checking that commit hooks aren't bypassed

### With tool-builder

When building new tools, assign the correct `permissionLevel()`:
- File read tool → `ReadOnly`
- File write tool → `Write`
- Shell execution tool → `Execute`
- System config tool → `Dangerous`

### With subagent-dispatch

Sub-agents should inherit the parent's permission mode or a **stricter** one:
- Parent in Default → Sub-agent in Default or Plan
- Parent in AcceptEdits → Sub-agent in AcceptEdits or Default
- Never escalate: sub-agent must not have MORE permissions than parent

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| Writing files without reading first | Blind overwrite destroys work | Always read before edit |
| Trusting user-provided paths | Path traversal attacks | Resolve and validate all paths |
| Auto-allowing shell commands | Untrusted input → RCE | Ask for execution permission |
| Storing secrets in project files | Credential leak via git | Use `.env.example` with placeholders |
| Giving sub-agents full permissions | Blast radius of mistakes | Inherit or restrict, never escalate |
| Skipping mtime checks | Concurrent edits lost | Always check freshness before writing |
