---
name: codebase-onboard
description: "Systematically explore a codebase and generate an AGENTS.md file. Discovers project structure, build commands, test commands, conventions, and dependencies. Use when entering a new project, generating AGENTS.md, or orienting an agent to an unfamiliar repo."
license: MIT
metadata:
  pattern: codebase-discovery
  origin: opencode /init, badlogic/pi-mono, nousresearch/hermes-agent
---

# Codebase Onboard: Systematic Project Discovery

Explore an unfamiliar codebase and produce an AGENTS.md that orients future agents (and humans) to work in it effectively.

## When To Use This

- First time entering a new repository
- Generating or updating an AGENTS.md file
- Orienting a new agent or developer to a project
- After major structural refactors

## Discovery Protocol

### Phase 1: Top-Level Scan

Read these files if they exist (in parallel where possible):

```
README.md           # Purpose, setup, architecture overview
AGENTS.md           # Existing agent instructions
CONTRIBUTING.md     # Development workflow, PR process
package.json        # Node: scripts, dependencies, monorepo structure
pyproject.toml      # Python: dependencies, build system, scripts
Cargo.toml          # Rust: workspace, dependencies
go.mod              # Go: module name, dependencies
Makefile             # Build/test/lint targets
docker-compose.yml  # Service architecture
.github/workflows/  # CI pipeline (what gets checked)
```

### Phase 2: Structure Map

Identify the project layout pattern:

| Pattern | Indicator | Structure |
|---------|-----------|-----------|
| Monorepo | `packages/`, `workspaces` in package.json | Multiple packages with shared config |
| Single package | `src/` at root | One module with src/test split |
| Python project | `pyproject.toml`, `setup.py` | Module directories, tests/ |
| Rust workspace | `[workspace]` in Cargo.toml | Member crates |

List directories one level deep. Note which are packages, which are config, which are generated.

### Phase 3: Build & Test Commands

Find the canonical commands. Check `package.json` scripts, `Makefile` targets, `pyproject.toml` scripts, CI workflows:

```
Build:     npm run build / cargo build / make build
Test:      npm test / pytest / cargo test / make test
Lint:      npm run check / ruff check / cargo clippy
Format:    npm run format / black . / cargo fmt
Typecheck: tsc --noEmit / mypy / pyright
```

### Phase 4: Conventions

Scan a few source files to identify:

- **Language/runtime**: TypeScript + Bun? Python 3.12? Rust nightly?
- **Style**: Tabs or spaces? Semicolons? Trailing commas?
- **Imports**: Absolute or relative? Barrel files?
- **Testing**: Framework (vitest, pytest, cargo test)? Test location (colocated or `tests/`)?
- **Formatting**: Enforced tool (prettier, black, rustfmt)?
- **Commit style**: Conventional commits? Signed?

### Phase 5: Key Patterns

Identify patterns that agents must follow:

- State management approach
- Error handling convention
- API/route registration pattern
- Database access pattern
- Environment variable handling

## AGENTS.md Template

```markdown
# Development Rules

## First Message
If no concrete task given, read README.md, then ask which area to work on.
[If monorepo: list packages with one-line descriptions]

## Commands
- Build: `[command]`
- Test: `[command]`
- Lint/Check: `[command]`
- Format: `[command]`
- Run specific test: `[command] path/to/test`

[Note any commands that should NEVER be run, e.g. "NEVER run npm run dev"]

## Project Structure
```
[top-level directory tree with one-line descriptions]
```

## Code Quality
- [Language-specific rules: no `any` types, no inline imports, etc.]
- [Import conventions]
- [Error handling pattern]

## Key Patterns
- [Pattern 1: how X works in this codebase]
- [Pattern 2: how Y is structured]

## Testing
- [Framework and how to run tests]
- [Where tests live]
- [What needs API keys / env vars]

## Git Rules
- NEVER use `git add -A` -- stage specific files only
- [Commit message format for this project]
- [Branch naming convention]
- [PR workflow]

## Known Pitfalls
- [Gotcha 1]
- [Gotcha 2]
```

## Per-Directory AGENTS.md

For monorepos or large codebases, place additional AGENTS.md files in subdirectories for module-specific rules:

```
AGENTS.md                    # Root: project-wide rules
packages/api/AGENTS.md       # API-specific patterns
packages/ui/AGENTS.md        # Frontend-specific rules
tests/AGENTS.md              # Testing conventions
```

Keep them short and focused. Only document what's specific to that directory.

## Updating AGENTS.md

When you discover something during implementation that future agents need to know:

**Add it if:**
- It's a general pattern (e.g., "use `sql<number>` for aggregations")
- It's a gotcha (e.g., "must update X when changing Y")
- It's a non-obvious dependency between files

**Don't add:**
- Story-specific implementation details
- Temporary debugging notes
- Information already in README.md

## Integration With Other Skills

- **ralph-loop**: Each iteration reads AGENTS.md before starting work
- **guardrails**: Persistent patterns graduate from guardrails.md into AGENTS.md
- **prd**: AGENTS.md conventions inform how stories are written
- **git-checkpoint**: AGENTS.md documents the project's commit/PR workflow
