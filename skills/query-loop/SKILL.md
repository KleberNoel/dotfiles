---
name: query-loop
description: "The core agent execution engine: stream API response, detect tool calls, execute tools, check permissions, fire hooks, append results, manage token budget, and decide whether to continue or stop. Covers stop conditions, error recovery, streaming accumulation, and the tool execution cycle. Use when building or understanding agent runtimes."
license: MIT
metadata:
  pattern: query-loop
  sources: code-agents, claude-code
---

# Query Loop: The Agent Execution Engine

Every AI agent is, at its core, a loop: send messages to a model, get a response, execute any tool calls, append results, repeat. This skill defines the precise mechanics of that loop, including all stop conditions, error recovery paths, and integration points.

## The Loop

```
function run_query_loop(conversation, tools, config) -> QueryOutcome:
    loop:
        // 1. Build request
        messages = conversation.to_api_messages()
        
        // 2. Stream response
        response = stream_api_call(messages, tools, config)
        
        // 3. Check token budget
        auto_compact_if_needed(conversation, response.usage)
        
        // 4. Inspect stop reason
        match response.stop_reason:
            "end_turn"      -> return QueryOutcome::EndTurn
            "stop_sequence" -> return QueryOutcome::EndTurn
            "max_tokens"    -> return QueryOutcome::MaxTokens
            "tool_use"      -> execute_tools_and_continue(response)
            unknown         -> return QueryOutcome::EndTurn
        
        // 5. Execute tool calls (only reached on tool_use)
        for tool_call in response.tool_calls:
            // 5a. Pre-hooks
            hook_result = run_hooks(PreToolUse, tool_call)
            if hook_result == Blocked(reason):
                append_tool_error(tool_call.id, reason)
                continue
            
            // 5b. Execute
            tool_result = execute_tool(tool_call.name, tool_call.input)
            
            // 5c. Post-hooks
            hook_result = run_hooks(PostToolUse, tool_call, tool_result)
            if hook_result == Modified(new_result):
                tool_result = new_result
            
            // 5d. Append result
            conversation.append_tool_result(tool_call.id, tool_result)
        
        // 6. Loop back to step 1
```

## QueryOutcome

The loop always terminates with one of four outcomes:

```
enum QueryOutcome:
    EndTurn      # Model finished naturally (said what it wanted to say)
    MaxTokens    # Context window exhausted (response was cut off)
    Cancelled    # User or system cancelled the request
    Error(msg)   # Unrecoverable error (API failure, auth error, etc.)
```

### How to Handle Each Outcome

| Outcome | Meaning | Action |
|---|---|---|
| `EndTurn` | Model is done responding | Display response, wait for user input |
| `MaxTokens` | Response was truncated | Auto-compact conversation and retry, or ask user |
| `Cancelled` | User pressed Ctrl+C or timeout | Clean up, preserve state |
| `Error` | API/network/auth failure | Retry with backoff (see error recovery) |

## Stop Reasons Explained

The API returns a `stop_reason` with every response. Understanding these is critical:

### `end_turn`
The model voluntarily stopped generating. It said everything it wanted to say. This is the normal happy path when the model responds with text only (no tool calls).

### `tool_use`
The model wants to call one or more tools. The response contains `tool_use` content blocks with `name`, `id`, and `input` fields. **Do not return to the user** — execute the tools and continue the loop.

### `max_tokens`
The model hit the output token limit. The response is **incomplete**. This can mean:
- The model was generating a long response (truncated mid-sentence)
- The context window is nearly full (no room for output)
- Action: trigger auto-compact, then retry the request

### `stop_sequence`
A custom stop sequence was matched. Rarely used in agent loops but relevant for structured output extraction.

## Streaming Accumulation

API responses arrive as a stream of chunks. You need a `StreamAccumulator` to assemble complete content blocks:

```
class StreamAccumulator:
    text_buffer: String           # Accumulates text content
    tool_calls: Vec<ToolCall>     # Accumulates tool_use blocks
    current_tool_input: String    # Partial JSON for current tool input
    usage: Usage                  # Token counts from the stream
    stop_reason: String           # Set when stream ends
    
    function feed(chunk):
        match chunk.type:
            "content_block_start":
                if chunk.content_block.type == "tool_use":
                    start new tool call with id and name
            "content_block_delta":
                if text delta: append to text_buffer
                if tool input delta: append to current_tool_input
            "content_block_stop":
                if building tool call: parse current_tool_input as JSON
            "message_delta":
                set stop_reason, update usage
            "message_stop":
                finalize
```

### Streaming Pitfalls

1. **Partial JSON** — Tool input arrives as string fragments. Don't try to parse until `content_block_stop`.
2. **Multiple content blocks** — A single response can contain text + multiple tool calls. Process all of them.
3. **Interleaved text and tools** — The model may write text, then call a tool, then write more text. Display text as it streams, queue tool calls.
4. **Cancellation during streaming** — Use `tokio::select!` (Rust) or `AbortController` (JS) to cleanly cancel mid-stream. Biased toward the cancellation signal.

## ToolResult Structure

Every tool execution returns a `ToolResult`:

