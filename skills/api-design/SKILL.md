---
name: api-design
description: "REST and RPC API design patterns: resource naming, HTTP method semantics, pagination, error responses, versioning, backward compatibility, rate limiting, and OpenAPI/JSON Schema generation. Use when designing APIs, reviewing API code, or building backends."
license: MIT
metadata:
  pattern: api-design
  languages: typescript, python, go
---

# API Design: Building APIs That Last

Good APIs are consistent, predictable, and hard to misuse. This skill covers the patterns that make APIs a pleasure to consume and maintain.

## Resource Naming

### URL Structure

```
GET    /api/v1/users              # List users
GET    /api/v1/users/123          # Get user by ID
POST   /api/v1/users              # Create user
PUT    /api/v1/users/123          # Replace user
PATCH  /api/v1/users/123          # Partial update
DELETE /api/v1/users/123          # Delete user

# Nested resources
GET    /api/v1/users/123/orders          # List user's orders
GET    /api/v1/users/123/orders/456      # Get specific order
POST   /api/v1/users/123/orders          # Create order for user

# Actions (when CRUD doesn't fit)
POST   /api/v1/users/123/activate        # Custom action
POST   /api/v1/orders/456/cancel         # Custom action
```

### Naming Rules

```
1. Use plural nouns for collections:     /users NOT /user
2. Use kebab-case for multi-word:        /order-items NOT /orderItems
3. No verbs in URLs:                     POST /orders NOT POST /create-order
4. No trailing slashes:                  /users NOT /users/
5. Lowercase only:                       /users NOT /Users
6. Resource IDs in path, filters in query: /users?role=admin NOT /users/admins
```

## HTTP Method Semantics

| Method | Idempotent | Safe | Body | Use For |
|---|---|---|---|---|
| GET | Yes | Yes | No | Retrieve resource(s) |
| POST | No | No | Yes | Create resource, trigger action |
| PUT | Yes | No | Yes | Replace entire resource |
| PATCH | No* | No | Yes | Partial update |
| DELETE | Yes | No | Optional | Remove resource |
| HEAD | Yes | Yes | No | Check existence, get headers |
| OPTIONS | Yes | Yes | No | CORS preflight, API discovery |

*PATCH can be made idempotent with JSON Merge Patch or if-match headers.

### Idempotency

Idempotent means calling the operation N times has the same effect as calling it once. This is critical for retry safety.

```
GET  /users/123     → Same user every time ✓
PUT  /users/123     → Same replacement every time ✓
DELETE /users/123   → Deleted (or already deleted) every time ✓
POST /users         → Creates NEW user every time ✗ (not idempotent)
```

**Making POST idempotent:** Use an idempotency key:
```
POST /api/v1/payments
Idempotency-Key: req_abc123
Content-Type: application/json

{"amount": 100, "currency": "USD"}

# Same Idempotency-Key → returns cached result, no duplicate payment
```

## Request/Response Format

### Standard Response Envelope

```json
// Success
{
  "data": {
    "id": "123",
    "email": "user@example.com",
    "name": "Alice"
  }
}

// Success (list)
{
  "data": [
    {"id": "123", "name": "Alice"},
    {"id": "456", "name": "Bob"}
  ],
  "pagination": {
    "total": 142,
    "page": 1,
    "per_page": 20,
    "next_cursor": "eyJpZCI6NDU2fQ=="
  }
}

// Error
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Email is required",
    "details": [
      {"field": "email", "constraint": "required"}
    ]
  }
}
```

### HTTP Status Codes

```
Success:
  200 OK              — General success (GET, PUT, PATCH, DELETE)
  201 Created         — Resource created (POST)
  202 Accepted        — Async operation accepted
  204 No Content      — Success, no body (DELETE)

Client Errors:
  400 Bad Request     — Invalid input
  401 Unauthorized    — Not authenticated
  403 Forbidden       — Authenticated but not authorized
  404 Not Found       — Resource doesn't exist
  409 Conflict        — State conflict (duplicate, version mismatch)
  422 Unprocessable   — Valid syntax but semantic error
  429 Too Many Reqs   — Rate limited

Server Errors:
  500 Internal Error  — Bug in server code
  502 Bad Gateway     — Upstream service failed
  503 Unavailable     — Temporarily overloaded
  504 Gateway Timeout — Upstream service timed out
```

## Pagination

### Cursor-Based (Recommended)

