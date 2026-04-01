---
name: memory-directory
description: "Structured agent memory with relevance-based retrieval: 4 memory types (user, feedback, project, reference), YAML-frontmatter markdown files, relevance scoring via sidecar model, freshness decay, deduplication, and injection budgets. Goes beyond session state into persistent cross-session knowledge. Use when building agents that need to remember across sessions."
license: MIT
metadata:
  pattern: memory-directory
  sources: code-agents, claude-code
---

# Memory Directory: Persistent Agent Memory with Relevance Retrieval

The context window is short-term memory. The memory directory is long-term memory — it persists across sessions and uses relevance scoring to inject only what matters for the current task.

## Core Insight

Memory isn't just storage — it's **retrieval**. An agent that remembers everything but retrieves nothing useful is worse than one with no memory at all. The memory directory system stores structured memories and selects the most relevant ones to inject into each session.

## Architecture

```
~/.claude/projects/<project-hash>/memory/
  MEMORY.md                    # Entrypoint — always loaded
  user-prefers-pytest.md       # User preference
  api-uses-bearer-auth.md      # Project fact
  fix-circular-imports.md      # Learned pattern
  cors-config-gotcha.md        # Error correction
```

Each memory is a standalone markdown file with YAML frontmatter. The system scans all files, scores them for relevance, and injects the top N into the system prompt.

## Memory Types

### 1. User Preferences (`user`)

Things the user has stated about how they like to work:

```yaml
---
name: prefers-pytest
description: "User prefers pytest over unittest for Python testing"
type: user
---
When writing Python tests, always use pytest. User dislikes unittest's verbose
class-based style. Use fixtures over setup/teardown. Use parametrize for
data-driven tests.
```

### 2. Feedback / Corrections (`feedback`)

Explicit corrections from the user about agent mistakes:

```yaml
---
name: dont-use-any-type
description: "User corrected: never use 'any' type in TypeScript"
type: feedback
---
The user explicitly said: "Don't use `any` type. Always define proper
interfaces or use `unknown` with type guards." This was in response to
the agent typing an API response as `any`.
```

### 3. Project Knowledge (`project`)

Facts about the specific project that help the agent work effectively:

```yaml
---
name: api-auth-bearer
description: "All API endpoints require Bearer token auth"
type: project
---
The REST API uses Bearer token authentication. Every request to /api/*
must include `Authorization: Bearer <token>` header. Tokens are JWTs
with 1-hour expiry. Refresh via POST /auth/refresh.

The token service is at src/services/auth/token-service.ts.
```

### 4. Reference Material (`reference`)

Snippets of documentation, patterns, or examples that are frequently needed:

```yaml
---
name: database-migration-pattern
description: "How to create safe database migrations in this project"
type: reference
---
## Creating Migrations

1. Generate: `npm run migrate:create <name>`
2. Edit the generated file in src/db/migrations/
3. Always include both `up()` and `down()` methods
4. Never drop columns in the same deploy as code changes
5. Use expand-migrate-contract pattern for breaking changes

Example:
```sql
-- Up
ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT FALSE;

-- Down
ALTER TABLE users DROP COLUMN email_verified;
```

## File Format

### Frontmatter (Required)

```yaml
---
name: "descriptive-kebab-case-name"      # Required, unique within directory
description: "one-line summary"            # Required, used for relevance matching
type: "user|feedback|project|reference"    # Required, one of 4 types
---
```

### Constraints

```
FRONTMATTER_MAX_LINES = 30       # Frontmatter section can't exceed 30 lines
MAX_MEMORY_FILES      = 200      # Hard cap on total memory files
MAX_FILE_SIZE         = 10_000   # ~10KB per memory file
```

### Body (Markdown)

The body contains the actual knowledge. Keep it focused and actionable:

- **Good**: Specific, actionable, includes file paths and commands
- **Bad**: Vague, opinion-based, duplicates information already in CLAUDE.md

## The Entrypoint: MEMORY.md

Every memory directory has a `MEMORY.md` file that is **always loaded** (not subject to relevance selection):

```markdown
# Project Memory

## Key Facts
- This is a Node.js/TypeScript monorepo using pnpm workspaces
- Database: PostgreSQL 15 with Prisma ORM
- Auth: JWT-based, see memory file `api-auth-bearer.md`

