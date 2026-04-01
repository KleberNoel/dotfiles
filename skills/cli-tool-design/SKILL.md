---
name: cli-tool-design
description: "Building command-line tools: argument parsing (positional, flags, subcommands), help text, stdin/stdout/stderr conventions, exit codes, interactive prompts with non-interactive fallback, progress indicators, color output with NO_COLOR support, config hierarchy (flag > env > config > default), and shell completions. Use when building CLI tools in any language."
license: MIT
metadata:
  pattern: cli-tool-design
  languages: python, typescript, go, rust
---

# CLI Tool Design: Building Command-Line Tools That Don't Suck

Good CLI tools are discoverable, composable, and predictable. They follow conventions that users already know from decades of Unix tradition.

## Argument Design

### The Three Types

```
1. SUBCOMMANDS — distinct operations
   git commit
   docker build
   npm install

2. POSITIONAL ARGUMENTS — required inputs in order
   cp <source> <destination>
   cat <file1> <file2>

3. FLAGS/OPTIONS — optional modifiers
   --verbose, -v          (boolean flag)
   --output=file, -o file (flag with value)
   --count 5, -n 5        (flag with value)
```

### Design Rules

```
1. If your tool does ONE thing:     use positional args + flags
   grep <pattern> <file> --ignore-case

2. If your tool does MANY things:   use subcommands
   git status, git commit, git push

3. Long flags are self-documenting: --recursive, --dry-run, --verbose
4. Short flags for frequent use:    -r, -n, -v
5. Required args are positional:    tool <required>
6. Optional args are flags:         tool --optional=value
7. Boolean flags don't take values: --verbose NOT --verbose=true
```

### Subcommand Hierarchy

```
tool <command> [subcommand] [flags] [args]

Examples:
  docker container ls --all
  git remote add origin <url>
  aws s3 cp <source> <dest> --recursive
  
Max depth: 2 levels (command + subcommand). Deeper nesting is confusing.
```

## Help Text

### Auto-Generated Help

Every tool must respond to `--help` and `-h`. Structure:

```
$ tool --help
Usage: tool <command> [options]

A brief one-line description of what this tool does.

Commands:
  init        Initialize a new project
  build       Build the project
  test        Run tests
  deploy      Deploy to production

Options:
  -v, --verbose    Enable verbose output
  -q, --quiet      Suppress all output
  -h, --help       Show this help message
  --version        Show version number

Examples:
  tool init my-project
  tool build --release
  tool test --coverage

Run 'tool <command> --help' for command-specific help.
```

### Help Text Rules

```
1. First line: "Usage: tool <synopsis>"
2. Description: ONE sentence, no period
3. Commands: sorted alphabetically, aligned descriptions
4. Options: short flag first, long flag, then description
5. Examples: 2-3 real-world usage examples
6. Cross-reference: how to get command-specific help
```

### Per-Command Help

```
$ tool build --help
Usage: tool build [options] [target]

Build the project artifacts.

Arguments:
  target          Build target (default: "all")

Options:
  -r, --release   Build in release mode (optimized)
  -j, --jobs N    Number of parallel jobs (default: CPU count)
  -o, --output    Output directory (default: "./dist")
  --clean         Clean before building

Examples:
  tool build                    # Build everything in debug mode
  tool build --release          # Optimized build
  tool build frontend -j 4      # Build frontend with 4 jobs
```

## stdin/stdout/stderr Conventions

### The Unix Philosophy

```
stdout → Data output (pipe-friendly, machine-readable when piped)
stderr → Human messages (progress, warnings, errors, debug info)
stdin  → Data input (when no file argument given)
```

### Implementation

```python
import sys

def main():
    # Read from file arg or stdin
    if args.file:
        data = open(args.file).read()
    elif not sys.stdin.isatty():
        data = sys.stdin.read()     # Piped input
    else:
        print("Error: no input. Provide a file or pipe data.", file=sys.stderr)
        sys.exit(1)
    
    # Data goes to stdout (pipeable)
    result = process(data)
    print(result)                    # stdout — data
    
    # Messages go to stderr (not captured by pipes)
    print(f"Processed {len(data)} bytes", file=sys.stderr)
```

### Pipe Detection

```python
# Detect if stdout is a terminal or a pipe
if sys.stdout.isatty():
    # Interactive — show colors, progress bars, tables
    print_fancy_table(results)
else:
    # Piped — output machine-readable format (JSON, CSV, TSV)
    print(json.dumps(results))
```

## Exit Codes

```
0    — Success
1    — General error
2    — Usage error (bad arguments, missing required flag)
126  — Permission denied (command found but not executable)
127  — Command not found
128+ — Killed by signal (128 + signal number)
130  — Interrupted (Ctrl+C, 128 + SIGINT=2)
```

### Custom Exit Codes

For tools that need more granularity:

```
0    — Success, no issues
1    — Error (general)
2    — Usage error (bad arguments)
3    — Configuration error
4    — Input error (file not found, invalid format)
5    — Network error (timeout, DNS failure)
10   — Partial success (some items processed, some failed)
```

**Document your exit codes** in `--help` or man page.

## Interactive Prompts

### With Non-Interactive Fallback

