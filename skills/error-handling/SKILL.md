---
name: error-handling
description: "Defensive error handling patterns across languages: exception hierarchies, error boundaries, retry with backoff and jitter, circuit breakers for external services, structured error responses, graceful degradation. Covers when to crash vs recover, retryable vs terminal errors, and error propagation strategies. Use when implementing error handling or reviewing error-prone code."
license: MIT
metadata:
  pattern: error-handling
  languages: python, typescript, go, rust
---

# Error Handling: Defensive Patterns Across Languages

Good error handling is the difference between software that works and software that works in production. This skill covers the patterns that make code resilient.

## The Fundamental Question: Crash or Recover?

```
CRASH when:
  - Invariant violated (impossible state reached)
  - Configuration missing at startup (fail fast)
  - Unrecoverable resource exhaustion (out of memory)
  - Security violation detected

RECOVER when:
  - Network request failed (retry)
  - User input invalid (report and re-prompt)
  - External service down (degrade gracefully)
  - Rate limit hit (back off)
  - File not found (check alternatives)
```

**Default stance: crash.** Only recover when you have a specific, tested recovery path. Silent error swallowing is worse than crashing.

## Error Classification

### Retryable vs Terminal

```
RETRYABLE (transient):
  - HTTP 429 (rate limit)
  - HTTP 500, 502, 503, 529 (server error)
  - Connection timeout
  - DNS resolution failure
  - Lock contention
  - Optimistic concurrency conflict

TERMINAL (permanent):
  - HTTP 400 (bad request — your input is wrong)
  - HTTP 401, 403 (auth — credentials won't fix themselves)
  - HTTP 404 (resource doesn't exist)
  - Parse error (data is corrupt)
  - Schema validation failure
  - Business rule violation
```

**Rule: never retry terminal errors.** You'll just waste time and potentially make things worse (e.g., creating duplicate resources).

## Retry with Exponential Backoff + Jitter

The standard retry pattern for transient failures:

```python
import random
import time

def retry_with_backoff(fn, max_retries=5, base_delay=1.0, max_delay=60.0):
    for attempt in range(max_retries):
        try:
            return fn()
        except RetryableError as e:
            if attempt == max_retries - 1:
                raise  # Final attempt, propagate
            
            delay = min(base_delay * (2 ** attempt), max_delay)
            jitter = random.uniform(0, delay * 0.1)
            time.sleep(delay + jitter)
    
    raise MaxRetriesExceeded()
```

### Why Jitter?

Without jitter, when a service recovers from an outage, all clients retry at exactly the same intervals, creating a "thundering herd" that crashes the service again. Jitter spreads retries randomly.

### Backoff Constants

```
BASE_DELAY   = 1.0 seconds
MAX_DELAY    = 60.0 seconds
MAX_RETRIES  = 5
JITTER       = random(0, delay * 0.1)

Delays: 1s, 2s, 4s, 8s, 16s (capped at 60s)
```

## Circuit Breaker Pattern

For external service calls, prevent cascade failures by "opening" the circuit after repeated failures:

```
class CircuitBreaker:
    states: CLOSED (normal) → OPEN (failing) → HALF_OPEN (testing)
    
    FAILURE_THRESHOLD = 5      # Failures before opening
    RESET_TIMEOUT     = 30s    # Time before trying again
    SUCCESS_THRESHOLD = 3      # Successes to close again

    function call(fn):
        match state:
            CLOSED:
                try:
                    result = fn()
                    reset_failure_count()
                    return result
                catch:
                    increment_failure_count()
                    if failure_count >= FAILURE_THRESHOLD:
                        state = OPEN
                        open_time = now()
                    raise

            OPEN:
                if now() - open_time >= RESET_TIMEOUT:
                    state = HALF_OPEN
                    return call(fn)  # Try once
                raise CircuitOpenError("Service unavailable, try later")

            HALF_OPEN:
                try:
                    result = fn()
                    increment_success_count()
                    if success_count >= SUCCESS_THRESHOLD:
                        state = CLOSED
                    return result
                catch:
                    state = OPEN
                    open_time = now()
                    raise
```

## Structured Error Responses

### API Error Format

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Email address is not valid",
    "details": [
      {
        "field": "email",
        "constraint": "Must be a valid email address",
        "received": "not-an-email"
      }
    ],
    "request_id": "req_abc123",
    "timestamp": "2026-04-01T12:00:00Z"
  }
}
```

### Error Code Design

```
Use hierarchical, machine-readable codes:
  AUTH_TOKEN_EXPIRED
  AUTH_INSUFFICIENT_PERMISSIONS
  VALIDATION_REQUIRED_FIELD
  VALIDATION_INVALID_FORMAT
  RESOURCE_NOT_FOUND
  RESOURCE_ALREADY_EXISTS
  RATE_LIMIT_EXCEEDED
  INTERNAL_SERVER_ERROR

