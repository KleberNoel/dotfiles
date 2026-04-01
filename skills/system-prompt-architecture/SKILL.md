---
name: system-prompt-architecture
description: "Layered system prompt construction for AI agents: static identity, capabilities, tool descriptions, project config, dynamic context. Covers cache stability boundaries, CLAUDE.md/AGENTS.md discovery via directory walk, prompt size budgeting, and section memoization. Use when building agent systems or optimizing prompt construction."
license: MIT
metadata:
  pattern: system-prompt-architecture
  sources: code-agents, claude-code
---

# System Prompt Architecture: Layered Prompt Construction

The system prompt is the agent's DNA — it defines identity, capabilities, rules, and context. This skill covers how to construct it from ordered layers, optimize for API caching, and manage its size budget.

## The Layer Model

System prompts are assembled from **sections** in a fixed order. Static sections come first (for cache stability), dynamic sections follow.

```
┌─────────────────────────────────────┐
│  STATIC LAYERS (cache-stable)       │  ← Rarely change. API can cache this prefix.
│                                     │
│  1. intro        — Identity/role    │
│  2. system       — Core rules       │
│  3. tasks        — Task management  │
│  4. actions      — Workflow patterns │
│  5. tools        — Tool usage rules │
│  6. tone         — Style guidance   │
│  7. output       — Format rules     │
├─ ─ CACHE BOUNDARY ─ ─ ─ ─ ─ ─ ─ ─ ┤  ← __SYSTEM_PROMPT_DYNAMIC_BOUNDARY__
│  DYNAMIC LAYERS (change per session)│
│                                     │
│  8.  session_guidance               │
│  9.  memory                         │
│  10. env_info                       │
│  11. language                       │
│  12. custom_instructions            │
│  13. user_instructions              │
│  14. project_instructions           │
│  15. claude_md                      │
│  16. hooks_info                     │
│  17. mcp_instructions               │
│  18. agent_instructions             │
│  19. coordinator_instructions       │
└─────────────────────────────────────┘
```

### Why Order Matters

1. **Cache stability** — API providers cache prompt prefixes. If the first 80% of your system prompt is identical across requests, only the last 20% costs full processing. Put stable content first.
2. **Attention pattern** — Models pay strongest attention to the beginning and end of the system prompt. Put identity and critical rules at the start, session-specific context at the end.
3. **Override semantics** — Later sections can override earlier ones. Project-level instructions override global defaults. User instructions override project instructions.

## Static Sections (1-7)

These sections are the same across all sessions for a given agent version. They change only on agent upgrade.

### 1. Intro — Identity and Role

```markdown
You are [Agent Name], an AI assistant specialized in software engineering.
You help users with coding tasks including writing, debugging, reviewing,
and refactoring code across multiple languages and frameworks.
```

**Rules:**
- Keep to 2-3 sentences
- State what the agent IS, not what it does (capabilities go in section 2)
- No version numbers (changes would break cache)

### 2. System — Core Behavioral Rules

```markdown
## Core Rules
- Always read files before editing them
- Never guess file contents — use tools to verify
- Prefer editing existing files over creating new ones
- When uncertain, ask the user rather than guessing
- Never execute destructive operations without confirmation
```

**Rules:**
- These are the NON-NEGOTIABLE rules
- Keep under 20 rules — the model won't reliably follow 50 rules
- Phrase as imperatives: "Always...", "Never...", "Prefer..."

### 3. Tasks — Task Management Guidance

How the agent should approach multi-step work: planning, breaking down tasks, tracking progress, reporting status.

### 4. Actions — Workflow Patterns

Common workflows the agent should know: "when asked to fix a bug, first reproduce, then diagnose, then fix, then verify." Defines behavioral patterns without referencing specific tools.

### 5. Tools — Tool Usage Instructions

