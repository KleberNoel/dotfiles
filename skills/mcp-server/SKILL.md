---
name: mcp-server
description: "Build and connect MCP (Model Context Protocol) servers to expose tools to AI agents. Covers Python (fastmcp) and TypeScript implementations, connecting to opencode/cursor/claude, and wrapping existing shell functions as agent-callable tools."
license: MIT
metadata:
  pattern: mcp-tool-bridge
  origin: nousresearch/hermes-agent, opencode mcp-servers
---

# MCP Server: Build Agent-Callable Tools

MCP (Model Context Protocol) is the standard for exposing tools to AI agents. Build a server, connect it, and any agent can call your tools.

## When To Use This

- You have shell functions, scripts, or APIs you want agents to call
- You need to extend agent capabilities beyond built-in tools
- You want to bridge existing automation into the agent workflow
- You need a tool that queries a database, calls an API, or runs a specific binary

## Quick Start: Python (fastmcp)

### Install
```bash
pip install fastmcp
```

### Create a server

```python
# tools_server.py
from fastmcp import FastMCP

mcp = FastMCP("my-tools")

@mcp.tool()
def search_history(query: str) -> str:
    """Search bash eternal history for a pattern."""
    import subprocess
    result = subprocess.run(
        ["grep", "-i", query, os.path.expanduser("~/.bash_eternal_history")],
        capture_output=True, text=True
    )
    return result.stdout or "No matches found."

@mcp.tool()
def daily_log(entry: str = "") -> str:
    """Open or append to today's daily log file."""
    from datetime import date
    import os
    log_dir = os.path.expanduser("~/.dailylog")
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, date.today().isoformat())
    if entry:
        with open(log_file, "a") as f:
            f.write(entry + "\n")
        return f"Appended to {log_file}"
    elif os.path.exists(log_file):
        with open(log_file) as f:
            return f.read()
    return f"No log for today yet. File: {log_file}"

@mcp.tool()
def zombies() -> str:
    """Find zombie processes."""
    import subprocess
    result = subprocess.run(
        ["ps", "aux"],
        capture_output=True, text=True
    )
    zombies = [l for l in result.stdout.splitlines() if " Z " in l or " Z+ " in l]
    return "\n".join(zombies) if zombies else "No zombie processes."

if __name__ == "__main__":
    mcp.run()
```

### Test it
```bash
# Inspect available tools
fastmcp inspect tools_server.py

# Call a tool directly
fastmcp call tools_server.py search_history query="git commit"
```

## Quick Start: TypeScript

```typescript
// tools-server.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execSync } from "child_process";

const server = new McpServer({ name: "my-tools", version: "1.0.0" });

server.tool(
  "disk_usage",
  "Show disk usage for a directory, sorted by size",
  { path: z.string().describe("Directory path to analyze") },
  async ({ path }) => {
    const output = execSync(`du -sh ${path}/* | sort -rh | head -20`, {
      encoding: "utf-8",
    });
    return { content: [{ type: "text", text: output }] };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
```

## Connecting to Agent Tools

### OpenCode

Add to `.opencode/opencode.json` (project) or `~/.config/opencode/config.json` (global):

```json
{
  "mcp": {
    "my-tools": {
      "command": "python",
      "args": ["tools_server.py"],
      "cwd": "/path/to/server"
    }
  }
}
```

### Cursor

Add to `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "my-tools": {
      "command": "python",
      "args": ["tools_server.py"]
    }
  }
}
```

### Claude Code

Add to `.claude/mcp.json`:

```json
{
  "mcpServers": {
    "my-tools": {
      "command": "python",
      "args": ["tools_server.py"]
    }
  }
}
```

### Hermes Agent

Add to `cli-config.yaml`:

```yaml
mcp_servers:
  my-tools:
    transport: stdio
    command: python
    args: ["tools_server.py"]
```

## Wrapping Shell Functions

Pattern for turning any bash function into an MCP tool:

```python
import subprocess
import os

@mcp.tool()
def run_shell_function(function_name: str, args: str = "") -> str:
    """Run a bash function from dotfiles.

    Available functions: search_history, dailylog, zombies,
    bakswp, disksp, git_switch_to_ssh_remote
    """
    allowed = {
        "search_history", "dailylog", "zombies", "bakswp",
        "disksp", "git_switch_to_ssh_remote", "find_windows_home",
    }
    if function_name not in allowed:
        return f"Function '{function_name}' not in allowed list: {allowed}"

    # Source bash_functions then call the function
    cmd = f'source ~/.bash_functions/*.sh 2>/dev/null; {function_name} {args}'
    result = subprocess.run(
        ["bash", "-c", cmd],
        capture_output=True, text=True, timeout=30,
        cwd=os.path.expanduser("~")
    )
    output = result.stdout
    if result.returncode != 0:
        output += f"\nSTDERR: {result.stderr}" if result.stderr else ""
        output += f"\nExit code: {result.returncode}"
    return output or "(no output)"
```

## Tool Design Guidelines

### Good tools
- Do one thing well
- Have clear parameter names with descriptions
- Return structured text (not raw binary)
- Handle errors gracefully (return error message, don't crash)
- Have timeouts for subprocess calls
- Validate inputs before executing

### Bad tools
- Do multiple unrelated things
- Accept arbitrary shell commands (security risk)
- Return megabytes of output (blows up context)
- Require interactive input
- Have side effects without clear naming (`delete_*`, `destroy_*`)

### Naming convention
```
verb_noun          # search_history, create_backup, list_processes
noun_verb          # file_read, git_status (when grouping by noun)
```

## Adding Resources (Read-Only Data)

MCP also supports resources -- data the agent can read but not execute:

```python
@mcp.resource("config://bashrc")
def get_bashrc() -> str:
    """Current .bashrc contents."""
    with open(os.path.expanduser("~/.bashrc")) as f:
        return f.read()

@mcp.resource("config://gitconfig")
def get_gitconfig() -> str:
    """Current .gitconfig contents."""
    with open(os.path.expanduser("~/.gitconfig")) as f:
        return f.read()
```

## Testing

```bash
# List all tools
fastmcp inspect tools_server.py

# Call a specific tool
fastmcp call tools_server.py search_history query="docker"

# Run as stdio server (for debugging transport)
python tools_server.py

# Test TypeScript server
npx ts-node tools-server.ts
```