## Active Concerns
- Migration to ESM modules in progress (don't add new CommonJS)
- Performance optimization needed for /api/search endpoint
```

### Entrypoint Constraints

```
MAX_ENTRYPOINT_LINES = 200
MAX_ENTRYPOINT_BYTES = 25_000   # ~25KB
```

MEMORY.md is your curated index. It should summarize the most important facts and reference specific memory files for details.

## Relevance Selection Algorithm

When a new session starts (or a new user message arrives), the system selects which memories to inject:

### Step 1: Scan

```
function scan_memories(memory_dir):
    files = list_files(memory_dir, "*.md")
    files = exclude("MEMORY.md")           # Entrypoint loaded separately
    files = sort_by_mtime(files, newest_first)
    files = truncate(files, MAX_MEMORY_FILES)
    
    summaries = []
    for file in files:
        frontmatter = parse_yaml_frontmatter(file)
        summaries.append({
            filename: file.name,
            name: frontmatter.name,
            description: frontmatter.description,
            type: frontmatter.type,
            age_days: days_since_modified(file)
        })
    
    return summaries
```

### Step 2: Score via Sidecar Model

Use a fast, cheap model (e.g., Sonnet) in a **sidecar query** — not the main agent model — to evaluate relevance:

```
function find_relevant_memories(summaries, user_message, already_surfaced):
    # Remove memories already shown this session
    candidates = [s for s in summaries if s.filename not in already_surfaced]
    
    # Build selection prompt
    prompt = f"""
    Given the user's current message and these available memories,
    select up to 5 that are most relevant to the current task.
    
    User message: {user_message}
    
    Available memories:
    {format_summaries(candidates)}
    
    Return a JSON array of filenames, most relevant first.
    """
    
    # Sidecar query with strict token limit
    response = sidecar_query(
        model="sonnet",
        prompt=prompt,
        max_tokens=256,
        response_format="json"
    )
    
    selected = parse_json(response)  # ["api-auth-bearer.md", "fix-circular-imports.md"]
    return selected[:5]  # Hard cap at 5
```

### Step 3: Inject

```
function inject_memories(selected_files, memory_dir):
    injection = ""
    
    for filename in selected_files:
        content = read(join(memory_dir, filename))
        age = days_since_modified(join(memory_dir, filename))
        
        injection += format_memory(content)
        
        # Freshness warning for old memories
        if age > 30:
            injection += f"\n<system-reminder>This memory is {age} days old. Verify before relying on it.</system-reminder>"
    
    return injection
```

### Deduplication

Track which memories have been surfaced this session to avoid repetition:

```
session.already_surfaced = set()

# After injecting memories:
session.already_surfaced.update(selected_files)

# On next selection:
candidates = [m for m in all_memories if m not in session.already_surfaced]
```

## Freshness Decay

Memories degrade in reliability over time. The system applies freshness signals:

```
function freshness_tag(age_days):
    if age_days <= 1:
        return ""  # Fresh, no warning
    elif age_days <= 7:
        return ""  # Recent enough
    elif age_days <= 30:
        return "<system-reminder>Memory is {age_days} days old.</system-reminder>"
    else:
        return "<system-reminder>Memory is {age_days} days old. Verify before relying on it.</system-reminder>"
```

### Auto-Pruning

Memories that haven't been accessed in 90+ days are candidates for pruning. During a dream cycle (see `context-management` skill), old memories are reviewed and either refreshed or deleted.

## Injection Budget

Memories compete with other system prompt sections for token space:

```
MEMORY_INJECTION_BUDGET = 4000 tokens  # Max tokens for memory injection

function budget_memories(selected_files):
    injected = []
    tokens_used = 0
    
    for file in selected_files:
        content = read(file)
        file_tokens = count_tokens(content)
        
        if tokens_used + file_tokens > MEMORY_INJECTION_BUDGET:
            break  # Budget exhausted
        
        injected.append(content)
        tokens_used += file_tokens
    
    return injected
```

## Creating and Updating Memories

### When to Create a Memory

Create a new memory when:
1. The user explicitly states a preference ("I always want to use tabs, not spaces")
2. The user corrects the agent ("No, that's wrong — the API uses v2, not v1")
3. A project pattern is discovered that isn't in CLAUDE.md ("The deploy script needs AWS_REGION set")
4. A complex debugging session reveals a non-obvious gotcha

### When NOT to Create a Memory

- Trivial or one-time facts
- Information already in CLAUDE.md or README
- Opinions that may change (use only for explicit preferences)
- Secrets, tokens, or credentials (**never**)

### Memory Creation Workflow

```
1. Identify knowledge worth persisting
2. Classify type (user/feedback/project/reference)
3. Write concise frontmatter (name + description)
4. Write focused body (under 50 lines ideally)
5. Save to memory directory
6. Update MEMORY.md index if the memory is important enough
```

## Team Memory

For shared team knowledge (conventions everyone should follow):

```
<memory_dir>/team/
  code-style-guide.md
  deploy-process.md
  incident-response.md
```

### Team Memory Safety

- Path traversal protection: sanitize team directory names
- Team memories are read-only for individual agents
- Updated via explicit team workflows (PR to shared config repo)

## Integration Points

### With system-prompt-architecture
Memories are injected into the `memory` dynamic section (section 9) of the system prompt.

### With context-management
The dream pattern from `context-management` runs consolidation on the memory directory — deduplicating, pruning, and refreshing stale entries.

### With guardrails
Feedback-type memories often encode the same lessons as guardrail signs. The difference: guardrails are session-scoped rules, memories are cross-session knowledge.

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| Storing everything | 200 files of noise, retrieval degrades | Only persist confirmed, reusable knowledge |
| No frontmatter descriptions | Relevance scoring can't work | Write clear one-line descriptions |
| Huge memory files (500+ lines) | Blows injection budget on one memory | Keep files under 50 lines, split if needed |
| Never pruning | Stale memories mislead the agent | Prune >90 day untouched memories |
| Injecting all memories | Wastes token budget | Relevance selection, max 5 per turn |
| Storing secrets | Credential leak | Never. Use vault or env vars. |