```python
import sys

def prompt_confirm(message, default=False):
    """Prompt for yes/no. Falls back to default in non-interactive mode."""
    if not sys.stdin.isatty():
        return default  # Non-interactive — use default
    
    suffix = " [Y/n] " if default else " [y/N] "
    response = input(message + suffix).strip().lower()
    
    if not response:
        return default
    return response in ("y", "yes")

# Usage:
if prompt_confirm("Delete all build artifacts?", default=False):
    clean_build()
```

### The --yes Flag

```
tool deploy --yes          # Skip all confirmation prompts
tool clean --assume-yes    # Alternative naming

# In code:
if args.yes or prompt_confirm("Continue?"):
    proceed()
```

### Input Hierarchy

```
1. Command-line flag     (highest priority)
2. Environment variable  
3. Config file           
4. Interactive prompt    
5. Default value         (lowest priority)

Example:
  --token=abc       → uses "abc"
  TOKEN=def (env)   → uses "def" (if no flag)
  config.token=ghi  → uses "ghi" (if no env)
  prompt: "Token?"  → asks user (if no config, interactive)
  default: none     → error (if non-interactive and no other source)
```

## Progress Indicators

### When to Show Progress

```
< 1 second:    No indicator needed
1-5 seconds:   Spinner
5+ seconds:    Progress bar with ETA
Background:    Status line that updates in-place
```

### Spinner

```
Frames: ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
Update rate: 80ms

Output: ⠹ Building project...       (stderr, not stdout)
```

### Progress Bar

```
Building ████████████░░░░░░░░ 62% (124/200) ETA: 12s

Components:
  label + filled bar + empty bar + percentage + count + ETA
```

### Rules

```
1. Progress goes to stderr (never pollute stdout)
2. Disable in non-interactive mode (no tty)
3. Respect --quiet flag
4. Use \r to overwrite in place (no scrolling)
5. Clear the progress line before printing other output
```

## Color Output

### The NO_COLOR Standard

```bash
# Respect the NO_COLOR environment variable (https://no-color.org)
NO_COLOR=1 tool build    # Forces no color output
```

### Implementation

```python
import os, sys

def supports_color():
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("FORCE_COLOR"):
        return True
    if not sys.stderr.isatty():
        return False  # Piped — no color
    return True

# Color codes
RED    = "\033[31m" if supports_color() else ""
GREEN  = "\033[32m" if supports_color() else ""
YELLOW = "\033[33m" if supports_color() else ""
BOLD   = "\033[1m"  if supports_color() else ""
RESET  = "\033[0m"  if supports_color() else ""

print(f"{RED}Error:{RESET} file not found", file=sys.stderr)
print(f"{GREEN}✓{RESET} Build succeeded", file=sys.stderr)
```

### Semantic Colors

```
Red:     Errors, failures, destructive actions
Green:   Success, passing tests, created files
Yellow:  Warnings, deprecations, important notices
Blue:    Information, links, file paths
Bold:    Emphasis, headers, key values
Dim:     Secondary information, timestamps
```

## Config File Hierarchy

```
Priority (highest to lowest):
1. CLI flags:           --port 8080
2. Environment vars:    PORT=8080
3. Local config:        ./.toolrc.json
4. User config:         ~/.config/tool/config.json
5. System config:       /etc/tool/config.json
6. Built-in defaults:   port: 3000
```

### Config File Format

```json
// ~/.config/tool/config.json
{
  "port": 8080,
  "verbose": false,
  "output": {
    "format": "json",
    "color": "auto"
  }
}
```

### Environment Variable Naming

```
TOOL_PORT=8080              # TOOL_ prefix + UPPERCASE
TOOL_OUTPUT_FORMAT=json     # Nested: underscores for dots
TOOL_VERBOSE=1              # Boolean: 1/true/yes = true
```

## Shell Completions

### Generating Completions

Most CLI frameworks support generating completion scripts:

```bash
# Generate and install for bash
tool completions bash > ~/.local/share/bash-completion/completions/tool

# Generate for zsh
tool completions zsh > ~/.zfunc/_tool

# Generate for fish
tool completions fish > ~/.config/fish/completions/tool.fish
```

### What to Complete

```
1. Subcommands:      tool <TAB> → init build test deploy
2. Flags:            tool build --<TAB> → --release --jobs --output
3. Flag values:      tool build --format <TAB> → json yaml toml
4. File paths:       tool build -o <TAB> → (file completion)
5. Dynamic values:   tool deploy --env <TAB> → staging production
```

## Language-Specific Libraries

```
Python:     click, typer (recommended), argparse (stdlib)
TypeScript: commander, yargs, oclif (for complex CLIs)
Go:         cobra (standard), urfave/cli
Rust:       clap (derive or builder API)
```

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| No `--help` flag | Users can't discover features | Always implement -h/--help |
| Colors on stdout | Breaks piping to other tools | Colors on stderr only, respect NO_COLOR |
| No non-interactive mode | Can't use in scripts/CI | Accept flags for all prompts, --yes |
| Interactive-only input | Breaks in pipelines | Accept stdin and file args |
| Chatty default output | Overwhelms users, breaks pipes | Quiet by default, --verbose for more |
| Custom flag syntax | `+v` instead of `-v` | Use standard `-` and `--` conventions |
| No exit codes | Scripts can't check success | Document and use meaningful exit codes |
