# Run 20260713T143556 — Scenario #1: plaintext baseline at 650 TPS

**HEADLINE: steady-state e2e p99 = 946ms (σ 122ms), 1,012,461 transfers in
steady state, 99.97% success — <1s GOAL MET at 650 TPS, 30% above the 500 TPS
design target. Full-run aggregate p99 1008ms. Validity gate exact
(fulfil/prepare=1.000, notif/prepare=2.000). 650 TPS is the verified maximum
for this hardware: 700 TPS sustains cleanly (99.94%) but lands at p99
~1.06-1.15s across two attempts and two pod placements.**

## Security composition

| Layer | Mechanism |
|---|---|
| DFSP ↔ switch (both directions) | None — plain HTTP |
| service ↔ service | None |
| apps ↔ Kafka | None — plaintext |
| apps ↔ MySQL | None — plaintext |
| Pod-pod encryption | None (WireGuard disabled, no mesh) |

## Configuration deltas active in this run

- MySQL: `max_connections=1500`, CPU limit 4.0 (dedicated 4-vCPU node)
- Kafka: CPU limit 3.5
- account-lookup-service: 10 replicas
- fsp202 sim backend: 2 replicas (dual-seeded)
- Sim backends restarted ~2 runs earlier (in-memory DB growth practice)

## Node CPU (steady window)

Switch: n5 81.8%, n4 75.4%, n1 74.8%, n3 69.9%, n2 67.7%; mysql 69.8%,
kafka 66.0%. DFSP: fsp201 76.4%, fsp202 72.1%, others ≤54%.

Full data: `steady-state.md`, `summary.json`, raw k6 logs in this directory.