NOT: "Something went wrong" (useless)
NOT: error code 42 (meaningless without a lookup table)
```

## Language-Specific Patterns

### Python

```python
# Custom exception hierarchy
class AppError(Exception):
    """Base for all application errors."""
    def __init__(self, message: str, code: str, status: int = 500):
        self.message = message
        self.code = code
        self.status = status

class NotFoundError(AppError):
    def __init__(self, resource: str, id: str):
        super().__init__(
            message=f"{resource} with id '{id}' not found",
            code="RESOURCE_NOT_FOUND",
            status=404
        )

class ValidationError(AppError):
    def __init__(self, field: str, constraint: str):
        super().__init__(
            message=f"Validation failed for '{field}': {constraint}",
            code="VALIDATION_ERROR",
            status=400
        )

# Context manager for cleanup
from contextlib import contextmanager

@contextmanager
def managed_connection(url):
    conn = connect(url)
    try:
        yield conn
    except Exception:
        conn.rollback()
        raise
    else:
        conn.commit()
    finally:
        conn.close()
```

### TypeScript

```typescript
// Result type (no exceptions)
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };

function parseConfig(raw: string): Result<Config, ValidationError> {
  try {
    const parsed = JSON.parse(raw);
    if (!parsed.apiKey) {
      return { ok: false, error: new ValidationError("apiKey is required") };
    }
    return { ok: true, value: parsed as Config };
  } catch {
    return { ok: false, error: new ValidationError("Invalid JSON") };
  }
}

// Error boundary (React)
class ErrorBoundary extends React.Component {
  state = { error: null };
  
  static getDerivedStateFromError(error) {
    return { error };
  }
  
  componentDidCatch(error, info) {
    logErrorToService(error, info.componentStack);
  }
  
  render() {
    if (this.state.error) {
      return <ErrorFallback error={this.state.error} />;
    }
    return this.props.children;
  }
}
```

### Go

```go
// Errors are values, not exceptions
func readConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("reading config %s: %w", path, err)
    }
    
    var cfg Config
    if err := json.Unmarshal(data, &cfg); err != nil {
        return nil, fmt.Errorf("parsing config %s: %w", path, err)
    }
    
    if cfg.APIKey == "" {
        return nil, fmt.Errorf("config %s: apiKey is required", path)
    }
    
    return &cfg, nil
}

// Sentinel errors for comparison
var (
    ErrNotFound     = errors.New("resource not found")
    ErrUnauthorized = errors.New("unauthorized")
)

// Check with errors.Is
if errors.Is(err, ErrNotFound) {
    // handle 404
}
```

### Rust

```rust
// Enum-based errors with thiserror
use thiserror::Error;

#[derive(Error, Debug)]
enum AppError {
    #[error("Resource not found: {resource} with id {id}")]
    NotFound { resource: String, id: String },
    
    #[error("Validation error: {0}")]
    Validation(String),
    
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),
    
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

// ? operator for propagation
fn load_user(id: &str) -> Result<User, AppError> {
    let row = db.query("SELECT * FROM users WHERE id = $1", &[&id])
        .await?;  // sqlx::Error auto-converts to AppError::Database
    
    row.ok_or_else(|| AppError::NotFound {
        resource: "User".into(),
        id: id.into(),
    })
}
```

## Graceful Degradation

When an external dependency fails, degrade instead of crashing:

```
// Full service
Homepage: personalized recommendations + search + user profile + notifications

// Recommendation service down
Homepage: trending items (cached) + search + user profile + notifications
          ↑ fallback to cached/static content

// Search service down  
Homepage: trending items (cached) + "Search temporarily unavailable" + user profile
          ↑ show honest error message for that feature

// Database down
Homepage: static cached version + "Some features temporarily unavailable"
          ↑ serve what you can from cache
```

### Degradation Rules

1. **Each dependency failure should be independent** — one service down shouldn't take everything down
2. **Cache aggressively** — stale data is better than no data for many use cases
3. **Be honest with users** — show what's degraded, don't pretend everything is fine
4. **Set timeouts on all external calls** — a slow dependency is as bad as a down one
5. **Monitor degradation state** — alert when operating in degraded mode

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| `catch (Exception e) {}` | Silently swallows all errors | Catch specific exceptions, log others |
| Retrying terminal errors | Wastes time, may cause duplicates | Classify errors, only retry transient |
| No timeout on HTTP calls | One slow service blocks everything | Always set connect + read timeouts |
| Generic error messages | Users and devs can't diagnose | Structured errors with codes and context |
| Logging errors without context | "Error occurred" is useless | Include request ID, input, stack trace |
| Nested try/catch blocks | Unreadable, error swallowing risk | Extract to functions, use Result type |
