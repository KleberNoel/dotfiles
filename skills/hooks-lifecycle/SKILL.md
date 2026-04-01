---
name: hooks-lifecycle
description: "Event-driven agent extension via hooks: intercept, modify, or block tool execution without changing the tools themselves. Covers 4 hook types (PreToolUse, PostToolUse, Notification, Stop), pattern matching, hook configuration format, and the stdin/stdout protocol. Use when building extensible agent systems or adding per-project customization."
license: MIT
metadata:
  pattern: hooks-lifecycle
  sources: code-agents, claude-code
---

# Hooks Lifecycle: Event-Driven Agent Extension

Hooks let you intercept and modify agent behavior without changing tools or the core loop. They are the extension mechanism that makes agents customizable per-project, per-user, and per-workflow.

## Why Hooks

Without hooks, customizing agent behavior requires modifying tool code or the agent runtime. Hooks provide a clean separation:

- **Tools** define WHAT operations are available
- **The query loop** defines HOW operations are executed
- **Hooks** define WHEN and WHETHER operations are allowed, and can transform inputs/outputs

## Hook Types

### PreToolUse

Fires **before** a tool executes. Can inspect the tool name and input, then allow, block, or modify.

```
Event:   PreToolUse
Timing:  After model requests tool_use, before tool.execute()
Context: tool_name, tool_input
Can:     Allow, Block (with reason), Modify (tool_input)
```

**Use cases:**
- Block dangerous commands (`rm -rf /`, `DROP TABLE`)
- Enforce read-before-write (block writes to unread files)
- Add safety constraints (inject `--dry-run` flag)
- Log all tool invocations for audit

### PostToolUse

Fires **after** a tool executes. Can inspect the result and modify it before the model sees it.

```
Event:   PostToolUse
Timing:  After tool.execute() returns, before result sent to model
Context: tool_name, tool_input, tool_output, is_error
Can:     Allow, Modify (tool_output)
```

**Use cases:**
- Run formatter on written files (prettier, black, gofmt)
- Redact sensitive data from tool output
- Add context to error messages
- Trigger side effects (notifications, metrics)

### Notification

Fires on informational events. Non-blocking — cannot modify behavior.

```
Event:   Notification
Timing:  Various points in the agent lifecycle
Context: event type, message, metadata
Can:     Observe only (no block/modify)
```

**Use cases:**
- Send Slack/Discord notifications on task completion
- Update external dashboards
- Trigger CI pipelines
- Write audit logs

### Stop

Fires when the agent is about to stop (end_turn, user cancellation, error).

```
Event:   Stop
Timing:  After query loop exits, before control returns to user
Context: stop_reason, final_message, session_summary
Can:     Allow, Modify (add cleanup actions)
```

**Use cases:**
- Auto-commit work in progress before stopping
- Write progress summary to file
- Clean up temporary resources
- Send completion notification

## Hook Configuration

Hooks are configured per-project in a hooks config file (`.claude/hooks.json`, `.opencode/hooks.json`, or equivalent).

### Configuration Format

```json
{
  "hooks": [
    {
      "event": "PreToolUse",
      "tool_filter": "bash",
      "command": "/path/to/scripts/validate-bash.sh",
      "blocking": true
    },
    {
      "event": "PostToolUse",
      "tool_filter": "write",
      "command": "prettier --write $TOOL_INPUT_PATH",
      "blocking": true
    },
    {
      "event": "Notification",
      "tool_filter": null,
      "command": "notify-send 'Agent' '$EVENT_MESSAGE'",
      "blocking": false
    },
    {
      "event": "Stop",
      "tool_filter": null,
      "command": "/path/to/scripts/auto-save.sh",
      "blocking": true
    }
  ]
}
```

### Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `event` | string | yes | One of: PreToolUse, PostToolUse, Notification, Stop |
| `tool_filter` | string? | no | Glob pattern matching tool names. `null` = all tools. |
| `command` | string | yes | Shell command to execute |
| `blocking` | bool | yes | If true, hook can block/modify. If false, fire-and-forget. |