```
struct ToolResult:
    content: String           # The output to show the model
    is_error: bool            # Whether this represents a failure
    metadata: Option<Value>   # Extra data (not sent to model, used by hooks/logging)
```

### Rules for ToolResult

- **`content`** is what the model sees. Keep it concise but complete.
- **`is_error: true`** tells the model something went wrong. The model can then decide to retry, try a different approach, or report the error.
- **Never return empty content** — always provide at least a status message.
- **Truncate large outputs** — If a command produces 10,000 lines, truncate and tell the model: "Output truncated (showing first 200 lines of 10,000). Use grep to search for specific content."

## Token Budget Management

Check the token budget after every API response:

```
function check_token_budget(conversation, usage, config):
    total_tokens = usage.input_tokens + usage.output_tokens
    context_limit = config.model_context_limit
    fraction = total_tokens / context_limit
    
    if fraction >= 0.95 and compact_failed:
        signal ROTATE  # Start fresh context
    elif fraction >= 0.90:
        trigger auto_compact(conversation)
    elif fraction >= 0.85:
        warn "Context at {fraction*100}%, compaction imminent"
    
    # Also check output budget
    max_output = get_max_output_tokens(config.model)
    remaining = context_limit - usage.input_tokens - max_output
    if remaining < 1000:
        trigger auto_compact(conversation)
```

### Per-Model Output Limits

```
claude-opus:    4096 default, 16384 extended
claude-sonnet:  4096 default, 16384 extended  
gpt-4o:         4096 default, 16384 extended
```

## Error Recovery

### API Errors (Retryable)

```
RETRY_DELAYS = [1s, 2s, 4s, 8s, 16s]  # Exponential backoff
MAX_RETRIES = 5

for attempt in 0..MAX_RETRIES:
    try:
        response = stream_api_call(messages, tools)
        return response
    catch error:
        if error.status in [429, 500, 502, 503, 529]:
            # Retryable
            delay = RETRY_DELAYS[min(attempt, len(RETRY_DELAYS)-1)]
            jitter = random(0, delay * 0.1)
            sleep(delay + jitter)
            continue
        elif error.status in [400, 401, 403]:
            # Not retryable
            return QueryOutcome::Error(error.message)
        else:
            # Unknown — retry once, then fail
            if attempt == 0: continue
            return QueryOutcome::Error(error.message)
```

### Tool Execution Errors

When a tool crashes or times out:

```
function execute_tool_safe(name, input) -> ToolResult:
    try:
        result = tools[name].execute(input)
        return result
    catch timeout:
        return ToolResult(
            content: "Tool '{name}' timed out after {timeout}s",
            is_error: true
        )
    catch error:
        return ToolResult(
            content: "Tool '{name}' failed: {error.message}",
            is_error: true
        )
```

**Never crash the loop because a tool failed.** Always convert tool errors into `ToolResult(is_error: true)` and let the model decide what to do.

### Stuck Loop Detection

The model can get stuck calling the same tool with the same input repeatedly:

```
STUCK_THRESHOLD = 3  # Same tool+input 3 times in a row

if last_n_tool_calls_identical(STUCK_THRESHOLD):
    inject system message: "You appear stuck calling {tool} repeatedly 
    with the same input. Try a different approach."
    
    if still stuck after intervention:
        return QueryOutcome::Error("Agent stuck in loop")
```

## The Complete Iteration

Putting it all together, one full iteration of the query loop:

```
1.  Build messages array from conversation history
2.  Add system prompt (static + dynamic sections)
3.  Call streaming API
4.  Accumulate stream chunks into complete response
5.  Update token usage counters
6.  Check token budget → compact if needed
7.  Extract stop_reason
8.  If end_turn/stop_sequence → return EndTurn
9.  If max_tokens → attempt compact, retry
10. If tool_use:
    a. Extract all tool_call blocks from response
    b. For each tool_call:
       - Validate tool exists and input matches schema
       - Run PreToolUse hooks (may block)
       - Execute tool (with timeout and error catching)
       - Run PostToolUse hooks (may modify result)
       - Append ToolResult to conversation
    c. Go to step 1
11. If cancelled → return Cancelled
12. If error → retry with backoff or return Error
```

## Integration Points

### With context-management
Token budget checks at step 6 trigger the auto-compact algorithm defined in the `context-management` skill.

### With hooks-lifecycle
PreToolUse and PostToolUse hooks at steps 10b fire the hook system defined in the `hooks-lifecycle` skill.

### With permission-safety
Tool execution at step 10b passes through the permission validation gate defined in the `permission-safety` skill.

### With tool-builder
Tools registered in the loop must conform to the Tool interface defined in the `tool-builder` skill.

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| Parsing tool JSON before stream complete | Partial JSON → parse error | Wait for `content_block_stop` |
| Crashing on tool failure | Kills the entire agent session | Wrap in try/catch, return error ToolResult |
| Ignoring max_tokens | Model response is incomplete | Auto-compact and retry |
| No stuck-loop detection | Agent burns tokens forever | Detect repeated identical tool calls |
| Retrying 401/403 errors | Auth won't fix itself | Fail fast on non-retryable errors |
| Blocking on tool execution | One slow tool blocks everything | Use timeouts on all tool executions |
