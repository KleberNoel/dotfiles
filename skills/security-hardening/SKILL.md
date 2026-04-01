---
name: security-hardening
description: "Application security patterns: input validation, SQL injection prevention, XSS/CSRF protection, authentication flows (OAuth2, JWT), secrets management, dependency vulnerability scanning, CORS configuration, and rate limiting. Use when building web applications, APIs, or reviewing code for security issues."
license: MIT
metadata:
  pattern: security-hardening
  languages: python, typescript, go
---

# Security Hardening: Application Security Patterns

Security is not a feature — it's a property of every feature. This skill covers the defensive patterns that prevent the most common and damaging vulnerabilities.

## The OWASP Top 10 (Condensed)

```
1. Broken Access Control     → Enforce authz on every endpoint
2. Cryptographic Failures    → Use standard libraries, never roll your own
3. Injection                 → Parameterized queries, never string concat
4. Insecure Design           → Threat model before building
5. Security Misconfiguration → Secure defaults, no debug in prod
6. Vulnerable Components     → Scan dependencies, update regularly
7. Auth Failures             → Strong passwords, MFA, rate limiting
8. Data Integrity Failures   → Verify signatures, validate inputs
9. Logging Failures          → Log security events, monitor alerts
10. SSRF                     → Validate URLs, restrict outbound
```

## Input Validation

**Rule: Never trust input from any external source.** This includes HTTP request bodies, query params, headers, URL paths, file uploads, environment variables from untrusted contexts, and data from external APIs.

### Validation Strategy

```
1. PARSE    — Decode the input (JSON, URL encoding, Unicode normalization)
2. VALIDATE — Check against a strict schema (type, length, format, range)
3. SANITIZE — Remove or escape dangerous characters for the output context
4. USE      — Only use the validated, sanitized version
```

### Schema Validation

```typescript
// TypeScript with Zod
import { z } from "zod";

const CreateUserSchema = z.object({
  email: z.string().email().max(255),
  name: z.string().min(1).max(100).regex(/^[a-zA-Z\s\-']+$/),
  age: z.number().int().min(13).max(150),
  role: z.enum(["user", "admin"]),
});

// Python with Pydantic
from pydantic import BaseModel, EmailStr, constr, conint

class CreateUser(BaseModel):
    email: EmailStr
    name: constr(min_length=1, max_length=100, pattern=r"^[a-zA-Z\s\-']+$")
    age: conint(ge=13, le=150)
    role: Literal["user", "admin"]
```

### Common Bypass Vectors

| Input | Attack | Defense |
|---|---|---|
| `../../../etc/passwd` | Path traversal | Resolve path, check prefix |
| `'; DROP TABLE--` | SQL injection | Parameterized queries |
| `<script>alert(1)</script>` | XSS | Context-aware escaping |
| `\x00` null bytes | Null byte injection | Strip null bytes |
| Unicode homoglyphs | Visual spoofing | Normalize unicode (NFKC) |
| Oversized payloads | DoS | Enforce max length/size |

## SQL Injection Prevention

**The only reliable defense: parameterized queries (prepared statements).**

```python
# WRONG — string concatenation
cursor.execute(f"SELECT * FROM users WHERE id = '{user_id}'")

# RIGHT — parameterized query
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
```

```typescript
// WRONG
db.query(`SELECT * FROM users WHERE id = '${userId}'`);

// RIGHT
db.query("SELECT * FROM users WHERE id = $1", [userId]);
```

```go
// WRONG
db.Query(fmt.Sprintf("SELECT * FROM users WHERE id = '%s'", userID))

// RIGHT
db.Query("SELECT * FROM users WHERE id = $1", userID)
```

### ORM Safety

ORMs generally use parameterized queries internally, but raw query methods are still dangerous:

```python
# Safe — ORM handles parameterization
User.objects.filter(id=user_id)

# DANGEROUS — raw SQL with string formatting
User.objects.raw(f"SELECT * FROM users WHERE name = '{name}'")

# Safe — raw SQL with parameters
User.objects.raw("SELECT * FROM users WHERE name = %s", [name])
```

## XSS Prevention

### Output Encoding

Escape output based on the context where it appears:

```
HTML body:    &lt;script&gt; → <script> (HTML entity encoding)
HTML attr:    " → &quot; (attribute encoding)  
JavaScript:   ' → \' (JavaScript string escaping)
URL:          < → %3C (URL encoding)
CSS:          Don't interpolate user data into CSS
```

### Content Security Policy

```
Content-Security-Policy: 
  default-src 'self';
  script-src 'self' 'nonce-{random}';
  style-src 'self' 'unsafe-inline';
  img-src 'self' data: https:;
  connect-src 'self' https://api.example.com;
  frame-ancestors 'none';
```

### React/JSX

React escapes by default. Danger zones:

```jsx
// Safe — React escapes automatically
<div>{userInput}</div>

// DANGEROUS — bypasses escaping
<div dangerouslySetInnerHTML={{ __html: userInput }} />

// DANGEROUS — URL injection
<a href={userInput}>Click</a>  // userInput = "javascript:alert(1)"
// Fix: validate URL scheme
const safeUrl = /^https?:\/\//.test(userInput) ? userInput : "#";
```

## CSRF Protection

### Token-Based

```
1. Server generates random CSRF token per session
2. Token embedded in HTML forms as hidden field
3. Token sent in custom header for AJAX requests
4. Server validates token on every state-changing request
```

### SameSite Cookies

```
Set-Cookie: session=abc123; SameSite=Lax; Secure; HttpOnly
```

| SameSite | Behavior |
|---|---|
| `Strict` | Cookie never sent cross-site (breaks OAuth redirects) |
| `Lax` | Sent on top-level navigations (good default) |
| `None` | Always sent (requires `Secure` flag, needed for cross-site APIs) |

## Authentication

### JWT Lifecycle

```
1. User logs in with credentials → POST /auth/login
2. Server validates credentials, issues access_token (short-lived) + refresh_token (long-lived)
3. Client stores tokens:
   - access_token: in memory (NOT localStorage for SPAs)
   - refresh_token: in HttpOnly cookie (NOT accessible to JS)
4. Client sends access_token in Authorization header
5. When access_token expires (401):
   a. Client sends refresh_token to POST /auth/refresh
   b. Server validates refresh_token, issues new access_token
   c. If refresh_token expired → re-login required
```

### Token Lifetimes

```
access_token:   15 minutes (short — limits exposure if stolen)
refresh_token:  7 days (longer — for session continuity)
```

### Password Hashing

```python
# Use bcrypt with work factor 12+
import bcrypt

hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12))
is_valid = bcrypt.checkpw(password.encode(), stored_hash)
```

**Never:**
- Store passwords in plaintext
- Use MD5 or SHA for passwords (too fast, no salt)
- Roll your own crypto
- Store passwords in logs

## Secrets Management

### In Code

```
NEVER:
  - Hardcode secrets in source code
  - Commit .env files to git
  - Log secrets (even partially)
  - Pass secrets as command-line arguments (visible in ps)

DO:
  - Use environment variables (injected at runtime)
  - Use a secrets manager (Vault, AWS Secrets Manager, 1Password)
  - Use .env files ONLY for local development
  - Add .env to .gitignore BEFORE first commit
  - Provide .env.example with placeholder values
```

### Rotation

```
1. Generate new secret
2. Deploy new secret alongside old (both valid)
3. Roll out code using new secret
4. Verify all instances use new secret
5. Revoke old secret
6. Total time: under 1 hour for critical secrets
```

## Dependency Vulnerability Scanning

```bash
# Node.js
npm audit
npm audit fix          # Auto-fix compatible updates

# Python
pip-audit              # PEP 665 aware
safety check           # Check installed packages

# Go
govulncheck ./...      # Official Go vuln checker

# Rust
cargo audit            # Check Cargo.lock for known vulns

# Universal
snyk test              # Multi-language scanner
trivy fs .             # Container and filesystem scanner
```

### CI Integration

Run vulnerability scanning on every PR. Block merge on HIGH/CRITICAL severity.

## Rate Limiting

### Algorithm: Token Bucket

```
BUCKET_SIZE    = 100     # Max burst
REFILL_RATE    = 10/sec  # Sustained rate
PER_KEY        = IP or API key or user ID

function allow_request(key):
    bucket = get_bucket(key)
    if bucket.tokens > 0:
        bucket.tokens -= 1
        return true
    return false  # 429 Too Many Requests
```

### What to Rate Limit

```
HIGH limit:   Static assets, health checks
MEDIUM limit: API read endpoints (100/min)
LOW limit:    Auth endpoints (5/min), write endpoints (20/min)
VERY LOW:     Password reset (3/hour), account creation (10/hour)
```

### Response Headers

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 42
X-RateLimit-Reset: 1711929600
Retry-After: 30
```

## CORS Configuration

```typescript
// Strict — specific origins only
app.use(cors({
  origin: ["https://app.example.com", "https://admin.example.com"],
  methods: ["GET", "POST", "PUT", "DELETE"],
  allowedHeaders: ["Content-Type", "Authorization"],
  credentials: true,
  maxAge: 86400,  // Preflight cache: 24 hours
}));

// NEVER in production:
app.use(cors({ origin: "*", credentials: true }));
// credentials + wildcard origin = browser rejects anyway
```

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| `origin: "*"` in CORS | Allows any site to call your API | Whitelist specific origins |
| JWT in localStorage | XSS can steal the token | Store in memory, refresh via HttpOnly cookie |
| Logging request bodies | May contain passwords/PII | Redact sensitive fields before logging |
| Rolling your own crypto | Guaranteed to be broken | Use libsodium, bcrypt, standard libs |
| No rate limiting on auth | Brute force attacks | Low rate limit on login, lockout after failures |
| Validating input only on client | Client validation is bypassable | Always validate server-side |