```
GET /api/v1/users?limit=20&cursor=eyJpZCI6NDU2fQ==

Response:
{
  "data": [...],
  "pagination": {
    "next_cursor": "eyJpZCI6NDc2fQ==",
    "has_more": true
  }
}
```

**Advantages:** Stable under concurrent writes, no page drift, efficient (seeks to cursor position).

### Offset-Based

```
GET /api/v1/users?limit=20&offset=40

Response:
{
  "data": [...],
  "pagination": {
    "total": 142,
    "limit": 20,
    "offset": 40
  }
}
```

**Disadvantages:** Page drift on inserts/deletes, O(n) for large offsets. Use only when random page access is needed.

### Pagination Rules

```
1. Default limit: 20
2. Max limit: 100 (prevent abuse)
3. Always return pagination metadata
4. Use cursor-based for feeds, timelines, large datasets
5. Use offset-based for admin UIs, reports
```

## Versioning

### URL Path Versioning (Recommended)

```
/api/v1/users
/api/v2/users
```

**Why:** Explicit, easy to route, easy to deprecate, cache-friendly.

### Header Versioning

```
GET /api/users
Accept: application/vnd.myapp.v2+json
```

**Why not:** Harder to test (can't just change URL), harder to cache, easy to forget.

### Version Lifecycle

```
1. v1 is STABLE — no breaking changes
2. v2 is CURRENT — active development
3. v1 deprecated — 6-month warning, Sunset header
4. v1 removed — returns 410 Gone

Sunset: Sat, 01 Oct 2026 00:00:00 GMT
Deprecation: true
```

## Backward Compatibility

### Safe Changes (Non-Breaking)

```
✓ Add a new optional field to response
✓ Add a new optional query parameter
✓ Add a new endpoint
✓ Add a new enum value (if client handles unknown values)
✓ Relax a validation constraint (accept wider input)
```

### Breaking Changes (Require New Version)

```
✗ Remove a field from response
✗ Rename a field
✗ Change a field's type
✗ Add a required field to request
✗ Tighten a validation constraint
✗ Change URL structure
✗ Change authentication mechanism
✗ Change error response format
```

### The Expand-Contract Pattern

For evolving APIs without breaking clients:

```
Phase 1 (Expand): Add new field alongside old
  {"name": "Alice", "full_name": "Alice Smith"}

Phase 2 (Migrate): Update all clients to use new field

Phase 3 (Contract): Remove old field in next major version
  {"full_name": "Alice Smith"}
```

## OpenAPI / JSON Schema

### Generating from Code

```python
# FastAPI autogen. OpenAPI
from fastapi import FastAPI
app = FastAPI(title="My API", version="1.0.0")

@app.get("/users/{user_id}", response_model=User)
def get_user(user_id: int):
    ...

# OpenAPI spec at /openapi.json
# Swagger UI at /docs
```

```typescript
// Express with tsoa
import { Controller, Get, Route } from "tsoa";

@Route("users")
export class UserController extends Controller {
  @Get("{userId}")
  public async getUser(userId: string): Promise<User> {
    ...
  }
}
// Generate: npx tsoa spec → openapi.json
```

### Schema-First Design

Alternatively, write the schema first, generate code:

```yaml
# openapi.yaml
paths:
  /users/{userId}:
    get:
      operationId: getUser
      parameters:
        - name: userId
          in: path
          required: true
          schema:
            type: string
      responses:
        200:
          description: User found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/User'
        404:
          $ref: '#/components/responses/NotFound'
```

## Authentication in APIs

### Bearer Token

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
```

### API Key

```
# Header (preferred)
X-API-Key: sk_live_abc123

# Query param (less secure, appears in logs)
/api/v1/users?api_key=sk_live_abc123
```

### Which to Use

| Method | Use Case |
|---|---|
| Bearer JWT | User-facing APIs with sessions |
| API Key | Service-to-service, developer APIs |
| OAuth2 | Third-party integrations |
| mTLS | Infrastructure, zero-trust networks |

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| Verbs in URLs | `POST /createUser` breaks REST model | `POST /users` |
| 200 for errors | Client can't distinguish success/failure | Use proper status codes |
| No pagination | 100K records in one response | Always paginate lists |
| Breaking changes in minor version | Clients break silently | New major version for breaks |
| Exposing internal IDs | Sequential IDs leak business data | Use UUIDs or opaque IDs |
| No rate limiting | Single client can DoS your API | Rate limit per client/key |
| Inconsistent naming | `user_name` vs `userName` vs `UserName` | Pick one convention, enforce it |