### Tool Filter Patterns

```
"bash"          # Exact match — only the bash tool
"write*"        # Glob — write, writeFile, writeToFile
"*file*"        # Glob — readFile, writeFile, deleteFile
null            # No filter — matches all tools
```

## The Hook Protocol

Hooks communicate with the agent via **stdin** (input) and **stdout/stderr** (output).

### Input (stdin)

The agent sends a JSON `HookContext` object on stdin:

```json
{
  "event": "PreToolUse",
  "tool_name": "bash",
  "tool_input": {
    "command": "rm -rf /tmp/build"
  },
  "tool_output": null,
  "is_error": false,
  "session_id": "sess_abc123"
}
```

For PostToolUse, `tool_output` is populated:

```json
{
  "event": "PostToolUse",
  "tool_name": "write",
  "tool_input": {
    "path": "src/main.ts",
    "content": "..."
  },
  "tool_output": "File written successfully",
  "is_error": false,
  "session_id": "sess_abc123"
}
```

### Output (stdout)

For **blocking** hooks, stdout determines the outcome:

```
# Allow — empty stdout or no output
(empty)

# Block — exit with non-zero code, reason on stderr
exit 1
stderr: "Blocked: command contains dangerous pattern 'rm -rf /'"

# Modify — valid JSON on stdout
stdout: {"tool_input": {"command": "rm -rf /tmp/build --dry-run"}}
```

### Outcome Resolution

```
function resolve_hook_outcome(exit_code, stdout, stderr):
    if exit_code != 0:
        return Blocked(stderr)
    
    if stdout is valid JSON:
        return Modified(parse(stdout))
    
    return Allowed
```

## Hook Execution Algorithm

```
function run_hooks(event, tool_name, tool_input, tool_output):
    outcomes = []
    
    for hook in config.hooks:
        # Filter by event type
        if hook.event != event:
            continue
        
        # Filter by tool name
        if hook.tool_filter and not glob_match(hook.tool_filter, tool_name):
            continue
        
        # Build context
        context = HookContext(
            event=event,
            tool_name=tool_name,
            tool_input=tool_input,
            tool_output=tool_output,
            session_id=session.id
        )
        
        # Execute hook
        if hook.blocking:
            result = execute_blocking(hook.command, context)
            outcomes.append(result)
            
            # Short-circuit on Block
            if result == Blocked:
                return result
        else:
            # Fire and forget
            spawn_async(hook.command, context)
    
    # Merge modifications (last write wins)
    for outcome in outcomes:
        if outcome == Modified(value):
            return outcome
    
    return Allowed
```

### Execution Rules

1. **Blocking hooks run sequentially** — order matters, first Block wins
2. **Non-blocking hooks run in parallel** — fire-and-forget, no waiting
3. **Hook timeout: 10 seconds** — blocking hooks that exceed this are killed and treated as Allowed
4. **Hook crash = Allowed** — a crashing hook should never block the agent
5. **Multiple modifications** — if two blocking hooks both return Modified, the last one wins

## Integration in the Query Loop

```
// In the query loop (see query-loop skill):

for tool_call in response.tool_calls:
    // PreToolUse hooks
    pre_result = run_hooks(PreToolUse, tool_call.name, tool_call.input, null)
    
    match pre_result:
        Blocked(reason):
            conversation.append_tool_result(tool_call.id, ToolResult(
                content: "Tool blocked by hook: " + reason,
                is_error: true
            ))
            continue  // Skip this tool, process next
        
        Modified(new_input):
            tool_call.input = new_input  // Use modified input
        
        Allowed:
            pass  // Proceed as-is
    
    // Execute tool
    tool_result = execute_tool(tool_call.name, tool_call.input)
    
    // PostToolUse hooks
    post_result = run_hooks(PostToolUse, tool_call.name, tool_call.input, tool_result)
    
    match post_result:
        Modified(new_output):
            tool_result = new_output
        _:
            pass
    
    conversation.append_tool_result(tool_call.id, tool_result)
```

