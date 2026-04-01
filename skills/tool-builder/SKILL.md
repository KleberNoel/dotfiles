---
name: tool-builder
description: "Build new agent tools for opencode, hermes-agent, or any MCP-compatible agent framework. Covers the tool definition pattern (schema, execute, permissions), registration, and testing across TypeScript, Python, and Rust implementations."
license: MIT
metadata:
  pattern: tool-definition
  origin: opencode tool.ts, code-agents spec, nousresearch/hermes-agent
---

# Tool Builder: Create New Agent Tools

A meta-skill for building tools that agents can call. Covers three frameworks (opencode/TypeScript, hermes/Python, code-agents/Rust) and the universal MCP approach.

## When To Use This

- You need a new tool that doesn't exist in any agent framework
- You're extending an agent's capabilities for a specific project
- You want to wrap an existing CLI tool, API, or function for agent use
- You're building a custom agent and need to define its toolset

## The Universal Tool Contract

Every tool, in every framework, follows this shape:

```
Tool = {
  name:        string           -- unique identifier
  description: string           -- what the tool does (LLM reads this)
  parameters:  Schema           -- input validation (JSON Schema or Zod)
  execute:     (input) -> output -- the implementation
  permissions: Level            -- what access level is needed
}
```

## OpenCode Tools (TypeScript + Effect)

### File: `packages/opencode/src/tool/your-tool.ts`

```typescript
import { Tool } from "./tool"
import * as z from "zod"

export const YourTool = Tool.define("your-tool", {
  description: "One sentence: what this tool does and when to use it.",
  parameters: z.object({
    input: z.string().describe("Description of this parameter"),
    optional_flag: z.boolean().optional().describe("When to set this"),
  }),
  async execute(input, ctx) {
    // ctx.sessionID, ctx.messageID, ctx.abort (AbortSignal)

    // Request permission if needed
    await ctx.ask({
      permission: "write",
      patterns: [input.input],
    })

    // Do the work
    const result = await doSomething(input.input)

    // Return string content
    return result
  },
})
```

### Register in tool index:

Add import + registration in the tool registry file. OpenCode auto-discovers tools from the `src/tool/` directory.

### Key patterns:
- `ctx.ask()` for permission gating
- Return strings (auto-truncated if > 50KB / 2000 lines)
- `ctx.abort` is an AbortSignal for cancellation
- Use `ctx.metadata()` to attach structured data for the UI

## Hermes Agent Tools (Python)

Hermes uses a 3-file pattern:

### File 1: `tools/your_tool.py`

```python
def get_your_tool_definitions():
    """Return tool definitions for the LLM."""
    return [{
        "type": "function",
        "function": {
            "name": "your_tool",
            "description": "One sentence: what this tool does.",
            "parameters": {
                "type": "object",
                "properties": {
                    "input": {
                        "type": "string",
                        "description": "Description of this parameter"
                    },
                },
                "required": ["input"]
            }
        }
    }]


def handle_your_tool(args: dict, context: dict) -> str:
    """Execute the tool. Return a string result."""
    input_val = args.get("input", "")

    # Do the work
    result = do_something(input_val)

    return str(result)
```

### File 2: Register in `model_tools.py`

```python
from tools.your_tool import get_your_tool_definitions, handle_your_tool
```

Add to the tool definitions list and the handler dispatch.

### File 3: Register in `toolsets.py`

Add `"your_tool"` to the appropriate toolset (e.g., `"default"`, `"coding"`, `"research"`).

## Code-Agents / Rust Tools

### File: `crates/tools/src/your_tool.rs`

```rust
use async_trait::async_trait;
use serde_json::Value;
use crate::{Tool, ToolContext, ToolResult, PermissionLevel};

pub struct YourTool;

#[async_trait]
impl Tool for YourTool {
    fn name(&self) -> &str { "your_tool" }

    fn description(&self) -> &str {
        "One sentence: what this tool does."
    }

    fn permission_level(&self) -> PermissionLevel {
        PermissionLevel::ReadOnly  // or Write, Execute, Dangerous
    }

    fn input_schema(&self) -> Value {
        serde_json::json!({
            "type": "object",
            "properties": {
                "input": {
                    "type": "string",
                    "description": "Description of this parameter"
                }
            },
            "required": ["input"]
        })
    }

    async fn execute(&self, input: Value, ctx: &ToolContext) -> ToolResult {
        let input_str = input["input"].as_str()
            .ok_or_else(|| "missing 'input' parameter")?;

        match do_something(input_str).await {
            Ok(result) => ToolResult::success(result),
            Err(e) => ToolResult::error(format!("Failed: {e}")),
        }
    }
}
```

Register in `crates/tools/src/lib.rs` tool list.

## MCP Tools (Framework-Agnostic)

See the `mcp-server` skill for full details. MCP tools work with ANY agent:

```python
from fastmcp import FastMCP
mcp = FastMCP("your-tools")

@mcp.tool()
def your_tool(input: str) -> str:
    """One sentence: what this tool does."""
    return do_something(input)
```

Connect via config in `.opencode/opencode.json`, `.cursor/mcp.json`, or `.claude/mcp.json`.

## Writing Good Descriptions

The description is what the LLM reads to decide whether to use the tool. It must be:

1. **Specific**: "Read a file from disk given an absolute path" not "Read files"
2. **Action-oriented**: Start with a verb. "Search", "Create", "List", "Run"
3. **Scoped**: Say what the tool does NOT do. "Reads files but does not modify them"
4. **Example-rich**: Include when-to-use hints. "Use this when you need to find files matching a pattern"

## Writing Good Parameters

- Every parameter needs a `.describe()` / `"description"` string
- Use enums for constrained values (`z.enum(["json", "text", "markdown"])`)
- Mark optional parameters explicitly
- Use sensible defaults documented in the description
- Validate at the boundary (Zod / JSON Schema does this automatically)

## Testing Tools

### Manual test:
```bash
# OpenCode: use the tool in a conversation
opencode run -p "Use the your_tool tool with input 'test'"

# Hermes: call directly
hermes chat -q "Use the your_tool tool with input 'test'"

# MCP: call via fastmcp CLI
fastmcp call server.py your_tool input="test"
```

### Automated test:
```python
# Python
def test_your_tool():
    result = handle_your_tool({"input": "test"}, {})
    assert "expected" in result
```

```typescript
// TypeScript
test("your_tool", async () => {
  const result = await YourTool.execute({ input: "test" }, mockCtx)
  expect(result).toContain("expected")
})
```

```rust
// Rust
#[tokio::test]
async fn test_your_tool() {
    let tool = YourTool;
    let input = serde_json::json!({"input": "test"});
    let result = tool.execute(input, &mock_ctx()).await;
    assert!(!result.is_error);
}
```

## Checklist

- [ ] Name is verb_noun or noun_verb, lowercase with underscores
- [ ] Description is one clear sentence
- [ ] All parameters have descriptions
- [ ] Required vs optional is explicit
- [ ] Permission level is appropriate (prefer ReadOnly when possible)
- [ ] Errors return descriptive messages (not stack traces)
- [ ] Output is text, not binary (truncate if large)
- [ ] Tool is registered in the framework's registry
- [ ] At least one test exists