General guidance on tool use: prefer specialized tools over bash, read before write, use parallel tool calls when independent. **Not** individual tool descriptions (those are in the API's `tools` parameter).

### 6. Tone — Communication Style

```markdown
- Be concise and direct
- Use technical language appropriate to the user's level
- No unnecessary filler or praise
- Disagree when technically warranted
```

### 7. Output — Formatting Rules

Markdown formatting preferences, code block conventions, response length guidance.

## The Cache Boundary

Between static and dynamic sections, insert a boundary marker:

```
__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__
```

Everything **above** this marker is eligible for API prefix caching. Everything below changes per session and breaks the cache.

### Cache Economics

```
Prompt: 10,000 tokens total
  Static (cached):  7,000 tokens → charged at ~10% of normal rate
  Dynamic:          3,000 tokens → charged at full rate
  
vs. no caching:    10,000 tokens → all at full rate

Savings: ~60% on prompt token costs
```

**Optimization: maximize the static portion.** Move anything that doesn't change per-session above the boundary.

## Dynamic Sections (8-19)

These change based on session, project, user, and environment.

### 8. Session Guidance

Session-specific instructions: current mode (plan vs build), active feature flags, session-level overrides.

### 9. Memory

Injected memories from the memory directory system (see `memory-directory` skill). Selected based on relevance to the current conversation.

### 10. Environment Info

```markdown
Working directory: /home/user/project
Platform: linux
Shell: bash
Date: 2026-04-01
Git branch: feat/user-auth
```

### 11. Language

User's preferred language for responses (detected or configured).

### 12-13. Custom and User Instructions

Global user preferences from `~/.claude/settings.json` or equivalent:
```json
{
  "customInstructions": "Always use TypeScript strict mode. Prefer functional patterns."
}
```

### 14. Project Instructions

From `.github/copilot-instructions.md`, `.cursorrules`, or similar project-level config.

### 15. CLAUDE.md / AGENTS.md — Project Config Discovery

This is the most important dynamic section. It injects project-specific conventions, commands, and context.

#### Discovery Algorithm

```
function discover_project_config(working_dir):
    configs = []
    
    # Walk from working_dir to filesystem root
    dir = working_dir
    while dir != "/":
        for filename in ["CLAUDE.md", "AGENTS.md"]:
            path = join(dir, filename)
            if exists(path):
                configs.append(read(path))
        dir = parent(dir)
    
    # Also check user-level
    user_config = join(HOME, ".claude/CLAUDE.md")
    if exists(user_config):
        configs.insert(0, read(user_config))  # Root-most first
    
    # Merge order: root-most first, CWD-most last
    # On conflict, closest to CWD wins
    return merge(configs)
```

#### What Goes in CLAUDE.md

```markdown
# Project: my-app

## Build & Test
- `npm run build` — TypeScript compilation
- `npm test` — Jest test suite
- `npm run lint` — ESLint + Prettier

## Architecture
- Express.js backend in src/server/
- React frontend in src/client/
- PostgreSQL database, migrations in src/db/migrations/

## Conventions
- Use camelCase for variables, PascalCase for types
- All API endpoints return { data, error } shape
- Tests live next to source: foo.ts → foo.test.ts

## Known Gotchas
- The Redis connection requires REDIS_URL env var
- Don't modify src/generated/ — these are auto-generated from protobuf
```

#### Rules for CLAUDE.md

- **Under 500 lines** — agents read this every session
- **Commands must be copy-pasteable** — no placeholders without explanation
- **Update when you discover patterns** — but don't duplicate README content
- **Never store secrets** — not even masked ones

### 16. Hooks Info

Description of active hooks so the model knows its tools may be intercepted:
```markdown
Active hooks:
- PreToolUse on "bash": Blocked if command contains "rm -rf /"
- PostToolUse on "write": Runs prettier on written files
```

### 17. MCP Instructions

Instructions from connected MCP servers describing their tools and usage patterns.

### 18-19. Agent and Coordinator Instructions

Special instructions when running as a sub-agent or coordinator (see `agent-coordinator` skill).

## Section Memoization

Computing dynamic sections can be expensive (file reads, git commands, API calls). Use memoization:

```
cache = {}

function systemPromptSection(name, compute_fn):
    if name not in cache:
        cache[name] = compute_fn()
    return cache[name]

# For sections that MUST be fresh every time (breaks caching):
function uncachedSystemPromptSection(name, compute_fn):
    return compute_fn()  # No cache, recomputed every call
```

**Rules:**
- Cache static sections indefinitely (they never change within a session)
- Cache env_info for the duration of the session
- Never cache memory or session_guidance (changes between turns)
- Invalidate claude_md cache when the file is modified (watch mtime)

## Prompt Size Budget

The system prompt competes with conversation history for context window space:

```
PROMPT_BUDGET_FRACTION = 0.25  # System prompt should use ≤25% of context

For a 200K context window:
  System prompt budget: 50,000 tokens (~37,500 words)
  Conversation budget:  150,000 tokens
```

### When the Prompt Is Too Large

If the assembled system prompt exceeds the budget:

```
Priority order for truncation (drop LAST first):
1. coordinator_instructions  (drop if not in coordinator mode)
2. agent_instructions        (drop if not a sub-agent)
3. mcp_instructions          (summarize, drop details)
4. hooks_info                (summarize)
5. project_instructions      (truncate to first 100 lines)
6. claude_md                 (truncate to first 200 lines)
7. memory                    (reduce to top-3 most relevant)

NEVER truncate:
- intro (identity)
- system (core rules)
- tools (tool usage guidance)
```

## Assembly Algorithm

```
function assemble_system_prompt(config, session):
    sections = []
    
    # Static sections (ordered, cache-stable)
    sections.append(section("intro", build_intro))
    sections.append(section("system", build_system_rules))
    sections.append(section("tasks", build_task_guidance))
    sections.append(section("actions", build_action_patterns))
    sections.append(section("tools", build_tool_guidance))
    sections.append(section("tone", build_tone))
    sections.append(section("output", build_output_rules))
    
    # Cache boundary
    sections.append("__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__")
    
    # Dynamic sections (ordered, session-specific)
    sections.append(uncached("session", build_session_guidance))
    sections.append(uncached("memory", build_memory_injection))
    sections.append(section("env", build_env_info))
    sections.append(section("lang", build_language))
    sections.append(section("custom", build_custom_instructions))
    sections.append(section("user", build_user_instructions))
    sections.append(section("project", build_project_instructions))
    sections.append(section("claude_md", build_claude_md))
    sections.append(section("hooks", build_hooks_info))
    sections.append(section("mcp", build_mcp_instructions))
    
    if session.is_sub_agent:
        sections.append(section("agent", build_agent_instructions))
    if session.is_coordinator:
        sections.append(section("coordinator", build_coordinator_instructions))
    
    # Budget check
    prompt = join(sections)
    if token_count(prompt) > PROMPT_BUDGET:
        prompt = truncate_by_priority(prompt)
    
    return prompt
```

## Integration Points

### With context-management
The system prompt is re-injected after every compaction. Compaction summaries sit in the conversation, not the system prompt.

### With memory-directory
Memory injection at section 9 uses the relevance selection algorithm from the `memory-directory` skill.

### With hooks-lifecycle
Hooks info at section 16 describes active hooks so the model can anticipate tool interception.

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| Putting dynamic content in static sections | Breaks API cache on every request | Respect the cache boundary |
| 50+ rules in the system section | Model can't reliably follow them all | Prioritize to top 15-20 rules |
| Duplicating tool descriptions in prompt | Wastes tokens (already in API tools param) | Reference tools, don't describe them |
| No CLAUDE.md | Agent rediscovers project conventions every session | Create and maintain CLAUDE.md |
| CLAUDE.md over 500 lines | Wastes token budget, dilutes important info | Keep focused, link to docs for details |
| Never invalidating section cache | Stale env info, stale hooks | Invalidate on file change or session event |
