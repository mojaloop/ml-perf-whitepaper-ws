# Position-Batch Handler — Bottleneck Analysis
## 1000 TPS with 70% Single-Payer Load (fsp201)

---

## 1. Context

Target: **1000 TPS, e2e p99 < 1000ms**

Test constraint: **fsp201 generates 70% of total load** (business requirement, cannot change).

| Test run | fsp201 load | e2e p99 | Status |
|----------|-------------|---------|--------|
| Baseline | 70% | 1678ms | FAILS target |
| Distributed | 40% | 843ms | PASSES target |

The 835ms difference is entirely in the transfer phase. Discovery and quote p99 are unchanged between both runs (~54ms and ~241ms respectively). This document explains why the position-batch (pos-batch) handler is the structural bottleneck.

---

## 2. Transfer Pipeline

A single transfer involves two independent sub-flows. Pos-batch appears once in each.

**PREPARE phase — payer initiates:**
```
Payer FSP: POST /transfers
  → ml-api-adapter-service
    → topic-transfer-prepare
      → cl-handler-prepare              (16 pods)
        → topic-transfer-position-batch [action=PREPARE, key=payer account]
          → cl-handler-pos-batch        ← BOTTLENECK (4 pods) — reserves payer liquidity
            → topic-notification-event
              → ml-api-adapter-handler-notification  (48 pods)
                → POST /transfers to payee FSP  (payee is notified to accept)
```

**FULFIL phase — payee responds:**
```
Payee FSP: PUT /transfers/{id}
  → ml-api-adapter-service
    → topic-transfer-fulfil
      → cl-handler-fulfil               (16 pods) — validates fulfil
        → topic-transfer-position-batch [action=COMMIT, key=payee account]
          → cl-handler-pos-batch        ← BOTTLENECK (4 pods) — settles payee position
            → topic-notification-event
              → ml-api-adapter-handler-notification  (48 pods)
                → PUT /transfers/{id} to payer FSP  (payer gets completion)
```

The pos-batch handler sits in the critical path **twice** per transfer:
- **PREPARE**: payer account (`participantCurrencyId` of fsp201) → partition 1 → reserves liquidity → notifies payee
- **COMMIT**: payee account (`participantCurrencyId` of fsp202) → partition 0 → settles position → notifies payer

---

## 3. Why Account ID Is the Partition Key

The `topic-transfer-position-batch` Kafka partition key is the participant's **`participantCurrencyId`** (account ID), set in `src/handlers/transfers/prepare.js`:

```javascript
const account = await Participant.getAccountByNameAndCurrency(
  cyrilResult.participantName,
  cyrilResult.currencyId,
  Enum.Accounts.LedgerAccountType.POSITION
)
messageKey = account.participantCurrencyId.toString()
```

**Business reason — correctness, not performance.**

Position updates must be strictly sequential per account because each transfer's liquidity check depends on the accumulated balance from all previous transfers:

```javascript
// src/models/position/batch.js
const getPositionsByAccountIdsForUpdate = async (trx, accountIds) => {
  return await knex('participantPosition')
    .transacting(trx)
    .whereIn('participantCurrencyId', accountIds)
    .forUpdate()   // ← SQL row-level lock
    .select('*')
}
```

If two transfers for fsp201 were processed concurrently on different partitions, both could read the same available balance and pass the liquidity check — resulting in an overdraft. The partition key is a correctness guarantee: **one account → one partition → one consumer → sequential processing**.

This design cannot be changed without breaking the accounting invariant.

---

## 4. The Hotspot

There are exactly **8 unique account IDs** sending messages to `topic-transfer-position-batch` (4 payers + 4 payees). With `participantCurrencyId` as the murmur2 partition key, each account ID hashes independently. Multiple accounts can collide onto the same partition.

Total messages to `topic-transfer-position-batch` = **2000/s** (1000 prepares + 1000 commits).

### Message rate per account

