---
name: event-driven-architecture
description: "Asynchronous communication patterns: pub/sub, message queues, event sourcing, CQRS, webhook design (idempotency, retry, signatures), dead letter queues, eventual consistency, and the saga pattern for distributed transactions. Use when building systems that react to events, integrate with external services, or need loose coupling between components."
license: MIT
metadata:
  pattern: event-driven-architecture
  languages: typescript, python, go
---

# Event-Driven Architecture: Asynchronous Communication Patterns

Event-driven architecture decouples producers from consumers. Instead of calling a service directly, you emit an event and let interested parties react. This enables loose coupling, independent scaling, and resilience.

## Core Concepts

### Events vs Commands vs Queries

```
EVENT:   "OrderPlaced"       — Something that happened (past tense, immutable)
COMMAND: "PlaceOrder"        — Request to do something (imperative, may fail)
QUERY:   "GetOrder(id)"      — Request for information (no side effects)

Events are FACTS. They cannot be rejected — they already happened.
Commands are REQUESTS. They can fail, be rejected, or be retried.
```

### Event Anatomy

```json
{
  "id": "evt_abc123",
  "type": "order.placed",
  "source": "order-service",
  "time": "2026-04-01T12:00:00Z",
  "data": {
    "order_id": "ord_789",
    "customer_id": "cust_456",
    "total": 99.99,
    "items": [{"sku": "WIDGET-1", "qty": 2}]
  },
  "metadata": {
    "correlation_id": "req_xyz",
    "causation_id": "cmd_place_order_xyz"
  }
}
```

### Event Naming Convention

```
<entity>.<past-tense-verb>

user.created
user.email.verified
order.placed
order.shipped
payment.succeeded
payment.failed
inventory.reserved
inventory.released
```

## Pub/Sub Pattern

Producers publish events to a topic. Consumers subscribe to topics they care about. Producers don't know (or care) who's listening.

```
                    ┌─── Email Service (sends confirmation)
                    │
Order Service ──→ [order.placed topic] ──→ Inventory Service (reserves stock)
                    │
                    └─── Analytics Service (tracks metrics)
```

### Implementation

```typescript
// Publisher — knows nothing about consumers
async function placeOrder(order: Order) {
  await db.orders.insert(order);
  
  await eventBus.publish({
    type: "order.placed",
    data: { order_id: order.id, customer_id: order.customerId, total: order.total }
  });
}

// Consumer — knows nothing about publisher
eventBus.subscribe("order.placed", async (event) => {
  await sendConfirmationEmail(event.data.customer_id, event.data.order_id);
});

// Another consumer — same event, different reaction
eventBus.subscribe("order.placed", async (event) => {
  await reserveInventory(event.data.order_id);
});
```

### Delivery Guarantees

```
At-most-once:   Fire and forget. Events may be lost.
                Use: logging, metrics (loss is acceptable)

At-least-once:  Retry until acknowledged. Events may be duplicated.
                Use: most business events (with idempotent consumers)

Exactly-once:   Guaranteed single delivery. Hard/impossible at scale.
                Use: financial transactions (approximate via idempotency)
```

**Default to at-least-once + idempotent consumers.** This is the sweet spot of reliability and simplicity.

## Message Queues

Unlike pub/sub (fan-out to all subscribers), queues deliver each message to **exactly one** consumer in a consumer group. Used for work distribution.

```
                    ┌─ Worker 1 (processes order A)
[order queue] ──────┼─ Worker 2 (processes order B)
                    └─ Worker 3 (processes order C)
```

### Queue Patterns

```
Point-to-Point:  One producer → one consumer
                 Use: task processing, job queues

Competing Consumers: One queue → multiple workers (load balancing)
                     Use: CPU-intensive processing, parallel execution

Request-Reply:   Producer sends to request queue, consumer replies to reply queue
                 Use: synchronous-style RPC over async transport
```

### Acknowledgment

```
function processMessage(msg):
    try:
        result = handle(msg.data)
        msg.ack()           # Remove from queue (processed successfully)
    catch RetryableError:
        msg.nack()          # Return to queue (will be redelivered)
    catch TerminalError:
        msg.reject()        # Send to dead letter queue (won't retry)
```

## Dead Letter Queue (DLQ)

Messages that fail repeatedly are moved to a DLQ for investigation:

```
Main Queue → Consumer → (fails 3x) → Dead Letter Queue
                                           ↓
                                     Manual review
                                     Fix and replay
                                     Or discard
```

### Configuration

```
MAX_RETRIES = 3           # Attempts before DLQ
RETRY_DELAY = [1s, 5s, 30s]  # Exponential backoff between retries
DLQ_RETENTION = 14 days   # How long to keep failed messages
```

### DLQ Processing

```
1. Monitor DLQ size (alert if growing)
2. Investigate failed messages (read error metadata)
3. Fix the root cause (bug in consumer, bad data)
4. Replay messages from DLQ to main queue
5. If unfixable, archive and discard
```

## Webhook Design

Webhooks are HTTP callbacks — your service calls an external URL when an event occurs.

### Sending Webhooks

```
POST https://customer-endpoint.com/webhooks
Content-Type: application/json
X-Webhook-ID: wh_abc123
X-Webhook-Timestamp: 1711929600
X-Webhook-Signature: sha256=a1b2c3...

{
  "id": "evt_abc123",
  "type": "payment.succeeded",
  "data": { ... }
}
```

### Signature Verification

Sign every webhook so the receiver can verify authenticity:

```python
import hmac, hashlib

def sign_webhook(payload: bytes, secret: str) -> str:
    signature = hmac.new(
        secret.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()
    return f"sha256={signature}"

# Receiver verifies:
def verify_webhook(payload: bytes, signature: str, secret: str) -> bool:
    expected = sign_webhook(payload, secret)
    return hmac.compare_digest(signature, expected)  # Constant-time comparison
```

### Idempotency Keys

Include a unique event ID so receivers can deduplicate:

```
X-Webhook-ID: wh_abc123

# Receiver tracks processed IDs:
if wh_id in processed_webhooks:
    return 200  # Already handled, skip
processed_webhooks.add(wh_id, ttl=48h)
process(event)
```

### Retry Strategy

```
Attempt 1: Immediate
Attempt 2: 1 minute
Attempt 3: 5 minutes
Attempt 4: 30 minutes
Attempt 5: 2 hours
Attempt 6: 8 hours
Attempt 7: 24 hours (final)

Success: HTTP 2xx response
Failure: Anything else (4xx, 5xx, timeout, connection error)
Final failure: Disable webhook endpoint, notify the customer
```

### Webhook Best Practices

```
1. Timeout: 30 seconds max per delivery attempt
2. Payload: keep small (< 64KB), include IDs, let receiver fetch full data
3. Signatures: sign every request with HMAC-SHA256
4. Idempotency: include unique event ID in header
5. Retry: exponential backoff, max 7 attempts over 24 hours
6. Ordering: do NOT guarantee order (consumers must handle out-of-order)
7. Versioning: include schema version in payload
```

## Event Sourcing

Instead of storing current state, store the sequence of events that produced the state:

```
Traditional:
  users table: { id: 1, name: "Alice", email: "alice@new.com" }

Event Sourced:
  events table:
    { type: "user.created", data: { name: "Alice", email: "alice@old.com" } }
    { type: "user.email.changed", data: { email: "alice@new.com" } }
    
  Current state = replay all events in order
```

### When to Use Event Sourcing

```
YES:
  - Audit trail is required (finance, healthcare, legal)
  - Need to reconstruct state at any point in time
  - Complex domain with many state transitions
  - Need to derive multiple read models from same events

NO:
  - Simple CRUD with no audit requirements
  - High-frequency updates (too many events)
  - Simple domain with few state transitions
  - Team is unfamiliar with the pattern
```

### Snapshots

Replaying 10 million events is slow. Take periodic snapshots:

```
Snapshot at event 9,999,000: { current_state }
To rebuild: load snapshot + replay events 9,999,001 to present
```

## CQRS (Command Query Responsibility Segregation)

Separate the write model (commands) from the read model (queries):

```
Write Side:                    Read Side:
  PlaceOrder (command)           GetOrderSummary (query)
       ↓                             ↑
  Order Aggregate              Read-optimized view
       ↓                             ↑
  OrderPlaced (event) ──────→  Projection updates view
```

### Why CQRS

```
Write model: normalized, consistent, enforces business rules
Read model:  denormalized, fast, optimized for specific queries

Separate scaling: reads typically 10-100x writes
Separate optimization: write for consistency, read for speed
```

## Saga Pattern

Distributed transactions across services using a choreography of events:

```
Order Saga:
  1. OrderService:    CreateOrder      → emit order.created
  2. PaymentService:  ProcessPayment   → emit payment.succeeded OR payment.failed
  3. InventoryService: ReserveStock    → emit stock.reserved OR stock.insufficient
  4. ShippingService: ScheduleShipment → emit shipment.scheduled

Compensation (rollback):
  If payment.failed:
    → Cancel order (no inventory/shipping needed)
  
  If stock.insufficient:
    → Refund payment
    → Cancel order
  
  If shipment.failed:
    → Release stock
    → Refund payment
    → Cancel order
```

### Saga Rules

```
1. Each step must have a compensating action (undo)
2. Compensations are best-effort (may need manual intervention)
3. Track saga state (which steps completed, which pending)
4. Set timeouts for each step (don't wait forever)
5. Make each step idempotent (retries are inevitable)
```

## Eventual Consistency

In event-driven systems, different services may have different views of the state for a brief period:

```
Order placed at t=0
  Order Service: order exists     (t=0, immediate)
  Email Service: email sent       (t=2s, after processing event)
  Analytics:     order counted    (t=5s, after batch processing)
  Search Index:  order searchable (t=30s, after reindexing)
```

### Managing User Expectations

```
1. Read-your-writes: After a write, redirect to a page that reads from
   the write model (not the eventually-consistent read model)

2. Optimistic UI: Show the change immediately in the UI, reconcile
   when the event is confirmed

3. Explicit status: "Your order is being processed" instead of
   pretending it's instantly complete
```

## Anti-Patterns

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| Events with entity name only | "User" tells nothing — created? deleted? | Past-tense verb: "user.created" |
| Giant event payloads | Coupling, bandwidth, storage waste | Include IDs, let consumers fetch details |
| Guaranteed ordering | Extremely expensive at scale | Design consumers to handle out-of-order |
| No dead letter queue | Failed messages disappear forever | Always configure a DLQ |
| Synchronous in disguise | Publish event, then poll for result | Accept eventual consistency or use request-reply |
| No idempotency | Duplicate events cause duplicate side effects | Idempotency keys on all consumers |
| Event sourcing everything | Massive complexity for simple CRUD | Use only where audit trail or time-travel is needed |