## Common Hook Recipes

### 1. Block Dangerous Bash Commands

```bash
#!/bin/bash
# hooks/block-dangerous.sh
INPUT=$(cat)  # Read HookContext from stdin
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

DANGEROUS_PATTERNS=(
    "rm -rf /"
    "rm -rf ~"
    "DROP TABLE"
    "DROP DATABASE"
    ":(){ :|:& };:"
    "> /dev/sda"
    "mkfs."
    "dd if="
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    if [[ "$COMMAND" == *"$pattern"* ]]; then
        echo "Blocked: command contains dangerous pattern '$pattern'" >&2
        exit 1
    fi
done
# Exit 0 = Allowed
```

### 2. Auto-Format Written Files

```bash
#!/bin/bash
# hooks/auto-format.sh
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // .tool_input.filePath')

case "$FILE_PATH" in
    *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md)
        prettier --write "$FILE_PATH" 2>/dev/null ;;
    *.py)
        black "$FILE_PATH" 2>/dev/null && ruff check --fix "$FILE_PATH" 2>/dev/null ;;
    *.go)
        gofmt -w "$FILE_PATH" 2>/dev/null ;;
    *.rs)
        rustfmt "$FILE_PATH" 2>/dev/null ;;
esac
# Always allow — formatting is best-effort
```

### 3. Notify on Task Completion

```bash
#!/bin/bash
# hooks/notify-complete.sh
INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | jq -r '.tool_output // "Task completed"' | head -c 200)

# Desktop notification
notify-send "Agent" "$MESSAGE" 2>/dev/null

# Slack webhook (optional)
if [ -n "$SLACK_WEBHOOK_URL" ]; then
    curl -s -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "{\"text\": \"Agent: $MESSAGE\"}" >/dev/null
fi
```

### 4. Enforce Read-Before-Write

```bash
#!/bin/bash
# hooks/read-before-write.sh
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // .tool_input.filePath')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
READ_LOG="/tmp/agent-reads-${SESSION_ID}.log"

# Check if file was read in this session
if [ -f "$FILE_PATH" ] && ! grep -qF "$FILE_PATH" "$READ_LOG" 2>/dev/null; then
    echo "Blocked: must read '$FILE_PATH' before writing to it" >&2
    exit 1
fi
```

## Skills Infrastructure

Hooks and skills are closely related — skills define what an agent KNOWS, while hooks define how it's CONSTRAINED.

### Skill Discovery

Skills are discovered from multiple locations (searched in order):

```
1. .opencode/skills/         (project-local)
2. ~/.config/opencode/skills/ (user-global)
3. .claude/skills/           (project-local)
4. ~/.claude/skills/         (user-global)
5. .agents/skills/           (project-local)
6. ~/.agents/skills/         (user-global)
```

### Skill Format

Each skill is a directory containing a `SKILL.md` file with YAML frontmatter:

```yaml
---
name: skill-name          # lowercase, hyphens, 1-64 chars
description: "..."        # When to activate this skill
license: MIT
metadata:
  key: value
---

# Skill content (markdown)
```

### Skill Injection

Skills are injected into the system prompt based on relevance to the current task. The agent framework:

1. Scans all skill directories
2. Parses frontmatter for `name` and `description`
3. Selects relevant skills based on the user's query
4. Injects selected skill content into a dynamic prompt section

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| Blocking hooks with no timeout | Hook hangs → agent hangs | 10-second timeout, kill and allow |
| Hook crashes block the agent | Unstable extension kills productivity | Crash = Allowed, log the error |
| Modifying tool input silently | Agent and user can't debug mysterious behavior | Log modifications visibly |
| Too many blocking hooks | Each adds latency to every tool call | Keep blocking hooks minimal, use async for logging |
| Hooks that call the agent API | Recursive loop risk | Hooks should be simple, local scripts |
| No tool_filter (matching everything) | Hook runs on every single tool call | Filter to specific tools that need interception |