| Account | Role | msg/s at 1000 TPS / 70% fsp201 |
|---------|------|-------------------------------|
| fsp201 | payer PREPARE | **700/s** |
| fsp202 | payee COMMIT | **490/s** |
| fsp204 | payee COMMIT | 170/s |
| fsp206 | payee COMMIT | 170/s |
| fsp208 | payee COMMIT | 170/s |
| fsp203 | payer PREPARE | 100/s |
| fsp205 | payer PREPARE | 100/s |
| fsp207 | payer PREPARE | 100/s |

### Partition configuration: 8 partitions / 8 pods (current)

With 8 partitions matching the 8 unique account IDs, each account gets its own dedicated partition with no hash collisions. Each of the 8 pos-batch pods consumes exactly one partition.

| Partition | Account | msg/s | Pod node |
|-----------|---------|-------|----------|
| hot | fsp201 | **700/s** | sw1-n1 |
| hot | fsp202 | **490/s** | sw1-n3 |
| medium | fsp204 | 170/s | sw1-n2 or sw1-n4 |
| medium | fsp206 | 170/s | sw1-n2 or sw1-n4 |
| medium | fsp208 | 170/s | sw1-n2 or sw1-n4 |
| light | fsp203 | 100/s | distributed |
| light | fsp205 | 100/s | distributed |
| light | fsp207 | 100/s | distributed |


### Pod placement (8 pods / 8 partitions)

With 8 pods across 4 nodes, each node runs 2 pos-batch pods. The Kafka consumer group assigns one partition per pod. The hot partitions (fsp201 at 700/s, fsp202 at 490/s) land on whichever nodes Kubernetes schedules those pods at deployment time.

```
sw1-n1  →  2 pods  (may include fsp201 hot partition)
sw1-n2  →  2 pods
sw1-n3  →  2 pods  (may include fsp202 hot partition)
sw1-n4  →  2 pods
```

If both hot pods land on the same node, that node handles 700 + 490 = 1190/s, which would overload it. Node affinity rules are needed to spread the hot pods across different nodes (see Section 11).

---

## 5. DB Operations Per Batch — The Real Cost

Every single invocation of the pos-batch handler executes the following **sequential `await` calls to MySQL**, regardless of how many messages are in the batch:

| # | Operation | Inside lock? | Scales with N? |
|---|-----------|-------------|----------------|
| 1 | `knex.transaction()` → BEGIN | — | No |
| 2 | `_fetchLatestTransferStates` → SELECT transferStateChange IN (N ids) | No | Yes |
| 3 | `_fetchLatestFxTransferStates` → SELECT fxTransferStateChange | No | No (empty) |
| 4 | `_getParticipantCurrencyIds` → SELECT participantCurrency | No | No |
| 5 | `getPositionsByAccountIdsForUpdate` → **SELECT … FOR UPDATE** | **Acquires lock** | No (1 row) |
| 6 | `getTransferInfoList` → SELECT transferParticipant IN (N ids) | Yes | Yes |
| 7 | `getReservedPositionChangesByCommitRequestIds` → SELECT | Yes | No (empty) |
| 8 | `getTransferByIdsForReserve` → SELECT | Yes | No (empty) |
| 9 | **`getParticipantLimitByParticipantCurrencyLimit`** → SELECT | **Yes** | No (1 row) |
| 10 | `bulkInsertTransferStateChanges` → bulk INSERT | Yes | Yes |
| 11 | `updateParticipantPosition` → UPDATE 1 row | Yes | No |
| 12 | `trx.commit()` → COMMIT | Releases lock | No |

**12 sequential network round-trips per batch invocation**, approximately 6–8 of which execute while holding the `FOR UPDATE` row lock.

At ~2–3ms per round-trip on a loaded node: **~25–36ms minimum overhead per batch**, before processing a single message.

### Known performance issue — Step 9

`src/domain/position/binProcessor.js`, line 153–154:

```javascript
// Story #3657: The following SQL query/lookup can be optimized for performance
participantLimit = await participantFacade.getParticipantLimitByParticipantCurrencyLimit(
  accountIdMap[accountID].participantId,
  accountIdMap[accountID].currencyId,
  Enum.Accounts.LedgerAccountType.POSITION,
  Enum.Accounts.ParticipantLimitType.NET_DEBIT_CAP
)
```

This fetches fsp201's NET_DEBIT_CAP limit on **every single batch invocation**, while holding the row lock. The limit **never changes** during a test run. The codebase itself documents this as a known performance problem (Story #3657). Caching this single query would remove one round-trip from inside the lock.

---

## 6. Why the Consumer Only Picks Up ~7 Messages (Not 100)

The configmap sets:

```json
"batchSize": 100,
"consumeTimeout": 10,
"fetch.min.bytes": 1024,
"fetch.wait.max.ms": 5
```

With `sync: true`, the consumer loop is:

```
poll Kafka → wait up to fetch.wait.max.ms (5ms) → get messages → accumulate
→ if batchSize reached OR consumeTimeout elapsed → call handler
→ WAIT for handler to return (sync=true)
→ repeat
```

At 700 msg/s on partition 1, in `fetch.wait.max.ms = 5ms`, only `700 × 0.005 = 3.5 messages` arrive. The `consumeTimeout = 10ms` window fits **2 fetch calls × 3–4 messages = ~7 messages per invocation**.

`batchSize = 100` is a ceiling that is almost never reached at steady state with no backlog. The binding constraint is `consumeTimeout`.

### When does it get a full batch of 100?

Only when the Kafka partition already has 100+ messages queued as a **backlog**. When the queue is large, the broker returns messages immediately (no `fetch.wait.max.ms` wait) and the consumer fills `batchSize = 100` quickly.

---

## 7. Bimodal Throughput and Queue Oscillation

The consumer operates in two modes depending on queue depth:

| Mode | Queue depth | Effective batch | Cycle time | Service rate |
|------|-------------|-----------------|-----------|--------------|
| Small-batch | < 100 msgs | ~7 messages | 10ms wait + 35ms DB = 45ms | ~156 msg/s |
| Full-batch | ≥ 100 msgs | 100 messages | 0ms wait + 35ms DB = 35ms | ~2857 msg/s |

With 700 msg/s arriving on partition 1:

**Small-batch mode** → queue builds at `700 − 156 = 544 msg/s`
→ reaches 100 messages in `100/544 × 1000 ≈ 184ms`

**Full-batch mode** → queue drains at `2857 − 700 = 2157 msg/s`
→ a queue of 400 drains in `400/2157 × 1000 ≈ 185ms`

The system oscillates with a cycle of approximately **370ms** and a queue depth oscillating between **0 and ~400 messages**.

```
Queue
 400 │    ╲         ╲         ╲
     │     ╲         ╲         ╲
 100 │      ╲         ╲         ╲      (full-batch threshold)
     │  /    ╲    /    ╲    /    ╲
   0 │ /      ╲  /      ╲  /      ╲
     └─────────────────────────────→ time (~370ms/cycle)
       ←184ms→ ←185ms→
```

**p99 impact:** A transfer that arrives at queue peak (~400 messages) waits:

```
400 / 2857 × 1000 ≈ 140ms  (queue wait in pos-batch)
```

This happens **twice per transfer** (prepare and commit phases):

```
140ms × 2 = 280ms additional p99 latency from pos-batch alone
```

Combined with similar (smaller) oscillations in the prepare and fulfil handlers, this accounts for the observed p99 degradation of **~835ms** between 70% and 40% fsp201 tests.

---

## 8. Why Config Tuning Did Not Help

### Attempt: `consumeTimeout: 100ms, batchSize: 500`

**Result: e2e p99 degraded from 1678ms → 3579ms (2× worse).**

With `sync: true`, the cycle time is:
```
cycle = handler_processing_time + consumeTimeout_wait
```

When the queue is below batchSize, the consumer waits a full 100ms after each handler return. Each transfer passes through pos-batch twice, adding up to **200ms mandatory wait** before even accounting for queue depth. The added dead time overwhelmed any benefit from larger batches.

### Why increasing TPS would not fix it either

For the queue to stay permanently above the batchSize threshold, the full-batch service rate (2857/s) must not exceed the arrival rate:

```
arrival_rate × batch_processing_time ≥ batchSize
arrival_rate × 0.035s ≥ 100
arrival_rate ≥ 2857 msg/s
→ total TPS ≥ 2857 / 0.70 ≈ 4082 TPS
```

The queue only stays persistently above 100 messages at **~4000 total TPS** — at which point MySQL, the prepare handler, and every other component would be saturated long before the pos-batch handler benefits.

---

## 9. Node Load Impact

### At 70% fsp201 (1678ms p99)

| Node | LOAD5/vCPU peak | Pos-batch partition |
|------|----------------|---------------------|
| sw1-n1 | ~75%+ | Partition 1 — fsp201 (700/s) |
| sw1-n3 | ~60–70% | Partition 0 — fsp202 (490/s) |
| sw1-n2 | ~44% | Partition 3 (light) |
| sw1-n4 | ~46% | Partition 2 (light) |

### At 40% fsp201 (843ms p99)

| Node | LOAD5/vCPU peak | Pos-batch partition |
|------|----------------|---------------------|
| sw1-n1 | ~60% | Partition 1 — fsp201 (400/s) |
| sw1-n3 | ~56% | Partition 0 — fsp202 (280/s) |
| sw1-n2 | ~44% | Partition 3 (200/s) |
| sw1-n4 | ~46% | Partition 2 (200/s) |

Moving the hot pods to less-loaded nodes (n2/n4) reduces the per-round-trip MySQL latency from ~3ms to ~1.5ms, cutting batch overhead from ~35ms to ~18ms. This reduces oscillation amplitude — smaller queue peaks, shorter p99 wait — but does **not eliminate the oscillation**, since service rate is still bimodal.

---

## 10. Root Cause Summary

The bottleneck is a combination of three factors that compound each other:

1. **Structural hotspot**: the `participantCurrencyId` partition key concentrates 70% of all position messages onto one Kafka partition, served by one consumer pod. This is correct by design and cannot be changed without breaking accounting correctness.

2. **Per-batch DB overhead**: 12 sequential MySQL round-trips per handler invocation, regardless of batch size. Fixed overhead dominates at the small effective batch sizes (~7 messages) produced by `consumeTimeout = 10ms` at 700 msg/s. This creates a bimodal service rate (156/s vs 2857/s) that drives queue oscillation.

3. **Known unoptimized query** (Story #3657): `getParticipantLimitByParticipantCurrencyLimit` is called inside the open transaction (while holding the `FOR UPDATE` lock) on every batch invocation, fetching data that does not change during the test.

---

## 11. Options to Address

| Option | Impact | Effort | Notes |
|--------|--------|--------|-------|
| **Node placement** (pin hot pods to n2/n4) | Moderate | Low | Reduces round-trip latency; does not eliminate oscillation |
| **Cache participant limit** (Story #3657) | High | Medium | Removes 1 round-trip from inside the lock; pure code change |
| **Batch pre-fetch queries** (run steps 2–4 in parallel) | High | Medium | 3 independent SELECTs before lock could run concurrently with `Promise.all` |
| **Change partition key** | Would break correctness | N/A | Not viable |
| **Reduce single-payer concentration** | Eliminates hotspot | Test design change | Validated: 40% fsp201 achieves 843ms p99 |
| **Larger hardware for hot partition node** | Moderate | High | Dedicated node with no competing workloads; not minimum-infra |
